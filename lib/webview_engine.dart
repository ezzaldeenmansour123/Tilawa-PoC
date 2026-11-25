// WebView adapter: hosts @tilawa/core/web and translates its events.
//
// Flow:
//   1. ModelManager has downloaded + SHA-verified the model + ref-v2.json.
//   2. LocalServer serves assets/web/* + the model files on 127.0.0.1.
//   3. WebView loads the page; the JS bridge (web/src/bridge.js) calls
//      createTilawa with self-hosted assetBase + wasmPaths, then reports
//      every engine event back through the `TilawaBridge` JavaScriptChannel.
//   4. This class parses those events into SpeechEngine types and appends
//      them to the session EventLog.
//
// Known unknowns (to be measured on the S22 Ultra, NOT assumed):
//   - Whether the WebView grants microphone access after the app-level
//     RECORD_AUDIO permission (webview_flutter has no onPermissionRequest
//     API; if the WebView denies the mic, this adapter fails loudly with
//     reason "unavailable" and the PoC records NO-GO for the WebView path).
//   - Whether WebGPU is available inside the WebView (the `backend` field
//     of the capabilities event tells us: "webgpu" | "wasm" | "cpu").
//   - WASM is single-threaded in Android WebView (no SharedArrayBuffer),
//     so expect slower-than-desktop highlighting; the metrics will show it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

import 'event_log.dart';
import 'local_server.dart';
import 'model_manager.dart';
import 'models.dart';
import 'speech_engine.dart';

class WebViewEngine implements SpeechEngine {
  WebViewEngine({required this.modelManager});

  final ModelManager modelManager;

  WebViewController? _controller;
  LocalServer? _server;
  final _events = StreamController<Object>.broadcast();
  EngineCapabilities? _capabilities;
  EventLog? _log;
  String? _tier;
  // "surah:ayah" -> display words, from the engine's own ref-v2.json.
  Map<String, List<String>>? _referenceWords;
  bool _listening = false;

  @override
  EngineCapabilities? get capabilities => _capabilities;

  @override
  Future<EngineCapabilities> load({
    required String tier,
    void Function(double fraction)? onProgress,
  }) async {
    _tier = tier;
    final info = await modelManager.status(tier);
    if (info.status != ModelStatus.ready) {
      throw SpeechEngineException(
          'النموذج غير جاهز: ${info.error ?? 'غير مثبَّت'}');
    }
    // The WASM runtime must be present too (downloaded with the model —
    // see ModelManager.download). Without it loadWebModel fails with a
    // cryptic bridge error; fail here instead, with an actionable message.
    if (!await modelManager.ortWasmReady()) {
      throw SpeechEngineException(
          'ملفات تشغيل المحرك (WASM) غير موجودة — نزّلها من تبويب «النموذج» '
          '(زر التنزيل ينزّل النموذج والمرجع وملفات WASM معاً).');
    }
    // Load the reference words for the passage display (from the engine's
    // own ref-v2.json — never invented text).
    final refText = await modelManager.referenceFile.readAsString();
    final ref = jsonDecode(refText) as Map<String, dynamic>;
    final ayahs = ref['ayahs'] as List;
    if (ayahs.length != 6236) {
      throw SpeechEngineException(
          'المرجع لا يحتوي 6236 آية (وجد ${ayahs.length})');
    }
    _referenceWords = {
      for (final a in ayahs)
        '${(a as Map)['s']}:${a['a']}':
            ((a['w'] as List).cast<String>()),
    };

    _server ??= await LocalServer.start(
      Directory(modelManager.referenceFile.parent.path),
    );
    _controller ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // The page re-fires this on every load; complete only the
            // completer of the current load() call.
            if (_pageLoaded != null && !_pageLoaded!.isCompleted) {
              _pageLoaded!.complete();
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'TilawaBridge',
        onMessageReceived: _onBridgeMessage,
      );
    // NOTE: microphone permission is requested by the UI (permission_handler)
    // BEFORE load() is called. If the WebView still refuses getUserMedia,
    // the bridge reports {type:"error", reason:"denied"|"unavailable"|
    // "insecure-context"} and load() throws — recorded as a NO-GO data point.
    _pageLoaded = Completer<void>();
    await _controller!.loadRequest(Uri.parse('${_server!.baseUrl}tilawa.html'));
    await _pageLoaded!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw SpeechEngineException('انتهت مهلة تحميل صفحة المحرك'),
    );
    final completer = Completer<EngineCapabilities>();
    _loadCompleter = completer;
    await _controller!.runJavaScript(
      'window.TilawaPoc.init(${jsonEncode({
        'assetBase': '${_server!.baseUrl}',
        'tier': tier,
        'modelUrl': '${_server!.baseUrl}models/model-$tier.onnx',
        'referenceUrl': '${_server!.baseUrl}models/ref-v2.json',
        'wasmPaths': '${_server!.baseUrl}ort/$kOrtWebVersion/',
      })});',
    );
    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw SpeechEngineException(
          'انتهت مهلة تحميل النموذج (120 ثانية)'),
    );
  }

  Completer<EngineCapabilities>? _loadCompleter;
  Completer<void>? _pageLoaded;

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    final data = jsonDecode(message.message) as Map<String, dynamic>;
    final type = data['type'] as String?;
    switch (type) {
      case 'ready':
        final caps = EngineCapabilities.fromJson(
          (data['capabilities'] as Map).cast<String, dynamic>(),
        );
        _capabilities = caps;
        _loadCompleter?.complete(caps);
        _loadCompleter = null;
        await _log?.append('capabilities',
            data['capabilities'] as Map<String, dynamic>,
            audioMs: null);
      case 'error':
        final err = SpeechEngineException(
          (data['message'] ?? 'خطأ من المحرك') as String,
          reason: data['reason'] as String?,
        );
        if (_loadCompleter != null) {
          _loadCompleter!.completeError(err);
          _loadCompleter = null;
        } else {
          _events.addError(err);
        }
      case 'position':
        final payload = (data['event'] as Map).cast<String, dynamic>();
        final ev = _parsePosition(payload);
        await _log?.append('position', payload, audioMs: ev.timeMs);
        _events.add(ev);
      case 'checker':
        final payload = (data['event'] as Map).cast<String, dynamic>();
        final ev = _parseChecker(payload);
        await _log?.append('checker', payload, audioMs: ev.timeMs);
        _events.add(ev);
      case 'modelLoadMs':
        await _log?.append('meta', {
          'modelLoadMs': data['ms'],
          'backend': data['backend'],
        }, audioMs: null);
    }
  }

  PositionEvent _parsePosition(Map<String, dynamic> p) {
    final observed = ((p['observed'] as List?) ?? const [])
        .map((o) => RefWord.fromJson((o['word'] as Map).cast<String, dynamic>()))
        .toList();
    final expected = p['expected'] == null
        ? null
        : RefWord.fromJson((p['expected'] as Map).cast<String, dynamic>());
    return PositionEvent(
      timeMs: (p['timeMs'] as num).toInt(),
      observed: observed,
      confidence: ((observed.isNotEmpty
                  ? (p['observed'][0]['confidence'] as num?)?.toDouble()
                  : null) ??
              0.0),
      state: trackStateFromString((p['state'] ?? 'acquiring') as String),
      expected: expected,
    );
  }

  CheckerEvent _parseChecker(Map<String, dynamic> c) {
    final loc = (c['location'] as Map).cast<String, dynamic>();
    return CheckerEvent(
      id: (c['id'] ?? '') as String,
      timeMs: (c['timeMs'] as num).toInt(),
      state: checkerStateFromString((c['state'] ?? 'suspected') as String),
      errorClass: errorClassFromString((c['errorClass'] ?? '') as String) ??
          ErrorClass.wrongWord,
      location: RefWord.fromJson(loc),
      expectedPhonemes: c['expected'] as String?,
      observedPhonemes: c['observed'] as String?,
    );
  }

  @override
  Stream<Object> startSession({
    required SessionMode mode,
    Passage? passage,
  }) {
    if (_controller == null || _capabilities == null) {
      throw SpeechEngineException('حمّل النموذج أولاً (load قبل startSession)');
    }
    if (mode == SessionMode.memorization && passage == null) {
      throw ArgumentError('memorization requires a passage');
    }
    _listening = true;
    _controller!.runJavaScript(
      'window.TilawaPoc.startSession(${jsonEncode({
        'mode': mode.name,
        'surah': passage?.surah,
        'fromAyah': passage?.fromAyah,
        'toAyah': passage?.toAyah,
      })});',
    );
    return _events.stream;
  }

  /// Called by the UI when a session starts, so the log carries the
  /// wall-clock anchor needed for latency math (see LogMetrics).
  Future<void> beginLog({
    required String sessionId,
    required Map<String, dynamic> meta,
  }) async {
    _log = await EventLog.create(sessionId: sessionId, sessionMeta: {
      ...meta,
      'sessionStartedWallMs': DateTime.now().millisecondsSinceEpoch,
      'tier': _tier,
      'backend': _capabilities?.backend,
      'modelVersion': _capabilities?.modelVersion,
      'modelSha256': _capabilities?.modelSha256,
    });
  }

  @override
  Future<void> endSession() async {
    if (!_listening) return;
    _listening = false;
    await _controller?.runJavaScript('window.TilawaPoc.stopSession();');
    await _log?.append('meta', {'event': 'session-ended'}, audioMs: null);
    _log = null;
  }

  @override
  List<List<String>>? passageWords(Passage passage) {
    final ref = _referenceWords;
    if (ref == null) return null;
    // _referenceWords maps "surah:ayah" -> display words; look the passage
    // up directly by (surah, ayah).
    final out = <List<String>>[];
    for (var a = passage.fromAyah; a <= passage.toAyah; a++) {
      final words = ref['${passage.surah}:$a'];
      if (words == null) return null;
      out.add(words);
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    await endSession();
    await _controller?.runJavaScript(
        'window.TilawaPoc && window.TilawaPoc.dispose();');
    await _server?.stop();
    await _events.close();
  }
}

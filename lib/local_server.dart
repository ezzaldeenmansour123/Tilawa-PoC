// Localhost server that gives the WebView a SECURE CONTEXT.
//
// Why: `tilawa.listen()` needs a secure context (https or localhost).
// Files loaded from Flutter assets (`loadFlutterAsset`) are NOT a secure
// context, so `getUserMedia` would reject with MicrophoneError
// ("insecure-context"). Serving the same files from http://127.0.0.1:<port>/
// IS a secure context (localhost is a potentially trustworthy origin).
//
// The server binds 127.0.0.1 only (never 0.0.0.0), serves only the PoC web
// directory + the downloaded model files, and stops with the engine.
// No audio ever goes through this server — the microphone goes straight
// from the WebView's getUserMedia into the engine.

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

class LocalServer {
  LocalServer._(this._server, this._modelDir);
  final HttpServer _server;
  final Directory _modelDir;

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port/';

  static Future<LocalServer> start(Directory modelDir) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = LocalServer._(server, modelDir);
    server.listen(s._handle);
    return s;
  }

  Future<void> stop() => _server.close(force: true);

  static const _mime = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.wasm': 'application/wasm',
    '.onnx': 'application/octet-stream',
    '.css': 'text/css; charset=utf-8',
  };

  /// Cross-origin isolation headers (COOP + COEP + CORP), applied to
  /// EVERY response the server sends.
  ///
  /// Why this matters — fixed 2026-11-25 after the poc-9 phone test:
  /// onnxruntime-web >= 1.19 ships ONLY multi-threaded WASM builds
  /// (ort-wasm-simd-threaded.wasm); the single-threaded files
  /// (ort-wasm-simd.wasm, ort-wasm.wasm) do NOT exist in the package,
  /// so the loader 404s on them whenever numThreads == 1. And
  /// @tilawa/core/web sets numThreads = 1 whenever the page is NOT
  /// cross-origin isolated. Android WebView DOES support SharedArrayBuffer
  /// — it is gated on cross-origin isolation (Chromium >= 92), exactly
  /// like desktop Chrome — so serving COOP: same-origin + COEP:
  /// require-corp makes `crossOriginIsolated === true`, lets the loader
  /// use the threaded build, and unblocks the engine. The earlier claim
  /// in this file ("isolation is impossible in WebView") was wrong.
  /// CORP: same-origin on every response is what lets COEP require-corp
  /// admit our own same-origin subresources (bundle, model, wasm).
  static void _isolationHeaders(HttpResponse res) {
    res.headers.add('Cross-Origin-Opener-Policy', 'same-origin');
    res.headers.add('Cross-Origin-Embedder-Policy', 'require-corp');
    res.headers.add('Cross-Origin-Resource-Policy', 'same-origin');
  }

  /// Permanent diagnostics (TASMEE Phase 2, item 2.3): every request is
  /// logged with its path + status code, so a future failure in the
  /// serve chain (bundle 404/500, WASM 404, eval error) is visible in
  /// logcat instead of silent. Only the path and the status are logged —
  /// never audio or query data.
  static void _logRequest(HttpRequest req, int status) {
    debugPrint('[LocalServer] ${req.method} ${req.uri.path} -> $status');
  }

  /// Registry paths the @tilawa/core loader fetches, mapped to the flat
  /// files ModelManager stores. Keys are the path below `/models/`;
  /// values are the flat file names in the model directory. Only the two
  /// tiers the registry defines are listed — anything else is not a
  /// known model and must 404 rather than serve a wrong file.
  static const _registryModelPaths = {
    'spliced-clean/1-int8/model.onnx': 'model-full.onnx',
    'spliced-clean-lite/1-int8/model.onnx': 'model-lite.onnx',
  };

  File _resolveModelFile(String path) {
    final rel = path.substring(8); // strip '/models/'
    final flat = _registryModelPaths[rel];
    if (flat != null) {
      debugPrint('[LocalServer] registry model path $path -> $flat');
      return File('${_modelDir.path}/$flat');
    }
    return File('${_modelDir.path}/$rel');
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/' || path == '/tilawa.html') {
        await _serveAsset(req, 'assets/web/tilawa.html');
      } else if (path == '/bundle.js') {
        await _serveAsset(req, 'assets/web/bundle.js');
      } else if (path.startsWith('/models/')) {
        // Registry-path mapping (2026-11-26 404 fix, ported from Pro):
        // @tilawa/core's loader ignores the `model` URL the bridge
        // passes and fetches the model by REGISTRY path —
        // `models/<id>/<version>/model.onnx` relative to the page —
        // while ModelManager stores the file FLAT as `model-<tier>.onnx`.
        // The generic mapping below used to turn that registry path into
        // `<modelDir>/spliced-clean/1-int8/model.onnx`, which does not
        // exist, so every load 404'd. Map the two registry paths the
        // loader actually requests to the flat files. Any other /models/
        // path keeps the generic mapping (ref-v2.json,
        // model-<tier>.onnx); a path matching neither a registry entry
        // nor an existing file 404s in _serveFile and is recorded by
        // the request log line.
        await _serveFile(req, _resolveModelFile(path));
      } else if (path.startsWith('/ort/')) {
        // onnxruntime-web WASM files, downloaded by tools/download_assets.py
        // into <modelDir>/ort/<version>/.
        //
        // FIXED 2026-11-25 (Phase 2, item 2.2; the poc-12 phone failure —
        // the engine never became ready, 120 s timeout, no error): the
        // old code built File('${_modelDir.path}${path.substring(1)}'),
        // i.e. "<dir>ort/1.30.0/..." with the '/' missing, so EVERY /ort/
        // request 404'd while the disk-side check
        // (ModelManager.ortWasmReady) passed. `path` already starts with
        // '/', so the model dir + path is the correct on-disk file —
        // note this is NOT the /models/ pattern (substring(8) strips
        // "/models/" because that prefix is not part of the disk
        // layout, while "ort/" IS: the files live in <dir>/ort/<ver>/).
        await _serveFile(req, File('${_modelDir.path}$path'));
      } else {
        _isolationHeaders(req.response);
        req.response
          ..statusCode = HttpStatus.notFound
          ..write('not found');
        await req.response.close();
        _logRequest(req, HttpStatus.notFound);
      }
    } catch (e) {
      _isolationHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..write('server error: $e');
      await req.response.close();
      _logRequest(req, HttpStatus.internalServerError);
    }
  }

  Future<void> _serveAsset(HttpRequest req, String asset) async {
    final data = await rootBundle.load(asset);
    final ext = asset.substring(asset.lastIndexOf('.'));
    req.response.headers.contentType =
        ContentType.parse(_mime[ext] ?? 'application/octet-stream');
    req.response.headers.add('Cache-Control', 'no-store');
    req.response.headers.contentLength = data.lengthInBytes;
    _isolationHeaders(req.response);
    req.response.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    await req.response.close();
    _logRequest(req, HttpStatus.ok);
  }

  Future<void> _serveFile(HttpRequest req, File file) async {
    if (!await file.exists()) {
      // Isolation headers here too: under COEP require-corp a header-less
      // 404 subresource is blocked by the browser instead of arriving as
      // a clean 404, which would mask the real error from the loader.
      _isolationHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('model file not found: ${req.uri.path}');
      await req.response.close();
      _logRequest(req, HttpStatus.notFound);
      return;
    }
    final ext = file.path.substring(file.path.lastIndexOf('.'));
    req.response.headers.contentType =
        ContentType.parse(_mime[ext] ?? 'application/octet-stream');
    req.response.headers.add('Cache-Control', 'no-store');
    _isolationHeaders(req.response);
    req.response.headers.contentLength = await file.length();
    await req.response.addStream(file.openRead());
    await req.response.close();
    _logRequest(req, HttpStatus.ok);
  }
}

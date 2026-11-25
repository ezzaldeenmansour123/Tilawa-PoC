// Recitation screen: pick a declared passage, recite, watch the words.
//
// The passage TEXT comes from the engine's own reference (ref-v2.json) via
// engine.passageWords() — never typed from memory, never invented.
// Highlighting rules (per the design):
//   - current observed word: highlighted (only when state == locked and
//     confidence >= 0.6; otherwise shown as "acquiring/ambiguous" faintly).
//   - checker=suspected: faint "probable" colour, never counted.
//   - checker=confirmed: marked as an error (wrong/omitted/added/skipped).
//   - checker=uncertain OR confidence < 0.6: grey "غير متأكد — أعد المحاولة",
//     never counted as an error.
//   - checker=resolved (self-correction): shown as "صحّحت نفسك", not an error.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';
import '../speech_engine.dart';
import '../webview_engine.dart';

class PresetPassage {
  const PresetPassage(this.label, this.passage);
  final String label;
  final Passage passage;
}

const kPresets = [
  PresetPassage('الفاتحة (1:1–7)', Passage(surah: 1, fromAyah: 1, toAyah: 7)),
  PresetPassage('آية الكرسي (2:255)', Passage(surah: 2, fromAyah: 255, toAyah: 255)),
  PresetPassage('الإخلاص (112:1–4)', Passage(surah: 112, fromAyah: 1, toAyah: 4)),
  PresetPassage('الملك (67:1–5)', Passage(surah: 67, fromAyah: 1, toAyah: 5)),
];

class RecitationScreen extends StatefulWidget {
  const RecitationScreen({super.key, required this.engine});
  final WebViewEngine engine;
  @override
  State<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends State<RecitationScreen> {
  PresetPassage _preset = kPresets[0];
  List<List<String>>? _words; // per ayah
  RefWord? _current;
  double _confidence = 0;
  TrackState _track = TrackState.acquiring;
  final List<CheckerEvent> _mistakes = [];
  final List<String> _notes = [];
  StreamSubscription<Object>? _sub;
  bool _running = false;
  bool _loading = false;
  String? _error;
  int? _loadMs;
  int? _lastLatencyMs;
  DateTime? _sessionStartWall;

  Future<void> _loadWords() async {
    setState(() => _words = widget.engine.passageWords(_preset.passage));
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
      _mistakes.clear();
      _notes.clear();
      _current = null;
    });
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        setState(() => _error =
            'إذن الميكروفون مرفوض — امنحه من إعدادات النظام ثم أعد المحاولة. (هذا اختبار بحد ذاته: يجب أن تظهر هذه الرسالة بوضوح بلا تعطل.)');
        return;
      }
      final t0 = DateTime.now();
      await widget.engine.load(tier: 'lite');
      _loadMs = DateTime.now().difference(t0).inMilliseconds;
      await _loadWords();
      if (_words == null) {
        setState(() => _error = 'تعذّر تحميل نص المقطع من المرجع.');
        return;
      }
      final sessionId = 'poc-${DateTime.now().millisecondsSinceEpoch}';
      await widget.engine.beginLog(
        sessionId: sessionId,
        meta: {
          'preset': _preset.label,
          'mode': 'memorization',
          'conditions': 'غرفة هادئة — سرعة عادية (عدّلها في السجل إن تغيّرت)',
        },
      );
      _sessionStartWall = DateTime.now();
      _sub = widget.engine
          .startSession(
            mode: SessionMode.memorization,
            passage: _preset.passage,
          )
          .listen(
            _onEvent,
            onError: (e) => setState(() => _error = e.toString()),
          );
      setState(() => _running = true);
    } on SpeechEngineException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'خطأ غير متوقع: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onEvent(Object event) {
    if (event is PositionEvent) {
      final best = event.observed.isNotEmpty ? event.observed.first : null;
      if (best != null && _sessionStartWall != null) {
        final latency = DateTime.now().difference(_sessionStartWall!).inMilliseconds -
            event.timeMs;
        _lastLatencyMs = latency;
      }
      setState(() {
        _current = best;
        _confidence = event.confidence;
        _track = event.state;
      });
    } else if (event is CheckerEvent) {
      setState(() {
        if (event.state == CheckerState.confirmed) {
          _mistakes.add(event);
        } else if (event.state == CheckerState.uncertain) {
          _notes.add('غير متأكد عند ${event.location} — لا يُحسب خطأً');
        } else if (event.state == CheckerState.resolved) {
          _notes.add('صحّحت نفسك عند ${event.location} — لا يُحسب خطأً');
        }
      });
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    await widget.engine.endSession();
    setState(() => _running = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _wordColor(int surah, int ayah, int wordIndex) {
    final cur = _current;
    if (cur != null &&
        cur.surah == surah &&
        cur.ayah == ayah &&
        cur.word == wordIndex + 1) {
      if (_confidence < 0.6 || _track != TrackState.locked) {
        return Colors.grey.shade400; // uncertain — faint, not a verdict
      }
      return Colors.teal.shade200; // locked, confident
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButton<PresetPassage>(
            value: _preset,
            isExpanded: true,
            items: kPresets
                .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: _running
                ? null
                : (p) {
                    if (p != null) setState(() => _preset = p);
                  },
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ),
          if (_words != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var ai = 0; ai < _words!.length; ai++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          children: [
                            for (var wi = 0; wi < _words![ai].length; wi++)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _wordColor(_preset.passage.surah,
                                      _preset.passage.fromAyah + ai, wi),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _words![ai][wi],
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'نص المقطع يظهر هنا بعد تحميل النموذج — من المرجع المدمج (ref-v2.json)، وليس نصاً مكتوباً يدوياً.'),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Chip(
                label: Text(
                    'التتبع: ${_track.name} • الثقة: ${(_confidence * 100).toStringAsFixed(0)}%'),
              ),
              const SizedBox(width: 8),
              Chip(label: Text('أخطاء مؤكدة: ${_mistakes.length}')),
            ],
          ),
          if (_loadMs != null)
            Text('زمن تحميل النموذج: ${(_loadMs! / 1000).toStringAsFixed(1)} ث'),
          if (_lastLatencyMs != null)
            Text('زمن آخر تظليل (تقريبي): ${_lastLatencyMs}ms'),
          if (_mistakes.isNotEmpty)
            ..._mistakes.map((m) => ListTile(
                  leading: const Icon(Icons.error, color: Colors.red),
                  title: Text(
                      '${errorClassLabel(m.errorClass)} عند ${m.location}'),
                )),
          ..._notes.map((n) => ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.grey),
                title: Text(n),
              )),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? _stop : (_loading ? null : _start),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_running ? Icons.stop : Icons.mic),
            label: Text(_running
                ? 'إيقاف الجلسة'
                : (_loading ? 'جارٍ تحميل النموذج...' : 'ابدأ التسميع')),
          ),
          const SizedBox(height: 8),
          const Text(
            'سجّل في دفترك لكل جلسة: زمن أول تظليل، زمن تأكيد كل خطأ، الأخطاء '
            'المؤكدة مقابل المزروعة عمداً، والإنذارات الكاذبة — ثم صدّر السجل '
            'من تبويب «السجلات».',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

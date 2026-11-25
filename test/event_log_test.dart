// Pure-Dart unit tests: no engine, no WebView, no device needed.
// Run in CI: flutter test.

import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_poc/event_log.dart';
import 'package:tilawa_poc/models.dart';

void main() {
  group('LogMetrics.highlightLatenciesMs', () {
    test('computes wall - (startWall + audioMs) per position event', () {
      final events = [
        {
          'type': 'meta',
          'payload': {'sessionStartedWallMs': 1000000},
        },
        {'type': 'position', 'wallMs': 1000800, 'audioMs': 0},
        {'type': 'position', 'wallMs': 1002100, 'audioMs': 900},
        {'type': 'position', 'wallMs': 1003300, 'audioMs': 2100},
        {'type': 'checker', 'wallMs': 1004000, 'audioMs': 3000},
      ];
      final lat = LogMetrics.highlightLatenciesMs(events);
      expect(lat, [800, 1200, 1200]);
      expect(LogMetrics.median(lat), 1200.0);
      expect(LogMetrics.percentile(lat, 90), 1200.0);
    });

    test('returns empty without a sessionStartedWallMs meta line', () {
      final events = [
        {'type': 'position', 'wallMs': 1000800, 'audioMs': 0},
      ];
      expect(LogMetrics.highlightLatenciesMs(events), isEmpty);
    });
  });

  group('LogMetrics.median', () {
    test('odd and even counts', () {
      expect(LogMetrics.median([3, 1, 2]), 2.0);
      expect(LogMetrics.median([4, 1, 3, 2]), 2.5);
    });
    test('empty is NaN, never a fake zero', () {
      expect(LogMetrics.median([]).isNaN, isTrue);
    });
  });

  group('models', () {
    test('RefWord equality is by (surah, ayah, word)', () {
      expect(
        const RefWord(surah: 1, ayah: 2, word: 3),
        const RefWord(surah: 1, ayah: 2, word: 3),
      );
      expect(
        const RefWord(surah: 1, ayah: 2, word: 3),
        isNot(const RefWord(surah: 1, ayah: 2, word: 4)),
      );
      expect(const RefWord(surah: 2, ayah: 255, word: 1).toString(), '2:255:1');
    });

    test('error classes map 1:1 from the engine strings', () {
      expect(errorClassFromString('wrong_word'), ErrorClass.wrongWord);
      expect(errorClassFromString('omitted_word'), ErrorClass.omittedWord);
      expect(errorClassFromString('added_word'), ErrorClass.addedWord);
      expect(errorClassFromString('skipped_passage'), ErrorClass.skippedPassage);
      expect(errorClassFromString('tajweed'), isNull,
          reason: 'tajweed is never an engine error class');
    });

    test('checker states: only confirmed counts as an error', () {
      const confirmed = CheckerEvent(
        id: 'x',
        timeMs: 0,
        state: CheckerState.confirmed,
        errorClass: ErrorClass.wrongWord,
        location: RefWord(surah: 1, ayah: 1, word: 1),
      );
      expect(confirmed.countsAsError, isTrue);
      for (final s in [
        CheckerState.suspected,
        CheckerState.uncertain,
        CheckerState.resolved,
      ]) {
        expect(
          CheckerEvent(
            id: 'x',
            timeMs: 0,
            state: s,
            errorClass: ErrorClass.wrongWord,
            location: const RefWord(surah: 1, ayah: 1, word: 1),
          ).countsAsError,
          isFalse,
          reason: '$s must never count as an error',
        );
      }
    });
  });
}

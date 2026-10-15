// NOTE on test scope: VadChunkedSenseVoiceStrategy spawns real isolates that
// load real ONNX models and run real native inference. None of that is
// meaningfully testable in `flutter test` — there is no real microphone
// audio, no real model files in the test sandbox, and isolate boundaries
// don't accept fakes/mocks. These tests therefore only exercise the pure,
// synchronous parts of the class: config validation (configOptions /
// currentConfig / applyConfig) and the guarantee that an invalid
// `languageCode` passed to start() is rejected with an ArgumentError BEFORE
// any isolate is spawned (asserted via debugSpawnAttempts, a counter
// incremented only inside the real isolate-spawning path).
//
// Full VAD + SenseVoice behavior (real audio through real models, segment
// boundaries, decoded text) is verified only by the later real-device smoke
// test task, not here.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/vad_chunked_sense_voice_strategy.dart';

void main() {
  group('computeBackdatedSpeechStartOffset', () {
    test('backdates by the default 6400-sample pre-roll', () {
      expect(computeBackdatedSpeechStartOffset(10000), 3600);
    });

    test('clamps to zero when the buffer is shorter than the pre-roll', () {
      expect(computeBackdatedSpeechStartOffset(100), 0);
    });

    test('returns zero at exactly the pre-roll length', () {
      expect(computeBackdatedSpeechStartOffset(6400), 0);
    });

    test('honors a caller-supplied preRollSamples override', () {
      expect(
        computeBackdatedSpeechStartOffset(1000, preRollSamples: 200),
        800,
      );
    });
  });

  group('GrowingSampleBuffer', () {
    test('starts empty', () {
      final buffer = GrowingSampleBuffer();
      expect(buffer.length, 0);
      expect(buffer.slice(0, 0), isEmpty);
    });

    test('append grows length and slice concatenates across chunks', () {
      final buffer = GrowingSampleBuffer();
      buffer.append(Float32List.fromList([1, 2, 3]));
      buffer.append(Float32List.fromList([4, 5]));
      expect(buffer.length, 5);
      expect(buffer.slice(0, 5), [1, 2, 3, 4, 5]);
    });

    test('slice returns a sub-range spanning multiple appended chunks', () {
      final buffer = GrowingSampleBuffer();
      buffer.append(Float32List.fromList([1, 2, 3]));
      buffer.append(Float32List.fromList([4, 5, 6]));
      buffer.append(Float32List.fromList([7, 8]));
      expect(buffer.slice(2, 7), [3, 4, 5, 6, 7]);
    });

    test('slice clamps an out-of-range end to the buffer length', () {
      final buffer = GrowingSampleBuffer();
      buffer.append(Float32List.fromList([1, 2, 3]));
      expect(buffer.slice(1, 100), [2, 3]);
    });

    test('slice clamps a negative start to zero', () {
      final buffer = GrowingSampleBuffer();
      buffer.append(Float32List.fromList([1, 2, 3]));
      expect(buffer.slice(-5, 2), [1, 2]);
    });

    test('slice returns empty when start >= end', () {
      final buffer = GrowingSampleBuffer();
      buffer.append(Float32List.fromList([1, 2, 3]));
      expect(buffer.slice(2, 2), isEmpty);
      expect(buffer.slice(3, 1), isEmpty);
    });

    test('clear resets length and subsequent appends start fresh', () {
      final buffer = GrowingSampleBuffer();
      buffer.append(Float32List.fromList([1, 2, 3]));
      buffer.clear();
      expect(buffer.length, 0);
      buffer.append(Float32List.fromList([9, 9]));
      expect(buffer.slice(0, 2), [9, 9]);
    });

    test('append ignores empty chunks without affecting length', () {
      final buffer = GrowingSampleBuffer();
      buffer.append(Float32List.fromList([1, 2]));
      buffer.append(Float32List(0));
      expect(buffer.length, 2);
    });
  });

  group('configOptions / currentConfig / applyConfig', () {
    test('configOptions exposes exactly one language option', () {
      final strategy = VadChunkedSenseVoiceStrategy();
      expect(strategy.configOptions, hasLength(1));
      final option = strategy.configOptions.single;
      expect(option.key, 'language');
      expect(option.allowedValues, ['auto', 'zh', 'en', 'ja', 'ko', 'yue']);
      expect(option.defaultValue, 'auto');
    });

    test('currentConfig defaults to auto before any applyConfig call', () {
      final strategy = VadChunkedSenseVoiceStrategy();
      expect(strategy.currentConfig, {'language': 'auto'});
    });

    test('applyConfig stores a valid language override', () {
      final strategy = VadChunkedSenseVoiceStrategy();
      strategy.applyConfig({'language': 'zh'});
      expect(strategy.currentConfig, {'language': 'zh'});
    });

    test('applyConfig rejects an unknown key', () {
      final strategy = VadChunkedSenseVoiceStrategy();
      expect(
        () => strategy.applyConfig({'volume': 'loud'}),
        throwsArgumentError,
      );
    });

    test('applyConfig rejects a value outside allowedValues', () {
      final strategy = VadChunkedSenseVoiceStrategy();
      expect(
        () => strategy.applyConfig({'language': 'fr'}),
        throwsArgumentError,
      );
    });
  });

  group('start() language validation runs before any isolate spawn', () {
    test('rejects an invalid languageCode without spawning isolates', () async {
      final strategy = VadChunkedSenseVoiceStrategy();

      await expectLater(
        () => strategy.start('fr'),
        throwsArgumentError,
      );

      expect(
        strategy.debugSpawnAttempts,
        0,
        reason: 'invalid language must fail before touching isolates',
      );
    });

    test(
      'a repeated invalid start() never spawns, across multiple attempts',
      () async {
        final strategy = VadChunkedSenseVoiceStrategy();

        await expectLater(() => strategy.start('xx'), throwsArgumentError);
        await expectLater(() => strategy.start(''), throwsArgumentError);
        await expectLater(() => strategy.start('ZH'), throwsArgumentError);

        expect(strategy.debugSpawnAttempts, 0);
      },
    );
  });
}

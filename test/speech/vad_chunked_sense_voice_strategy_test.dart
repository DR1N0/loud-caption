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

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/vad_chunked_sense_voice_strategy.dart';

void main() {
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

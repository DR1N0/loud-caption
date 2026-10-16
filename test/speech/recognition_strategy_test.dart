import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/recognition_strategy.dart';
import 'package:loud_caption/speech/speech_engine.dart';

/// Hand-written fake for tests that exercise code depending on
/// [RecognitionStrategy] without any sherpa-onnx/isolate machinery. Copied
/// into Task 6's tests rather than shared via a `test/fakes/` directory, per
/// this repo's convention of per-test-file fakes.
class FakeRecognitionStrategy implements RecognitionStrategy {
  final _controller = StreamController<RecognitionOutput>.broadcast();
  final List<String> calls = [];
  var _config = {'language': 'auto'};

  @override
  Stream<RecognitionOutput> get output => _controller.stream;

  @override
  List<SpeechEngineConfigOption> get configOptions => const [
    SpeechEngineConfigOption(
      key: 'language',
      allowedValues: ['auto', 'zh', 'en'],
      defaultValue: 'auto',
    ),
  ];

  @override
  Map<String, String> get currentConfig => _config;

  @override
  void applyConfig(Map<String, String> values) {
    _config = {..._config, ...values};
  }

  @override
  Future<void> start(String languageCode) async {
    calls.add('start:$languageCode');
  }

  @override
  void acceptAudio(Float32List samples, int sampleRate) {
    calls.add('acceptAudio:${samples.length}@$sampleRate');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _controller.close();
  }

  void emit(RecognitionOutput value) => _controller.add(value);
}

void main() {
  test('RecognitionOutput round-trips its fields', () {
    const output = RecognitionOutput(text: '你好', isFinal: true);
    expect(output.text, '你好');
    expect(output.isFinal, isTrue);
    expect(output.detectedLanguage, isNull);

    const withLanguage = RecognitionOutput(
      text: '你好',
      isFinal: true,
      detectedLanguage: 'zh',
    );
    expect(withLanguage.detectedLanguage, 'zh');
  });

  test(
    'fake RecognitionStrategy drives output through the real interface shape',
    () async {
      final strategy = FakeRecognitionStrategy();
      await strategy.start('zh');
      strategy.acceptAudio(Float32List.fromList([0.1, 0.2, 0.3]), 16000);

      final emitted = strategy.output.first;
      strategy.emit(const RecognitionOutput(text: '你好', isFinal: true));
      expect((await emitted).text, '你好');

      strategy.applyConfig({'language': 'en'});
      expect(strategy.currentConfig['language'], 'en');

      await strategy.stop();
      await strategy.dispose();
      expect(strategy.calls, ['start:zh', 'acceptAudio:3@16000', 'stop', 'dispose']);
    },
  );
}

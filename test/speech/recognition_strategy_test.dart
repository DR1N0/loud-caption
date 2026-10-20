import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/recognition_strategy.dart';

/// Hand-written fake for tests that exercise code depending on
/// [RecognitionStrategy] without any sherpa-onnx/isolate machinery. Copied
/// into Task 6's tests rather than shared via a `test/fakes/` directory, per
/// this repo's convention of per-test-file fakes.
class FakeRecognitionStrategy implements RecognitionStrategy {
  final _controller = StreamController<RecognitionOutput>.broadcast();
  final List<String> calls = [];

  @override
  Stream<RecognitionOutput> get output => _controller.stream;

  @override
  Future<void> start() async {
    calls.add('start');
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
      await strategy.start();
      strategy.acceptAudio(Float32List.fromList([0.1, 0.2, 0.3]), 16000);

      final emitted = strategy.output.first;
      strategy.emit(const RecognitionOutput(text: '你好', isFinal: true));
      expect((await emitted).text, '你好');

      await strategy.stop();
      await strategy.dispose();
      expect(strategy.calls, ['start', 'acceptAudio:3@16000', 'stop', 'dispose']);
    },
  );
}

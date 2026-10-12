import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/speech_engine.dart';

void main() {
  test('partial and final events retain text and session identity', () {
    const partial = SpeechEvent(SpeechEventKind.partial, '你好', 7);
    const done = SpeechEvent(SpeechEventKind.finalText, '你好', 7);
    expect(partial.text, '你好');
    expect(partial.sessionId, done.sessionId);
    expect(done.kind, SpeechEventKind.finalText);
  });
}

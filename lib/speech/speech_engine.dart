enum SpeechEventKind { partial, finalText, error }

class SpeechEvent {
  const SpeechEvent(this.kind, this.text, this.sessionId, {this.detectedLanguage});

  final SpeechEventKind kind;
  final String text;
  final int sessionId;

  /// The language detected for this segment (e.g. `'zh'`, `'en'`, `'yue'`),
  /// or `null` if unknown/not reported. Only meaningful for `partial`/
  /// `finalText` events.
  final String? detectedLanguage;
}

abstract interface class SpeechEngine {
  Stream<SpeechEvent> get events;
  Future<int> start();
  Future<bool> isSessionActive(int sessionId);
  Future<void> stop();
  Future<void> dispose();
}

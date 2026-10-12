enum SpeechEventKind { partial, finalText, error }

class SpeechEvent {
  const SpeechEvent(this.kind, this.text, this.sessionId);

  final SpeechEventKind kind;
  final String text;
  final int sessionId;
}

abstract interface class SpeechEngine {
  Stream<SpeechEvent> get events;
  Future<int> start(String languageCode);
  Future<bool> isSessionActive(int sessionId);
  Future<void> stop();
  Future<void> dispose();
}

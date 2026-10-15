enum SpeechEventKind { partial, finalText, error }

class SpeechEvent {
  const SpeechEvent(this.kind, this.text, this.sessionId);

  final SpeechEventKind kind;
  final String text;
  final int sessionId;
}

/// Describes one discrete legal setting for an engine (e.g. SenseVoice's
/// `language` key accepts exactly one of six strings) — not an implied
/// ability to combine multiple values from [allowedValues] at once.
class SpeechEngineConfigOption {
  const SpeechEngineConfigOption({
    required this.key,
    required this.allowedValues,
    required this.defaultValue,
  });

  final String key;
  final List<String> allowedValues;
  final String defaultValue;
}

abstract interface class SpeechEngine {
  Stream<SpeechEvent> get events;
  Future<int> start(String languageCode);
  Future<bool> isSessionActive(int sessionId);
  Future<void> stop();
  Future<void> dispose();

  /// The engine's configurable options, orthogonal to [start]'s
  /// `languageCode` parameter.
  List<SpeechEngineConfigOption> get configOptions;

  /// The engine's current config values, keyed by [SpeechEngineConfigOption.key].
  Map<String, String> get currentConfig;

  /// Validates `values` against [configOptions], throwing [ArgumentError]
  /// for an unknown key or an out-of-range value. Applied on a best-effort,
  /// per-engine-documented basis for the current/next session — callers
  /// must not assume it retroactively changes an in-flight utterance.
  Future<void> applyConfig(Map<String, String> values);
}

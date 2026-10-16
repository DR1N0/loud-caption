/// A single in-flight translation call: a bounded stream of growing output
/// text that eventually closes, plus the ability to cancel it early.
///
/// Unlike [TranslationEngine.translate] itself, [output] is not a long-lived
/// broadcast stream — it represents exactly one translation attempt.
abstract interface class TranslationRequest {
  Stream<String> get output;

  void cancel();
}

/// Translates recognized caption text on-device.
///
/// Implementations may require a one-time, potentially large model download
/// before they can translate; [ensureLoaded] drives that and [isLoaded]
/// reports whether it has completed.
abstract interface class TranslationEngine {
  Future<void> ensureLoaded();

  bool get isLoaded;

  TranslationRequest translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  });

  Future<void> dispose();
}

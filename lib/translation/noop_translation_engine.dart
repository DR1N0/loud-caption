import '../downloads/model_downloader.dart';
import 'translation_engine.dart';

/// Phase 2 placeholder: reports as never loaded and passes text through
/// unchanged. Lets the mode-cycling UI and [CaptionController] wiring be
/// built and tested against the real [TranslationEngine] interface before a
/// real on-device engine exists.
class NoopTranslationEngine implements TranslationEngine {
  @override
  bool get isLoaded => false;

  @override
  Future<bool> isModelDownloaded() async => true;

  @override
  Stream<DownloadProgress> ensureLoaded() => const Stream.empty();

  @override
  TranslationRequest translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) => _NoopTranslationRequest(text);

  @override
  Future<void> dispose() async {}
}

class _NoopTranslationRequest implements TranslationRequest {
  _NoopTranslationRequest(String text)
    : output = Stream<String>.value(text);

  @override
  final Stream<String> output;

  @override
  void cancel() {}
}

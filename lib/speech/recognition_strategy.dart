import 'dart:typed_data';

import 'speech_engine.dart';

/// One decoded segment of speech.
///
/// VAD-chunked strategies (e.g. SenseVoice via sherpa-onnx) only ever emit
/// `isFinal: true` — a whole utterance is batch-decoded at once, so there is
/// no mid-utterance partial. A future true-streaming strategy (e.g.
/// Paraformer) may also emit `isFinal: false` segments as a partial grows.
class RecognitionOutput {
  const RecognitionOutput({
    required this.text,
    required this.isFinal,
    this.detectedLanguage,
  });

  final String text;
  final bool isFinal;

  /// The language SenseVoice detected for this segment (e.g. `'zh'`, `'en'`,
  /// `'yue'`), or `null` if the strategy doesn't report one. Used to route
  /// per-source-language translation; has no effect on captioning itself.
  final String? detectedLanguage;
}

/// How captured audio becomes text, independent of how audio is captured.
///
/// Implementations own their own isolate(s) and model lifecycle. [start]
/// must not return until the strategy is ready to accept audio via
/// [acceptAudio]. [stop] quiesces the strategy but MAY keep expensive
/// resources (isolates, loaded models) warm for a later [start]; only
/// [dispose] must guarantee every native/isolate resource is released.
abstract interface class RecognitionStrategy {
  Stream<RecognitionOutput> get output;

  /// The strategy's configurable options, orthogonal to [start]'s
  /// `languageCode` parameter.
  List<SpeechEngineConfigOption> get configOptions;

  /// The strategy's current config values, keyed by
  /// [SpeechEngineConfigOption.key].
  Map<String, String> get currentConfig;

  /// Validates `values` against [configOptions], throwing [ArgumentError]
  /// for an unknown key or an out-of-range value.
  void applyConfig(Map<String, String> values);

  Future<void> start(String languageCode);

  void acceptAudio(Float32List samples, int sampleRate);

  Future<void> stop();

  Future<void> dispose();
}

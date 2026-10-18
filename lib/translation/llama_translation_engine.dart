import 'dart:async';

import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../downloads/model_downloader.dart';
import 'hy_mt2_model_download.dart';
import 'translation_engine.dart';

// Chinese display names for the languages Hy-MT2 is prompted to translate
// into — matching Hy-MT2's own README table ("Chinese names should be used
// in Chinese prompts"), independent of the app UI's own language labels.
const _languageNames = {'zh': '中文', 'en': '英语', 'ja': '日语', 'ko': '韩语'};

/// Builds the exact Hy-MT2 dense-model prompt: BOS, a user turn carrying the
/// translation instruction, then the assistant-turn opener the model
/// continues from. No system turn — Hy-MT2 has no default system prompt
/// (confirmed by the model's own README) and the dense-1.8B chat template
/// (`train/llama_factory_support/hy_dense_template.py` in the upstream
/// tencent/Hy-MT2 repo) only emits a system block when one is supplied.
String buildHyMt2Prompt(String sourceText, String targetLanguageCode) {
  final targetName = _languageNames[targetLanguageCode] ?? targetLanguageCode;
  final instruction =
      '将以下文本翻译为 $targetName，注意只需要输出翻译后的结果，不要额外解释：\n\n$sourceText';
  return '<｜hy_begin▁of▁sentence｜><｜hy_User｜>$instruction<｜hy_Assistant｜>';
}

/// Real on-device translation via Hy-MT2-1.8B (Q4_K_M GGUF) through
/// `llama_flutter_android`. The model is downloaded on demand — see
/// [ensureLoaded].
class LlamaTranslationEngine implements TranslationEngine {
  LlamaTranslationEngine({LlamaController? controller, int threads = 4})
    : _controller = controller ?? LlamaController(),
      _threads = threads;

  /// Caption lines are short; capped well below the model's own 4096-token
  /// recommendation to keep translation latency low for live captioning.
  static const _maxTranslationTokens = 200;

  final LlamaController _controller;
  final int _threads;

  /// Chains every native call (load, generate, stop) so none overlap —
  /// `llama_flutter_android` throws if `generate()` is called while a prior
  /// generation (or its cancellation `stop()`) hasn't finished yet. Mirrors
  /// `CaptionController._serializeEngine`'s identical pattern for the ASR
  /// engine.
  Future<void> _operations = Future<void>.value();
  bool _loaded = false;
  Stream<DownloadProgress>? _loading;

  @override
  bool get isLoaded => _loaded;

  @override
  Future<bool> isModelDownloaded() => isHyMt2ModelReady();

  @override
  Stream<DownloadProgress> ensureLoaded() {
    if (_loaded) return const Stream.empty();
    // Cached as a broadcast stream so a second concurrent `ensureLoaded()`
    // call (e.g. a re-rendered download dialog) observes the same in-flight
    // download rather than starting another.
    return _loading ??= _load().asBroadcastStream();
  }

  Stream<DownloadProgress> _load() async* {
    if (!await isHyMt2ModelReady()) {
      yield* downloadHyMt2Model();
    }
    final modelPath = await hyMt2ModelDestinationPath();
    await _controller.loadModel(
      modelPath: modelPath,
      threads: _threads,
      contextSize: 4096,
      gpuLayers: 0,
    );
    _loaded = true;
  }

  @override
  TranslationRequest translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) {
    final output = StreamController<String>();
    var cancelled = false;

    final task = _operations.then((_) async {
      if (cancelled) return;
      try {
        await _controller.clearContext();
        final prompt = buildHyMt2Prompt(text, targetLang);
        await for (final token in _controller.generate(
          prompt: prompt,
          maxTokens: _maxTranslationTokens,
          // Low temperature: translation should be faithful/deterministic,
          // not creative. 0.7 (a reasonable default for open-ended chat) let
          // the very first on-device call produce an off-task response that
          // echoed the instruction instead of translating it.
          temperature: 0.2,
          topP: 0.9,
          topK: 40,
          repeatPenalty: 1.05,
        )) {
          if (cancelled) break;
          output.add(token);
        }
      } catch (error, stackTrace) {
        if (!cancelled) output.addError(error, stackTrace);
      } finally {
        await output.close();
      }
    });
    _operations = task.catchError((Object _, StackTrace _) {});

    return _LlamaTranslationRequest(
      output: output.stream,
      onCancel: () {
        cancelled = true;
        _operations = _operations
            .then((_) => _controller.stop())
            .catchError((Object _, StackTrace _) {});
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _controller.dispose();
    _loaded = false;
  }
}

class _LlamaTranslationRequest implements TranslationRequest {
  _LlamaTranslationRequest({required this.output, required this.onCancel});

  @override
  final Stream<String> output;
  final void Function() onCancel;

  @override
  void cancel() => onCancel();
}

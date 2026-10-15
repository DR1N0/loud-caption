import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'recognition_strategy.dart';
import 'sense_voice_model_assets.dart';
import 'speech_engine.dart';

/// Language codes accepted by sherpa-onnx's SenseVoice model. Validated
/// natively in `offline-sense-voice-model-config.cc`; anything outside this
/// set is rejected by the native layer, so we reject it synchronously in
/// Dart first for a clearer error.
const _senseVoiceLanguages = ['auto', 'zh', 'en', 'ja', 'ko', 'yue'];

/// Validates [values] against [options], throwing [ArgumentError] for an
/// unknown key or a value outside that key's allowed values.
///
/// Pure and synchronous so it can run (and be unit-tested) before any
/// isolate is touched. Shared by [VadChunkedSenseVoiceStrategy.applyConfig]
/// (arbitrary caller-supplied keys) and [VadChunkedSenseVoiceStrategy.start]
/// (validating the single `language` key derived from its parameter).
void _validateLanguageConfig(
  Map<String, String> values,
  List<SpeechEngineConfigOption> options,
) {
  for (final entry in values.entries) {
    SpeechEngineConfigOption? option;
    for (final candidate in options) {
      if (candidate.key == entry.key) {
        option = candidate;
        break;
      }
    }
    if (option == null) {
      throw ArgumentError('Unknown config key: "${entry.key}"');
    }
    if (!option.allowedValues.contains(entry.value)) {
      throw ArgumentError(
        'Invalid value "${entry.value}" for config key "${entry.key}"; '
        'allowed values: ${option.allowedValues}',
      );
    }
  }
}

/// A [RecognitionStrategy] that runs Silero VAD + SenseVoice's offline
/// `OfflineRecognizer` across two background isolates (VAD, ASR), modeled on
/// sherpa-onnx's own `vad-non-streaming-asr-from-microphone` Flutter example.
///
/// Both isolates are spawned once (on the first [start]) and stay warm across
/// [stop]/[start] cycles — e.g. `CaptionController.switchLanguage`'s
/// stop-then-start pattern — because reloading SenseVoice's ~163 MB ONNX
/// model on every language toggle would make that toggle feel broken.
/// Only [dispose] tears the isolates down permanently.
///
/// Full VAD/ASR behavior (real audio through real models) is not exercised
/// by unit tests in this file — see that file's header comment for why, and
/// for what is tested instead. It is verified by a later real-device smoke
/// test.
class VadChunkedSenseVoiceStrategy implements RecognitionStrategy {
  VadChunkedSenseVoiceStrategy({
    Future<SenseVoiceModelPaths> Function()? prepareModelAssets,
  }) : _prepareModelAssets = prepareModelAssets ?? prepareSenseVoiceModelAssets;

  final Future<SenseVoiceModelPaths> Function() _prepareModelAssets;

  final StreamController<RecognitionOutput> _output =
      StreamController<RecognitionOutput>.broadcast();

  Isolate? _vadIsolate;
  Isolate? _asrIsolate;
  ReceivePort? _mainReceivePort;
  StreamSubscription<dynamic>? _mainSubscription;
  SendPort? _vadSendPort;
  SendPort? _asrSendPort;

  String? _languageOverride;
  bool _forwardingAudio = false;
  bool _disposed = false;

  /// Incremented each time isolate spawning is actually attempted. Exposed
  /// only so tests can assert that an invalid [start] language never reaches
  /// isolate spawning, without needing a real isolate or a fake for one.
  @visibleForTesting
  int debugSpawnAttempts = 0;

  @override
  Stream<RecognitionOutput> get output => _output.stream;

  @override
  List<SpeechEngineConfigOption> get configOptions => const [
    SpeechEngineConfigOption(
      key: 'language',
      allowedValues: _senseVoiceLanguages,
      defaultValue: 'auto',
    ),
  ];

  @override
  Map<String, String> get currentConfig => {
    'language': _languageOverride ?? configOptions.first.defaultValue,
  };

  @override
  void applyConfig(Map<String, String> values) {
    _validateLanguageConfig(values, configOptions);
    final language = values['language'];
    if (language != null) _languageOverride = language;
  }

  @override
  Future<void> start(String languageCode) async {
    _ensureNotDisposed();
    final effectiveLanguage = _languageOverride ?? languageCode;
    _validateLanguageConfig({'language': effectiveLanguage}, configOptions);

    if (_vadIsolate == null) {
      await _spawnIsolates(effectiveLanguage);
    } else {
      _vadSendPort!.send(const _VadReset());
      _asrSendPort!.send(_AsrSetLanguage(effectiveLanguage));
    }
    _forwardingAudio = true;
  }

  @override
  void acceptAudio(Float32List samples, int sampleRate) {
    // VAD/SenseVoice both expect 16 kHz mono PCM; mic capture upstream is
    // documented to always supply that, so sampleRate isn't transcoded here
    // — it's accepted only for symmetry with the RecognitionStrategy shape.
    if (!_forwardingAudio) return;
    final vadSendPort = _vadSendPort;
    if (vadSendPort == null) return;
    vadSendPort.send(_AudioChunk(samples));
  }

  @override
  Future<void> stop() async {
    _forwardingAudio = false;
    _vadSendPort?.send(const _VadFlush());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _forwardingAudio = false;
    _vadIsolate?.kill(priority: Isolate.immediate);
    _asrIsolate?.kill(priority: Isolate.immediate);
    await _mainSubscription?.cancel();
    _mainReceivePort?.close();
    await _output.close();
  }

  Future<void> _spawnIsolates(String languageCode) async {
    debugSpawnAttempts++;
    final paths = await _prepareModelAssets();

    final mainReceivePort = ReceivePort();
    _mainReceivePort = mainReceivePort;

    final asrReady = Completer<SendPort>();
    final vadReady = Completer<SendPort>();

    _mainSubscription = mainReceivePort.listen((message) {
      if (message is _AsrReady) {
        asrReady.complete(message.sendPort);
      } else if (message is _VadReady) {
        vadReady.complete(message.sendPort);
      } else if (message is _AsrResult) {
        if (!_output.isClosed) {
          _output.add(RecognitionOutput(text: message.text, isFinal: true));
        }
      }
    });

    _asrIsolate = await Isolate.spawn(
      _asrIsolateEntry,
      _AsrIsolateInit(
        mainSendPort: mainReceivePort.sendPort,
        senseVoiceModelPath: paths.senseVoiceModel,
        senseVoiceTokensPath: paths.senseVoiceTokens,
        languageCode: languageCode,
      ),
    );
    _asrSendPort = await asrReady.future;

    _vadIsolate = await Isolate.spawn(
      _vadIsolateEntry,
      _VadIsolateInit(
        mainSendPort: mainReceivePort.sendPort,
        asrSendPort: _asrSendPort!,
        sileroVadModelPath: paths.sileroVadModel,
      ),
    );
    _vadSendPort = await vadReady.future;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('VadChunkedSenseVoiceStrategy has been disposed');
    }
  }
}

// ============================================================
// Isolate messages
//
// Custom message classes, not raw primitives: Dart isolates can send plain
// object graphs (not just literals) across a SendPort as long as they don't
// carry native handles/closures, which is exactly what the sherpa-onnx
// Flutter example this is modeled on does too.
// ============================================================

class _AsrReady {
  const _AsrReady(this.sendPort);
  final SendPort sendPort;
}

class _VadReady {
  const _VadReady(this.sendPort);
  final SendPort sendPort;
}

class _AudioChunk {
  const _AudioChunk(this.samples);
  final Float32List samples;
}

class _VadReset {
  const _VadReset();
}

class _VadFlush {
  const _VadFlush();
}

class _AsrSegmentRequest {
  const _AsrSegmentRequest(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}

class _AsrSetLanguage {
  const _AsrSetLanguage(this.languageCode);
  final String languageCode;
}

class _AsrResult {
  const _AsrResult(this.text);
  final String text;
}

// ============================================================
// VAD isolate
// ============================================================

class _VadIsolateInit {
  const _VadIsolateInit({
    required this.mainSendPort,
    required this.asrSendPort,
    required this.sileroVadModelPath,
  });

  final SendPort mainSendPort;
  final SendPort asrSendPort;
  final String sileroVadModelPath;
}

Future<void> _vadIsolateEntry(_VadIsolateInit init) async {
  // FFI binding state is per-isolate: must (re-)init in every isolate that
  // touches sherpa-onnx, not just the main isolate.
  await sherpa_onnx.initBindingsAsync();

  final vad = sherpa_onnx.VoiceActivityDetector(
    config: sherpa_onnx.VadModelConfig(
      sileroVad: sherpa_onnx.SileroVadModelConfig(
        model: init.sileroVadModelPath,
        threshold: 0.5,
        // Tuned value validated on-device by the project owner, not the
        // Dart library default of 0.5.
        minSilenceDuration: 0.25,
        minSpeechDuration: 0.25,
        windowSize: 512,
        maxSpeechDuration: 5.0,
      ),
      sampleRate: 16000,
      numThreads: 1,
      provider: 'cpu',
      debug: true,
    ),
    bufferSizeInSeconds: 30,
  );

  final receivePort = ReceivePort();
  init.mainSendPort.send(_VadReady(receivePort.sendPort));

  void drainSegments() {
    while (!vad.isEmpty()) {
      final segment = vad.front();
      init.asrSendPort.send(_AsrSegmentRequest(segment.samples, 16000));
      vad.pop();
    }
  }

  receivePort.listen((message) {
    if (message is _AudioChunk) {
      vad.acceptWaveform(message.samples);
      drainSegments();
    } else if (message is _VadReset) {
      vad.reset();
    } else if (message is _VadFlush) {
      // A stop mid-utterance should still emit the trailing speech as a
      // final segment rather than silently dropping it.
      vad.flush();
      drainSegments();
    }
  });
}

// ============================================================
// ASR isolate
// ============================================================

class _AsrIsolateInit {
  const _AsrIsolateInit({
    required this.mainSendPort,
    required this.senseVoiceModelPath,
    required this.senseVoiceTokensPath,
    required this.languageCode,
  });

  final SendPort mainSendPort;
  final String senseVoiceModelPath;
  final String senseVoiceTokensPath;
  final String languageCode;
}

sherpa_onnx.OfflineRecognizerConfig _buildOfflineRecognizerConfig({
  required String senseVoiceModelPath,
  required String senseVoiceTokensPath,
  required String languageCode,
}) {
  return sherpa_onnx.OfflineRecognizerConfig(
    model: sherpa_onnx.OfflineModelConfig(
      senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
        model: senseVoiceModelPath,
        language: languageCode,
        useInverseTextNormalization: false,
      ),
      tokens: senseVoiceTokensPath,
      numThreads: 2,
    ),
  );
}

Future<void> _asrIsolateEntry(_AsrIsolateInit init) async {
  await sherpa_onnx.initBindingsAsync();

  final recognizer = sherpa_onnx.OfflineRecognizer(
    _buildOfflineRecognizerConfig(
      senseVoiceModelPath: init.senseVoiceModelPath,
      senseVoiceTokensPath: init.senseVoiceTokensPath,
      languageCode: init.languageCode,
    ),
  );

  final receivePort = ReceivePort();
  init.mainSendPort.send(_AsrReady(receivePort.sendPort));

  receivePort.listen((message) {
    if (message is _AsrSegmentRequest) {
      final stream = recognizer.createStream();
      stream.acceptWaveform(
        samples: message.samples,
        sampleRate: message.sampleRate,
      );
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      stream.free();
      init.mainSendPort.send(_AsrResult(result.text));
    } else if (message is _AsrSetLanguage) {
      // A language toggle updates the recognizer's runtime config in place
      // rather than recreating it, so the ~163 MB ONNX model stays loaded.
      recognizer.setConfig(
        _buildOfflineRecognizerConfig(
          senseVoiceModelPath: init.senseVoiceModelPath,
          senseVoiceTokensPath: init.senseVoiceTokensPath,
          languageCode: message.languageCode,
        ),
      );
    }
  });
}

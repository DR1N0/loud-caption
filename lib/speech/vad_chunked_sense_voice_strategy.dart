import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../settings/app_settings.dart' show recognitionLanguages;
import 'recognition_strategy.dart';
import 'sense_voice_model_assets.dart';
import 'speech_engine.dart';

/// Pre-roll back-dating applied to the speech-start offset the moment
/// [sherpa_onnx.VoiceActivityDetector.isDetected] transitions from
/// not-detected to detected. Copied exactly (not retuned) from sherpa-onnx's
/// own `SherpaOnnxSimulateStreamingAsr` Android demo (`Home.kt`): 6400
/// samples = 0.4s @ 16kHz, capturing audio the VAD likely saw just before it
/// noticed speech.
const int simulatedStreamingPreRollSamples = 6400;

/// Interval between "simulated streaming" partial re-decodes of the
/// in-progress speech segment. Copied exactly (not retuned) from the same
/// reference demo's 200ms value.
const Duration simulatedStreamingPartialInterval = Duration(milliseconds: 200);

/// Backdates [currentBufferLength] by [preRollSamples] (defaulting to
/// [simulatedStreamingPreRollSamples]), clamped to zero, to compute the
/// segment-start offset used for "simulated streaming" partial re-decodes.
///
/// Pure and synchronous, so — unlike the isolate code that calls it — it is
/// directly unit-tested without touching any isolate or native sherpa-onnx
/// code.
@visibleForTesting
int computeBackdatedSpeechStartOffset(
  int currentBufferLength, {
  int preRollSamples = simulatedStreamingPreRollSamples,
}) {
  final backdated = currentBufferLength - preRollSamples;
  return backdated < 0 ? 0 : backdated;
}

/// An append-only buffer of [Float32List] audio chunks supporting cheap
/// appends and slicing without copying on every append, used by
/// [_vadIsolateEntry] to accumulate the "simulated streaming" raw sample
/// buffer referenced in [VadChunkedSenseVoiceStrategy]'s class doc comment.
///
/// Kept separate from whatever [sherpa_onnx.VoiceActivityDetector] buffers
/// internally, matching the reference demo this is ported from.
///
/// Pure and synchronous (no isolate/native dependency), so it is directly
/// unit-tested.
@visibleForTesting
class GrowingSampleBuffer {
  final List<Float32List> _chunks = [];
  int _length = 0;

  /// Total number of samples appended so far and not yet discarded by
  /// [clear].
  int get length => _length;

  /// Appends [samples] to the end of the buffer.
  void append(Float32List samples) {
    if (samples.isEmpty) return;
    _chunks.add(samples);
    _length += samples.length;
  }

  /// Discards all buffered samples, resetting [length] to 0.
  void clear() {
    _chunks.clear();
    _length = 0;
  }

  /// Returns a newly-allocated [Float32List] containing samples
  /// `[start, end)`, clamped to the buffer's current bounds.
  Float32List slice(int start, int end) {
    final clampedStart = start < 0 ? 0 : (start > _length ? _length : start);
    final clampedEnd = end < clampedStart
        ? clampedStart
        : (end > _length ? _length : end);
    final result = Float32List(clampedEnd - clampedStart);
    var written = 0;
    var consumed = 0;
    for (final chunk in _chunks) {
      final chunkStart = consumed;
      final chunkEnd = consumed + chunk.length;
      consumed = chunkEnd;
      if (chunkEnd <= clampedStart || chunkStart >= clampedEnd) continue;
      final from = clampedStart > chunkStart ? clampedStart - chunkStart : 0;
      final to = clampedEnd < chunkEnd ? clampedEnd - chunkStart : chunk.length;
      for (var i = from; i < to; i++) {
        result[written++] = chunk[i];
      }
    }
    return result;
  }
}

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
/// While speech is ongoing, the VAD isolate also re-decodes the
/// in-progress segment every [simulatedStreamingPartialInterval] and emits
/// it as a non-final [RecognitionOutput] ("simulated streaming", ported
/// exactly from sherpa-onnx's own `SherpaOnnxSimulateStreamingAsr` Android
/// demo) so text appears progressively instead of only once per pause; the
/// existing VAD-segment-close path still does one more full decode and
/// emits the true final.
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
    // recognitionLanguages is also sherpa-onnx's SenseVoice model's exact
    // accepted set — validated natively in
    // `offline-sense-voice-model-config.cc`; anything outside it is
    // rejected by the native layer, so we reject it synchronously in Dart
    // first for a clearer error.
    SpeechEngineConfigOption(
      key: 'language',
      allowedValues: recognitionLanguages,
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
          _output.add(
            RecognitionOutput(
              text: message.text,
              isFinal: message.isFinal,
              detectedLanguage: message.lang,
            ),
          );
        }
        // Every `_AsrResult` — partial or final — means the ASR isolate's
        // single-threaded event loop just finished a decode and is free to
        // accept another. Relay that to the VAD isolate so it can unblock
        // its `asrBusy` gate (see `_vadIsolateEntry`'s `Timer.periodic`)
        // instead of firing a new partial-decode request on a fixed 200ms
        // schedule regardless of whether the ASR isolate is still working
        // through the previous one.
        _vadSendPort?.send(const _AsrIsolateFree());
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
  const _AsrSegmentRequest(this.samples, this.sampleRate, {required this.isFinal});

  /// The audio samples for this segment, wrapped in a [TransferableTypedData]
  /// at the construction site (via [_transferableSamples]) so that sending
  /// this message across the VAD→ASR isolate boundary is a zero-copy
  /// ownership move instead of Dart's default deep-copy-on-send for
  /// [TypedData]. The copy cost would otherwise grow with segment length —
  /// paid on every [simulatedStreamingPartialInterval] partial re-decode of a
  /// still-growing segment — unlike the single-process reference
  /// implementation this is ported from.
  ///
  /// [TransferableTypedData] is single-use and transfers ownership of the
  /// underlying buffer: callers must not read the original [Float32List]
  /// again after wrapping it. See [_transferableSamples]'s doc comment for
  /// why both call sites in this file are safe to do so.
  final TransferableTypedData samples;
  final int sampleRate;

  /// Whether this is the true final decode of a VAD-closed segment (`true`)
  /// or a "simulated streaming" partial re-decode of a still-open segment
  /// (`false`). Threaded through unchanged by the ASR isolate onto the
  /// matching [_AsrResult] so the main isolate's listener can construct the
  /// correctly-tagged [RecognitionOutput] without tracking any state of its
  /// own.
  final bool isFinal;
}

/// Wraps [samples] in a [TransferableTypedData] for a zero-copy isolate
/// send. Ownership of [samples]'s backing buffer transfers to the result;
/// [samples] must not be read again afterward in the sending isolate. Both
/// call sites in this file satisfy that: the periodic-timer re-decode passes
/// a [GrowingSampleBuffer.slice] result, which always allocates a fresh,
/// solely-referenced [Float32List] per call; `drainSegments()` passes
/// `vad.front().samples`, which sherpa_onnx's [sherpa_onnx.SpeechSegment]
/// already constructs via `Float32List.fromList(...)` — a fresh, exclusively
/// Dart-owned copy of the native segment's bytes, not a view shared with
/// anything else — and which is never read again after being sent (the
/// immediately-following `vad.pop()` only discards the native segment).
TransferableTypedData _transferableSamples(Float32List samples) {
  return TransferableTypedData.fromList([
    Uint8List.view(samples.buffer, samples.offsetInBytes, samples.lengthInBytes),
  ]);
}

class _AsrSetLanguage {
  const _AsrSetLanguage(this.languageCode);
  final String languageCode;
}

class _AsrResult {
  const _AsrResult(this.text, {required this.isFinal, this.lang});
  final String text;
  final bool isFinal;

  /// SenseVoice's detected language for this segment, or `null` if it
  /// reported none (an empty string from the native layer is normalized to
  /// `null` at the point this is constructed — see `_asrIsolateEntry`).
  final String? lang;
}

/// SenseVoice's native `lang` field comes back wrapped in its own special-
/// token syntax — e.g. `<|zh|>`, not `zh` — confirmed against sherpa-onnx's
/// own documented SenseVoice JSON output. Strips that wrapper so the rest of
/// the app (settings' `translationLanguages`, the routing table) can compare
/// against plain ISO-ish codes.
String? _normalizeDetectedLanguage(String raw) {
  if (raw.isEmpty) return null;
  final match = RegExp(r'^<\|([a-z]+)\|>$').firstMatch(raw);
  return match?.group(1) ?? raw;
}

/// Sent from the main isolate to the VAD isolate every time the main
/// isolate's listener processes an [_AsrResult] (partial or final alike).
/// Tells the VAD isolate the ASR isolate's event loop just became free again,
/// so it's safe to send another partial-decode request. See the
/// `asrBusy`/`Timer.periodic` handshake in [_vadIsolateEntry] for why this
/// exists: without it, the VAD isolate has no way to know the ASR isolate is
/// still mid-decode and will happily queue a new partial every 200ms
/// regardless, building an ever-staler backlog once a decode starts taking
/// longer than 200ms.
class _AsrIsolateFree {
  const _AsrIsolateFree();
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

  // "Simulated streaming" state: a growing raw-sample buffer, separate from
  // whatever `vad` buffers internally, used to re-decode the in-progress
  // speech segment every `simulatedStreamingPartialInterval` while speech is
  // ongoing. Ported from sherpa-onnx's own `SherpaOnnxSimulateStreamingAsr`
  // Android demo (`Home.kt`) with its exact parameters (6400-sample pre-roll,
  // 200ms re-decode interval) per real-device testing feedback that waiting
  // for a full pause before any text appears feels too slow.
  final growingBuffer = GrowingSampleBuffer();
  var speechStartOffset = 0;
  var isSpeechStarted = false;

  // Tracks whether the ASR isolate is believed to still be mid-decode on a
  // previously-sent *partial* request. Set `true` right after sending a
  // partial, cleared by the main isolate's `_AsrIsolateFree` relay once any
  // decode (partial or final) completes. See `Timer.periodic` below for the
  // gate this enables, and the root-cause explanation in this file's class
  // doc comment / the Task 12 brief: without this gate, a fixed 200ms timer
  // keeps enqueuing partial requests into the ASR isolate's FIFO mailbox
  // regardless of whether the previous one has even started running, so once
  // a decode exceeds 200ms the backlog compounds and every queued decode is
  // for audio that's already stale by the time it runs.
  var asrBusy = false;

  void resetUtteranceState() {
    // Called once a segment closes, so the next utterance's partials don't
    // include stale audio from the one that just finished.
    growingBuffer.clear();
    speechStartOffset = 0;
    isSpeechStarted = false;
  }

  void drainSegments() {
    while (!vad.isEmpty()) {
      final segment = vad.front();
      init.asrSendPort.send(
        _AsrSegmentRequest(
          _transferableSamples(segment.samples),
          16000,
          isFinal: true,
        ),
      );
      vad.pop();
      resetUtteranceState();
    }
  }

  // Fires independently of audio arrival; it's a no-op whenever speech isn't
  // currently in progress. Not explicitly cancelled: this isolate is only
  // ever torn down via `Isolate.kill` from the main isolate, which discards
  // the isolate (and any of its timers) wholesale.
  Timer.periodic(simulatedStreamingPartialInterval, (_) {
    // Skip this tick entirely (don't queue it for later) whenever the ASR
    // isolate hasn't signalled it's free since the last partial was sent —
    // this is the "skip stale intermediate work" fix: the next tick where
    // `asrBusy` is false will send whatever the growing buffer's *current*
    // length is, automatically reflecting however much the segment grew
    // while the ASR isolate was busy, instead of decoding every
    // progressively-stale, progressively-larger slice in between.
    if (!isSpeechStarted || asrBusy) return;
    final slice = growingBuffer.slice(speechStartOffset, growingBuffer.length);
    if (slice.isEmpty) return;
    init.asrSendPort.send(
      _AsrSegmentRequest(_transferableSamples(slice), 16000, isFinal: false),
    );
    asrBusy = true;
  });

  receivePort.listen((message) {
    if (message is _AudioChunk) {
      growingBuffer.append(message.samples);
      vad.acceptWaveform(message.samples);
      if (!isSpeechStarted && vad.isDetected()) {
        isSpeechStarted = true;
        speechStartOffset = computeBackdatedSpeechStartOffset(
          growingBuffer.length,
        );
      }
      drainSegments();
    } else if (message is _VadReset) {
      vad.reset();
      resetUtteranceState();
      // Defensive safety net, not something expected to ever actually fire:
      // a warm restart (`start()` called again on already-spawned isolates)
      // is exactly the kind of boundary where, if an `_AsrIsolateFree` relay
      // were ever lost (e.g. the main isolate's listener raced with isolate
      // teardown on a previous `stop`, or some future refactor introduces a
      // path that drops it), `asrBusy` could otherwise stay stuck `true`
      // forever and silently disable all partial decodes for the rest of the
      // process's life with no further symptom until the next long
      // utterance. Dart's SendPort delivery is reliable in the ordinary case
      // the brief flags this against, so this isn't fixing a reproduced bug
      // — it's cutting off a silent, hard-to-diagnose failure mode cheaply
      // at the one point where resetting all other utterance state already
      // happens anyway.
      asrBusy = false;
    } else if (message is _VadFlush) {
      // A stop mid-utterance should still emit the trailing speech as a
      // final segment rather than silently dropping it. `drainSegments`
      // resets the growing-buffer state once the flushed segment is
      // consumed, exactly as it does for a normal VAD-closed segment.
      vad.flush();
      drainSegments();
    } else if (message is _AsrIsolateFree) {
      asrBusy = false;
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
        samples: message.samples.materialize().asFloat32List(),
        sampleRate: message.sampleRate,
      );
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      stream.free();
      init.mainSendPort.send(
        _AsrResult(
          result.text,
          isFinal: message.isFinal,
          lang: _normalizeDetectedLanguage(result.lang),
        ),
      );
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

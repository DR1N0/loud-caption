import 'dart:async';
import 'dart:typed_data';

import 'mic_capture.dart';
import 'recognition_strategy.dart';
import 'speech_engine.dart';

/// Converts raw little-endian 16-bit PCM bytes (as produced by
/// `package:record`'s `AudioEncoder.pcm16bits`) into the normalized
/// `Float32List` samples sherpa-onnx's VAD/ASR models expect.
Float32List pcm16BytesToFloat32(Uint8List bytes) {
  final byteData = ByteData.sublistView(bytes);
  final sampleCount = bytes.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

/// [SpeechEngine] built from a [MicCapture] and a [RecognitionStrategy],
/// independent of any specific capture or recognition implementation.
///
/// Owns session-ID assignment and generation-based fencing itself: unlike
/// `AndroidVoskEngine`'s MethodChannel bridge, there is no native round-trip
/// to obtain a session ID, so there is no window in which a platform event
/// can arrive for a session this engine doesn't know about yet. That
/// eliminates the early-event-buffering machinery the Vosk adapter needed.
class SherpaOnnxSpeechEngine implements SpeechEngine {
  SherpaOnnxSpeechEngine({required MicCapture mic, required RecognitionStrategy strategy})
    : _mic = mic,
      _strategy = strategy {
    _strategyOutputSubscription = _strategy.output.listen(
      _onOutput,
      onError: _onStrategyError,
    );
  }

  final MicCapture _mic;
  final RecognitionStrategy _strategy;
  final StreamController<SpeechEvent> _events =
      StreamController<SpeechEvent>.broadcast();

  late final StreamSubscription<RecognitionOutput> _strategyOutputSubscription;
  StreamSubscription<Uint8List>? _micSubscription;

  int _generation = 0;
  int? _pendingStartGeneration;
  int? _activeSessionId;
  int _nextSessionId = 1;
  bool _sessionUnhealthy = false;
  bool _disposed = false;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<int> start(String languageCode) async {
    _ensureNotDisposed();
    if (_pendingStartGeneration != null || _activeSessionId != null) {
      throw StateError('Speech recognition is already active');
    }

    final generation = ++_generation;
    _pendingStartGeneration = generation;
    try {
      if (!await _mic.hasPermission()) {
        throw StateError('Microphone permission was denied');
      }

      final pcmStream = await _mic.start();
      if (_disposed || _generation != generation) {
        await _bestEffort(_mic.stop);
        throw StateError('Speech start was cancelled');
      }

      await _strategy.start(languageCode);
      if (_disposed || _generation != generation) {
        await _bestEffort(_mic.stop);
        await _bestEffort(_strategy.stop);
        throw StateError('Speech start was cancelled');
      }

      final sessionId = _nextSessionId++;
      _activeSessionId = sessionId;
      _sessionUnhealthy = false;
      _pendingStartGeneration = null;
      _micSubscription = pcmStream.listen(
        (bytes) => _onPcmBytes(sessionId, bytes),
        onError: (Object error, StackTrace stackTrace) =>
            _onMicError(sessionId, error),
      );
      return sessionId;
    } catch (_) {
      if (_pendingStartGeneration == generation) {
        _pendingStartGeneration = null;
      }
      rethrow;
    }
  }

  @override
  Future<bool> isSessionActive(int sessionId) async {
    _ensureNotDisposed();
    return sessionId == _activeSessionId && !_sessionUnhealthy;
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;

    _generation++;
    _activeSessionId = null;
    _pendingStartGeneration = null;
    await _micSubscription?.cancel();
    _micSubscription = null;

    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _mic.stop();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _strategy.stop();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    final needsStop = _activeSessionId != null || _pendingStartGeneration != null;
    _disposed = true;
    _generation++;
    _activeSessionId = null;
    _pendingStartGeneration = null;

    Object? firstError;
    StackTrace? firstStackTrace;
    void record(Object error, StackTrace stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    try {
      if (needsStop) {
        try {
          await _mic.stop();
        } catch (error, stackTrace) {
          record(error, stackTrace);
        }
        try {
          await _strategy.stop();
        } catch (error, stackTrace) {
          record(error, stackTrace);
        }
      }
    } finally {
      await _micSubscription?.cancel();
      _micSubscription = null;
      await _strategyOutputSubscription.cancel();
      try {
        await _mic.dispose();
      } catch (error, stackTrace) {
        record(error, stackTrace);
      }
      try {
        await _strategy.dispose();
      } catch (error, stackTrace) {
        record(error, stackTrace);
      }
      await _events.close();
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  @override
  List<SpeechEngineConfigOption> get configOptions => _strategy.configOptions;

  @override
  Map<String, String> get currentConfig => _strategy.currentConfig;

  @override
  Future<void> applyConfig(Map<String, String> values) async {
    _strategy.applyConfig(values);
  }

  void _onPcmBytes(int sessionId, Uint8List bytes) {
    if (_activeSessionId != sessionId) return;
    _strategy.acceptAudio(pcm16BytesToFloat32(bytes), 16000);
  }

  void _onMicError(int sessionId, Object error) {
    if (_activeSessionId != sessionId) return;
    _sessionUnhealthy = true;
    _events.add(
      SpeechEvent(SpeechEventKind.error, 'Microphone error: $error', sessionId),
    );
  }

  void _onOutput(RecognitionOutput output) {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    _events.add(
      SpeechEvent(
        output.isFinal ? SpeechEventKind.finalText : SpeechEventKind.partial,
        output.text,
        sessionId,
      ),
    );
  }

  void _onStrategyError(Object error, StackTrace stackTrace) {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    _sessionUnhealthy = true;
    _events.add(
      SpeechEvent(
        SpeechEventKind.error,
        'Speech recognition error: $error',
        sessionId,
      ),
    );
  }

  /// Swallows [action]'s error — used only when unwinding a cancelled
  /// pending [start], where the cancellation `StateError` thrown afterward is
  /// what matters, not whichever best-effort stop failed along the way.
  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Intentionally ignored; see doc comment.
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('Speech engine has been disposed');
  }
}

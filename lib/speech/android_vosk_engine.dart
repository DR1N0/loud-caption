import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'speech_engine.dart';

const _methodChannelName = 'app.loudcaption/speech/methods';
const _eventChannelName = 'app.loudcaption/speech/events';
const _maxEarlyEvents = 16;

/// Converts one native Vosk channel payload to the public speech contract.
///
/// Native events carry raw Vosk JSON so this boundary keeps recognizer-specific
/// payloads and stale native session IDs out of the app controller.
SpeechEvent? parseNativeEvent(Object? value, int activeSessionId) {
  if (value is! Map) return null;

  final id = value['sessionId'];
  final kind = value['kind'];
  final raw = value['raw'];
  if (id is! int ||
      id != activeSessionId ||
      kind is! String ||
      raw is! String) {
    return null;
  }

  if (kind == 'error') {
    final message = raw.trim();
    return SpeechEvent(
      SpeechEventKind.error,
      message.isEmpty ? '识别错误' : message,
      id,
    );
  }
  if (kind != 'partial' && kind != 'final') return null;

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;

    final text = decoded[kind == 'partial' ? 'partial' : 'text'];
    if (text is! String || text.trim().isEmpty) return null;

    return SpeechEvent(
      kind == 'partial' ? SpeechEventKind.partial : SpeechEventKind.finalText,
      text.trim(),
      id,
    );
  } on FormatException {
    return SpeechEvent(SpeechEventKind.error, '识别结果格式错误', id);
  }
}

/// Flutter adapter for the Android Vosk MethodChannel and EventChannel bridge.
class AndroidVoskEngine implements SpeechEngine {
  AndroidVoskEngine({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName),
      _eventChannel = eventChannel ?? const EventChannel(_eventChannelName) {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: _onNativeStreamError,
    );
  }

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final StreamController<SpeechEvent> _events =
      StreamController<SpeechEvent>.broadcast();
  final Queue<Object?> _earlyEvents = Queue<Object?>();

  late final StreamSubscription<Object?> _eventSubscription;
  int? _activeSessionId;
  int? _pendingStartGeneration;
  int? _failedLateStopGeneration;
  int _generation = 0;
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
      final sessionId = await _methodChannel.invokeMethod<int>('start', {
        'language': languageCode,
      });
      if (sessionId == null) {
        throw StateError('Native speech start did not return a session ID');
      }
      if (_disposed || _generation != generation) {
        await _stopLateNativeSession(generation);
        throw StateError('Speech start was cancelled');
      }

      _pendingStartGeneration = null;
      _activeSessionId = sessionId;
      _drainEarlyEvents();
      return sessionId;
    } catch (_) {
      // A native start failure can release its own pending marker. A late
      // cancellation failure cannot: its session may still own the mic.
      if (_pendingStartGeneration == generation && _generation == generation) {
        _pendingStartGeneration = null;
      }
      _earlyEvents.clear();
      rethrow;
    }
  }

  @override
  Future<bool> isSessionActive(int sessionId) async {
    _ensureNotDisposed();
    if (_activeSessionId != sessionId) return false;

    final result = await _methodChannel.invokeMethod<Object?>(
      'isSessionActive',
      {'sessionId': sessionId},
    );
    if (result is! bool) {
      throw StateError('Native session health did not return a bool');
    }
    if (_disposed || _activeSessionId != sessionId) return false;
    return result;
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;

    final failedLateStopGeneration = _failedLateStopGeneration;
    _invalidateSession();
    await _methodChannel.invokeMethod<void>('stop');
    if (_failedLateStopGeneration == failedLateStopGeneration) {
      if (_pendingStartGeneration == failedLateStopGeneration) {
        _pendingStartGeneration = null;
      }
      _failedLateStopGeneration = null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    final needsNativeStop =
        _activeSessionId != null || _pendingStartGeneration != null;
    _disposed = true;
    _invalidateSession();
    Object? stopError;
    StackTrace? stopStackTrace;
    try {
      if (needsNativeStop) {
        await _methodChannel.invokeMethod<void>('stop');
      }
    } catch (error, stackTrace) {
      stopError = error;
      stopStackTrace = stackTrace;
    } finally {
      await _eventSubscription.cancel();
      await _events.close();
    }
    if (stopError != null) {
      Error.throwWithStackTrace(stopError, stopStackTrace!);
    }
  }

  @override
  List<SpeechEngineConfigOption> get configOptions => const [];
  @override
  Map<String, String> get currentConfig => const {};
  @override
  Future<void> applyConfig(Map<String, String> values) async {}

  Future<void> _stopLateNativeSession(int generation) async {
    // A protocol stop has no session ID, so the pending marker remains a fence
    // until this exact late session is known to be stopped.
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } catch (_) {
      if (_pendingStartGeneration == generation) {
        _failedLateStopGeneration = generation;
      }
      rethrow;
    }
    if (_pendingStartGeneration == generation) {
      _pendingStartGeneration = null;
    }
    if (_failedLateStopGeneration == generation) {
      _failedLateStopGeneration = null;
    }
  }

  void _invalidateSession() {
    // Reject platform events before requesting native cancellation, because the
    // Vosk callback and this call can cross on the Android main thread.
    _generation++;
    _activeSessionId = null;
    _earlyEvents.clear();
  }

  void _onNativeEvent(Object? value) {
    if (_disposed) return;

    final activeSessionId = _activeSessionId;
    if (activeSessionId != null) {
      _emitParsed(value, activeSessionId);
    } else if (_pendingStartGeneration != null) {
      if (_earlyEvents.length == _maxEarlyEvents) {
        _earlyEvents.removeFirst();
      }
      _earlyEvents.addLast(value);
    }
  }

  void _onNativeStreamError(Object error, StackTrace stackTrace) {
    final activeSessionId = _activeSessionId;
    if (_disposed || activeSessionId == null) return;
    _events.add(SpeechEvent(SpeechEventKind.error, '语音通道错误', activeSessionId));
  }

  void _drainEarlyEvents() {
    final activeSessionId = _activeSessionId;
    if (activeSessionId == null) return;

    while (_earlyEvents.isNotEmpty) {
      _emitParsed(_earlyEvents.removeFirst(), activeSessionId);
    }
  }

  void _emitParsed(Object? value, int activeSessionId) {
    final event = parseNativeEvent(value, activeSessionId);
    if (event != null) _events.add(event);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('Speech engine has been disposed');
  }
}

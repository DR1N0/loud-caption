import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:synchronized/synchronized.dart';

import '../captions/caption_controller.dart';
import '../permissions/microphone_access.dart';
import '../speech/speech_engine.dart';
import '../ui/orientation_manager.dart';
import 'capture_intent.dart';
import 'screen_awake.dart';

/// Serializes native capture effects from lifecycle and preference intents.
///
/// UI routes may continue to use the controller directly until Task 4 moves
/// their policy here. This class is deliberately usable independently so its
/// capture gate can be supplied while constructing [CaptionController].
class CaptionLifecycleCoordinator extends ChangeNotifier {
  CaptionLifecycleCoordinator({
    required CaptionController controller,
    required SpeechEngine engine,
    required MicrophoneAccess microphoneAccess,
    required ScreenAwake screenAwake,
    required OrientationManager orientationManager,
  }) : _controller = controller,
       _engine = engine,
       _microphoneAccess = microphoneAccess,
       _screenAwake = screenAwake,
       _orientationManager = orientationManager {
    _controller.addListener(_onControllerChanged);
  }

  final CaptionController _controller;
  final SpeechEngine _engine;
  final MicrophoneAccess _microphoneAccess;
  final ScreenAwake _screenAwake;
  final OrientationManager _orientationManager;
  final Lock _lock = Lock();

  CaptureIntent _intent = const CaptureIntent(
    presence: CapturePresence.foreground,
    route: CaptureRoute.caption,
    access: null,
    permissionFresh: false,
  );
  Future<void>? _initialization;
  int _revision = 0;
  int _permissionRequest = 0;
  int _orientationTicket = 0;
  int? _stopRequiredRevision;
  int? _listeningSessionObserved;
  bool _awake = false;
  bool _permissionRequestInFlight = false;
  bool _orientationChangeInFlight = false;
  bool _disposed = false;
  String? _lifecycleMessage;

  bool get captureDesired => _intent.captureDesired;
  bool get mayStartCapture =>
      _stopRequiredRevision == null && _intent.mayStartCapture;
  MicAccessState? get access => _intent.access;
  bool get permissionRequestInFlight => _permissionRequestInFlight;
  bool get orientationChangeInFlight => _orientationChangeInFlight;
  String? get lifecycleMessage => _lifecycleMessage;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _controller.initialize();
    if (_disposed) return;
    try {
      await _orientationManager.apply(_controller.settings.landscape);
    } catch (error) {
      _setLifecycleMessage('屏幕方向设置失败: $error');
    }
    if (_disposed) return;
    final ticket = _revision;
    final currentAccess = await _microphoneAccess.status();
    if (_disposed || ticket != _revision) return;
    _replaceIntent(
      _intent.copyWith(
        access: currentAccess,
        permissionFresh: currentAccess == MicAccessState.granted,
      ),
    );
    await _queueReconcile();
  }

  Future<void> onAppLifecycle(AppLifecycleState state) {
    if (_disposed) return Future<void>.value();
    switch (state) {
      case AppLifecycleState.inactive:
        _replaceIntent(
          _intent.copyWith(presence: CapturePresence.temporarilyInactive),
        );
        return _queueReconcile();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _replaceIntent(_intent.copyWith(presence: CapturePresence.background));
        // A later resume may allow a replacement only after this native stop.
        // Keep the obligation separate from current intent so a fast lifecycle
        // bounce cannot let its queued stop observe foreground and disappear.
        _stopRequiredRevision = _revision;
        return _queueReconcile();
      case AppLifecycleState.resumed:
        return _resumeWithFreshPermission();
    }
  }

  Future<void> _resumeWithFreshPermission() async {
    _replaceIntent(
      _intent.copyWith(
        presence: CapturePresence.foreground,
        permissionFresh: false,
      ),
    );
    final ticket = _revision;
    final currentAccess = await _microphoneAccess.status();
    if (_disposed || ticket != _revision) return;
    _replaceIntent(
      _intent.copyWith(
        access: currentAccess,
        permissionFresh: currentAccess == MicAccessState.granted,
      ),
    );
    await _queueReconcile(checkHealth: true);
  }

  Future<void> requestMicrophonePermission() async {
    if (_disposed || _permissionRequestInFlight) return;
    _permissionRequestInFlight = true;
    final request = ++_permissionRequest;
    _notify();
    try {
      final result = await _microphoneAccess.request();
      if (_disposed || request != _permissionRequest) return;
      _replaceIntent(
        _intent.copyWith(
          access: result,
          permissionFresh: result == MicAccessState.granted,
        ),
      );
      await _queueReconcile();
    } finally {
      if (!_disposed && request == _permissionRequest) {
        _permissionRequestInFlight = false;
        _notify();
      }
    }
  }

  Future<bool> openPermissionSettings() => _microphoneAccess.openSettings();

  void onInAppSettingsOpened() {
    if (_disposed) return;
    _replaceIntent(_intent.copyWith(route: CaptureRoute.settings));
  }

  void onInAppSettingsClosed() {
    if (_disposed) return;
    _replaceIntent(_intent.copyWith(route: CaptureRoute.caption));
  }

  Future<void> selectLanguage(String languageCode) async {
    if (_disposed) return;
    await _lock.synchronized(() => _controller.switchLanguage(languageCode));
    if (!_disposed) await _queueReconcile();
  }

  Future<void> setLanguageEnabled(String languageCode, bool enabled) async {
    if (_disposed) return;
    await _lock.synchronized(
      () => _controller.setLanguageEnabled(languageCode, enabled),
    );
    if (!_disposed) await _queueReconcile();
  }

  Future<void> increaseFont() => _writeSetting(_controller.increaseFont);

  Future<void> decreaseFont() => _writeSetting(_controller.decreaseFont);

  Future<void> _writeSetting(Future<void> Function() write) async {
    if (_disposed) return;
    await _lock.synchronized(write);
  }

  Future<void> toggleOrientation() async {
    if (_disposed || _orientationChangeInFlight) return;
    final ticket = ++_orientationTicket;
    final previous = _controller.settings.landscape;
    _orientationChangeInFlight = true;
    _notify();
    try {
      await _lock.synchronized(_controller.toggleOrientation);
      if (_disposed || ticket != _orientationTicket) return;
      await _orientationManager.apply(_controller.settings.landscape);
      if (!_disposed && ticket == _orientationTicket) {
        await _queueReconcile(checkHealth: true, allowStartAfterHealth: false);
      }
    } catch (error) {
      if (!_disposed && ticket == _orientationTicket) {
        await _lock.synchronized(() async {
          if (_controller.settings.landscape != previous) {
            await _controller.toggleOrientation();
          }
        });
        _setLifecycleMessage('屏幕方向切换失败: $error');
      }
    } finally {
      if (!_disposed && ticket == _orientationTicket) {
        _orientationChangeInFlight = false;
        _notify();
      }
    }
  }

  Future<void> retryCapture() async {
    if (_disposed) return;
    await _queueReconcile(retryFailedStop: true);
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _replaceIntent(_intent.copyWith(terminal: true));
    _controller.removeListener(_onControllerChanged);
    await _queueReconcile(retryFailedStop: true);
    if (_controller.isStopConfirmed &&
        _controller.status == CaptionStatus.idle) {
      _disposed = true;
      _controller.dispose();
      await _engine.dispose();
    }
  }

  Future<void> _queueReconcile({
    bool checkHealth = false,
    bool allowStartAfterHealth = true,
    bool retryFailedStop = false,
  }) {
    final task = _lock.synchronized(
      () => _reconcile(
        checkHealth: checkHealth,
        allowStartAfterHealth: allowStartAfterHealth,
        retryFailedStop: retryFailedStop,
      ),
    );
    unawaited(
      task.catchError((Object error, StackTrace stackTrace) {
        if (_lifecycleMessage == null) {
          _setLifecycleMessage('识别生命周期失败: $error');
        }
      }),
    );
    return task;
  }

  Future<void> _reconcile({
    required bool checkHealth,
    required bool allowStartAfterHealth,
    required bool retryFailedStop,
  }) async {
    if (_disposed) return;
    final mustStop =
        _stopRequiredRevision != null ||
        (retryFailedStop &&
            !_controller.isStopConfirmed &&
            _controller.status != CaptionStatus.listening);
    if (!captureDesired || mustStop) {
      late final bool stopped;
      try {
        stopped = await _stopIfNeeded(
          retryFailedStop: retryFailedStop || (mustStop && _intent.terminal),
        );
      } finally {
        await _disableAwakeBestEffort();
      }
      if (!stopped || !captureDesired) return;
      _stopRequiredRevision = null;
    }

    final sessionId = _controller.currentSessionId;
    if (checkHealth &&
        _controller.status == CaptionStatus.listening &&
        sessionId != null) {
      bool active;
      try {
        active = await _engine.isSessionActive(sessionId);
      } catch (error) {
        _setLifecycleMessage('无法确认识别状态: $error');
        return;
      }
      if (!captureDesired) {
        try {
          await _stopIfNeeded();
        } finally {
          await _disableAwakeBestEffort();
        }
        return;
      }
      if (active) {
        await _enableAwakeIfCurrent();
        return;
      }
      await _stopIfNeeded();
      if (!captureDesired || !allowStartAfterHealth) return;
    } else if (_controller.status == CaptionStatus.listening &&
        sessionId != null) {
      await _enableAwakeIfCurrent();
      return;
    }

    if (!mayStartCapture || !_controller.isStopConfirmed) return;
    await _controller.start();
    if (!captureDesired) {
      try {
        await _stopIfNeeded();
      } finally {
        await _disableAwakeBestEffort();
      }
      return;
    }
    await _enableAwakeIfCurrent();
  }

  Future<bool> _stopIfNeeded({bool retryFailedStop = false}) async {
    if (_intent.stopFailed && !retryFailedStop) return false;
    if (_controller.isStopConfirmed &&
        _controller.status == CaptionStatus.idle) {
      _clearStopFailure();
      return true;
    }
    try {
      await _controller.stop();
      _clearStopFailure();
      return true;
    } catch (error) {
      _replaceIntent(_intent.copyWith(stopFailed: true));
      _setLifecycleMessage('停止识别失败: $error');
      rethrow;
    }
  }

  void _clearStopFailure() {
    if (!_intent.stopFailed) return;
    _replaceIntent(_intent.copyWith(stopFailed: false));
    _lifecycleMessage = null;
    _notify();
    unawaited(_queueReconcile());
  }

  Future<void> _enableAwakeIfCurrent() async {
    if (_awake ||
        !captureDesired ||
        !_intent.permissionFresh ||
        _controller.status != CaptionStatus.listening) {
      return;
    }
    try {
      await _screenAwake.enable();
      _awake = true;
    } catch (error) {
      _setLifecycleMessage('无法保持屏幕常亮: $error');
    }
  }

  Future<void> _disableAwakeBestEffort() async {
    if (!_awake) return;
    _awake = false;
    try {
      await _screenAwake.disable();
    } catch (error) {
      _setLifecycleMessage('无法关闭屏幕常亮: $error');
    }
  }

  void _onControllerChanged() {
    if (_disposed) return;
    final sessionId = _controller.currentSessionId;
    if (_controller.status != CaptionStatus.listening || sessionId == null) {
      _listeningSessionObserved = null;
      if (_controller.status == CaptionStatus.failed && _awake) {
        unawaited(
          _lock
              .synchronized(() async {
                if (_controller.status == CaptionStatus.failed) {
                  await _disableAwakeBestEffort();
                }
              })
              .catchError((Object error) {
                _setLifecycleMessage('无法关闭屏幕常亮: $error');
              }),
        );
      }
    } else if (_listeningSessionObserved != sessionId) {
      _listeningSessionObserved = sessionId;
      unawaited(_queueReconcile());
    }
    _notify();
  }

  void _replaceIntent(CaptureIntent next) {
    _intent = next;
    _revision++;
    _notify();
  }

  void _setLifecycleMessage(String message) {
    if (_disposed || _lifecycleMessage == message) return;
    _lifecycleMessage = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

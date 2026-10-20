import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/captions/caption_controller.dart';
import 'package:loud_caption/lifecycle/caption_lifecycle_coordinator.dart';
import 'package:loud_caption/lifecycle/screen_awake.dart';
import 'package:loud_caption/permissions/microphone_access.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/orientation_manager.dart';

void main() {
  late _FakeSpeechEngine engine;
  late _FakeMicrophoneAccess access;
  late _FakeScreenAwake awake;
  late _FakeOrientation orientation;
  late CaptionLifecycleCoordinator coordinator;
  late CaptionController controller;

  setUp(() {
    engine = _FakeSpeechEngine();
    access = _FakeMicrophoneAccess();
    awake = _FakeScreenAwake();
    orientation = _FakeOrientation();
    late CaptionLifecycleCoordinator gate;
    controller = CaptionController(
      engine: engine,
      settingsStore: _MemorySettingsStore(),
      mayStartCapture: () => gate.mayStartCapture,
      retryDelay: (_) async {},
    );
    gate = coordinator = CaptionLifecycleCoordinator(
      controller: controller,
      engine: engine,
      microphoneAccess: access,
      screenAwake: awake,
      orientationManager: orientation.manager,
    );
  });

  tearDown(() async {
    await coordinator.shutdown();
  });

  test(
    'rotation preserves a live session and wakelock',
    () async {
      await coordinator.initialize();
      final session = controller.currentSessionId;
      expect(session, isNotNull);
      expect(engine.startCalls, 1);
      expect(awake.enableCalls, 1);

      final applying = Completer<void>();
      orientation.holdApply = applying.future;
      final rotation = coordinator.toggleOrientation();
      await _flush();

      expect(engine.stopCalls, 0);
      expect(engine.startCalls, 1);
      expect(controller.currentSessionId, session);
      expect(awake.disableCalls, 0);
      applying.complete();
      await rotation;

      expect(engine.stopCalls, 0);
      expect(engine.startCalls, 1);
      expect(controller.currentSessionId, session);
      expect(awake.enableCalls, 1);
    },
  );

  test(
    'held orientation does not delay a real background stop',
    () async {
      await coordinator.initialize();
      final applying = Completer<void>();
      final stopReply = Completer<void>();
      orientation.holdApply = applying.future;
      engine.holdStop = stopReply.future;

      final rotation = coordinator.toggleOrientation();
      await _flush();
      final paused = coordinator.onAppLifecycle(AppLifecycleState.paused);
      final resumed = coordinator.onAppLifecycle(AppLifecycleState.resumed);
      await _flush();

      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 1);

      stopReply.complete();
      await Future.wait([paused, resumed]);
      expect(awake.disableCalls, 1);
      expect(engine.startCalls, 2);

      applying.complete();
      await rotation;
      expect(engine.startCalls, 2);
      expect(engine.stopCalls, 1);
    },
  );

  test(
    'hidden and detached serialize their held stops before resuming',
    () async {
      await coordinator.initialize();

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        final stopReply = Completer<void>();
        engine.holdStop = stopReply.future;
        final background = coordinator.onAppLifecycle(state);
        final resumed = coordinator.onAppLifecycle(AppLifecycleState.resumed);
        await _flush();
        expect(engine.stopCalls, greaterThan(0));

        stopReply.complete();
        await Future.wait([background, resumed]);
      }

      expect(engine.stopCalls, 2);
      expect(engine.startCalls, 3);
    },
  );

  test(
    'pause then resume cannot adopt a start still pending in native',
    () async {
      final startEntered = Completer<void>();
      final releaseStart = Completer<void>();
      engine.holdNextStart = releaseStart.future;
      engine.onStart = () {
        if (!startEntered.isCompleted) startEntered.complete();
      };
      final adopted = <int>[];
      controller.addListener(() {
        final sessionId = controller.currentSessionId;
        if (sessionId != null) adopted.add(sessionId);
      });

      final initializing = coordinator.initialize();
      await startEntered.future;
      final paused = coordinator.onAppLifecycle(AppLifecycleState.paused);
      final resumed = coordinator.onAppLifecycle(AppLifecycleState.resumed);
      await _flush();
      final allowedBeforeCleanup = coordinator.mayStartCapture;

      releaseStart.complete();
      await Future.wait([initializing, paused, resumed]);

      expect(allowedBeforeCleanup, isFalse);
      expect(engine.stopCalls, 1);
      expect(engine.startCalls, 2);
      expect(adopted, [2]);
      expect(controller.currentSessionId, 2);
    },
  );

  test(
    'a delayed background stop serializes one resumed replacement',
    () async {
      await coordinator.initialize();
      final stopReply = Completer<void>();
      engine.holdStop = stopReply.future;

      final background = coordinator.onAppLifecycle(AppLifecycleState.paused);
      final resumed = coordinator.onAppLifecycle(AppLifecycleState.resumed);
      await _flush();
      expect(engine.startCalls, 1);

      stopReply.complete();
      await Future.wait([background, resumed]);

      expect(engine.startCalls, 2);
      expect(engine.stopCalls, 1);
    },
  );

  test(
    'a failed stop reports its error, disables awake, and blocks restart',
    () async {
      await coordinator.initialize();
      engine.stopFailuresRemaining = 1;

      await expectLater(
        coordinator.onAppLifecycle(AppLifecycleState.paused),
        throwsStateError,
      );
      await coordinator.onAppLifecycle(AppLifecycleState.resumed);

      expect(engine.startCalls, 1);
      expect(coordinator.lifecycleMessage, contains('停止识别失败'));
      expect(coordinator.mayStartCapture, isFalse);
      expect(awake.disableCalls, 1);
    },
  );

  test(
    'wakelock disable error does not prevent background microphone stop',
    () async {
      await coordinator.initialize();
      awake.failDisable = true;

      await coordinator.onAppLifecycle(AppLifecycleState.paused);

      expect(engine.stopCalls, 1);
      expect(controller.currentSessionId, isNull);
      expect(awake.disableCalls, 1);
      expect(coordinator.lifecycleMessage, contains('无法关闭屏幕常亮'));
    },
  );

  test(
    'resumed health check leaves a healthy native session untouched',
    () async {
      await coordinator.initialize();
      final id = controller.currentSessionId;

      await coordinator.onAppLifecycle(AppLifecycleState.inactive);
      await coordinator.onAppLifecycle(AppLifecycleState.resumed);

      expect(engine.healthCalls, 1);
      expect(engine.stopCalls, 0);
      expect(engine.startCalls, 1);
      expect(controller.currentSessionId, id);
    },
  );

  test(
    'a late positive health reply cannot keep recording in background',
    () async {
      await coordinator.initialize();
      final healthReply = Completer<bool>();
      engine.nextHealthReply = healthReply.future;

      final resumed = coordinator.onAppLifecycle(AppLifecycleState.resumed);
      await _flush();
      expect(engine.healthCalls, 1);
      final paused = coordinator.onAppLifecycle(AppLifecycleState.paused);
      healthReply.complete(true);
      await Future.wait([resumed, paused]);

      expect(engine.stopCalls, 1);
      expect(engine.startCalls, 1);
      expect(controller.currentSessionId, isNull);
      expect(controller.status, CaptionStatus.idle);
      expect(awake.disableCalls, 1);
    },
  );

  test('shutdown discards a late positive health reply', () async {
    await coordinator.initialize();
    final healthReply = Completer<bool>();
    engine.nextHealthReply = healthReply.future;

    final resumed = coordinator.onAppLifecycle(AppLifecycleState.resumed);
    await _flush();
    expect(engine.healthCalls, 1);
    final shutdown = coordinator.shutdown();
    healthReply.complete(true);
    await Future.wait([resumed, shutdown]);

    expect(engine.stopCalls, 1);
    expect(engine.startCalls, 1);
    expect(engine.disposed, isTrue);
  });

  test(
    'resumed health check cleans a stale session then starts once',
    () async {
      await coordinator.initialize();
      engine.forceHealth = false;

      await coordinator.onAppLifecycle(AppLifecycleState.resumed);

      expect(engine.healthCalls, 1);
      expect(engine.stopCalls, 1);
      expect(engine.startCalls, 2);
    },
  );

  test(
    'pending resume permission keeps an existing session but cannot start one',
    () async {
      await coordinator.initialize();
      final original = controller.currentSessionId;
      final statusReply = Completer<MicAccessState>();
      access.nextStatus = statusReply.future;

      final resumed = coordinator.onAppLifecycle(AppLifecycleState.resumed);
      await _flush();
      expect(controller.currentSessionId, original);
      expect(engine.startCalls, 1);
      expect(coordinator.mayStartCapture, isFalse);

      statusReply.complete(MicAccessState.granted);
      await resumed;
      expect(engine.startCalls, 1);
      expect(controller.currentSessionId, original);
    },
  );

  test('permission completion while inactive does not start capture', () async {
    access.initial = MicAccessState.denied;
    await coordinator.initialize();
    access.requestReply = Completer<MicAccessState>();

    final request = coordinator.requestMicrophonePermission();
    await coordinator.onAppLifecycle(AppLifecycleState.inactive);
    access.requestReply!.complete(MicAccessState.granted);
    await request;

    expect(engine.startCalls, 0);
    expect(coordinator.captureDesired, isTrue);
    expect(coordinator.mayStartCapture, isFalse);
  });

  test(
    'granted permission after background waits for resumed fresh status',
    () async {
      access.initial = MicAccessState.denied;
      await coordinator.initialize();
      access.requestReply = Completer<MicAccessState>();

      final request = coordinator.requestMicrophonePermission();
      await coordinator.onAppLifecycle(AppLifecycleState.paused);
      access.initial = MicAccessState.granted;
      access.requestReply!.complete(MicAccessState.granted);
      await request;

      expect(engine.startCalls, 0);
      expect(coordinator.mayStartCapture, isFalse);

      await coordinator.onAppLifecycle(AppLifecycleState.resumed);
      expect(engine.startCalls, 1);
      expect(coordinator.mayStartCapture, isTrue);
    },
  );

  test(
    'stale permission reply after shutdown cannot restart capture',
    () async {
      final statusReply = Completer<MicAccessState>();
      access.nextStatus = statusReply.future;
      final initializing = coordinator.initialize();
      await _flush();

      await coordinator.shutdown();
      statusReply.complete(MicAccessState.granted);
      await initializing;

      expect(engine.startCalls, 0);
      expect(engine.disposed, isTrue);
    },
  );

  test('manual retry recovers after bounded native start failures', () async {
    engine.failuresRemaining = 4;
    await coordinator.initialize();
    expect(engine.startCalls, 4);
    expect(controller.status, CaptionStatus.failed);
    expect(controller.isStopConfirmed, isFalse);

    await coordinator.retryCapture();

    expect(engine.stopCalls, 1);
    expect(engine.startCalls, 5);
    expect(controller.status, CaptionStatus.listening);
    expect(controller.currentSessionId, isNotNull);
  });

  test('failed retry cleanup still blocks a new native start', () async {
    engine.failuresRemaining = 4;
    await coordinator.initialize();
    engine.stopFailuresRemaining = 1;

    await expectLater(coordinator.retryCapture(), throwsStateError);

    expect(engine.startCalls, 4);
    expect(controller.isStopConfirmed, isFalse);
    expect(coordinator.mayStartCapture, isFalse);
    expect(coordinator.lifecycleMessage, contains('停止识别失败'));

    await coordinator.retryCapture();
    expect(engine.stopCalls, 2);
    expect(engine.startCalls, 5);
    expect(controller.status, CaptionStatus.listening);
  });

  test('terminal recognition failure releases the wakelock', () async {
    await coordinator.initialize();
    final id = controller.currentSessionId!;
    expect(awake.enableCalls, 1);
    engine.failingLanguages.add('auto');

    engine.emit(SpeechEvent(SpeechEventKind.error, 'decoder failed', id));
    await _flush();
    await _flush();

    expect(controller.status, CaptionStatus.failed);
    expect(awake.disableCalls, 1);
  });

  test(
    'partial caption events do not repeatedly query native health',
    () async {
      await coordinator.initialize();
      final id = controller.currentSessionId!;
      for (var index = 0; index < 10; index++) {
        engine.emit(SpeechEvent(SpeechEventKind.partial, '$index', id));
      }
      await _flush();

      expect(engine.healthCalls, 0);
      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 0);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _MemorySettingsStore implements SettingsStore {
  CaptionSettings value = CaptionSettings();

  @override
  Future<CaptionSettings> load() async => value;

  @override
  Future<void> save(CaptionSettings settings) async => value = settings;
}

class _FakeSpeechEngine implements SpeechEngine {
  final _events = StreamController<SpeechEvent>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;
  int healthCalls = 0;
  int stopFailuresRemaining = 0;
  int failuresRemaining = 0;
  bool disposed = false;
  final failingLanguages = <String>{};
  int? _activeSessionId;
  bool? forceHealth;
  Future<bool>? nextHealthReply;
  Future<void>? holdStop;
  Future<void>? holdNextStart;
  void Function()? onStart;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<int> start() async {
    final pending = holdNextStart;
    holdNextStart = null;
    onStart?.call();
    await pending;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      startCalls++;
      throw StateError('test start failure');
    }
    if (failingLanguages.contains('auto')) {
      throw StateError('test auto start failure');
    }
    return _activeSessionId = ++startCalls;
  }

  @override
  Future<bool> isSessionActive(int sessionId) async {
    healthCalls++;
    final pending = nextHealthReply;
    nextHealthReply = null;
    return await pending ?? (forceHealth ?? _activeSessionId == sessionId);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await holdStop;
    if (stopFailuresRemaining > 0) {
      stopFailuresRemaining--;
      throw StateError('test stop failure');
    }
    _activeSessionId = null;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }

  void emit(SpeechEvent event) => _events.add(event);
}

class _FakeMicrophoneAccess implements MicrophoneAccess {
  MicAccessState initial = MicAccessState.granted;
  Future<MicAccessState>? nextStatus;
  Completer<MicAccessState>? requestReply;

  @override
  Future<MicAccessState> status() => nextStatus ?? Future.value(initial);

  @override
  Future<MicAccessState> request() =>
      requestReply?.future ?? Future.value(initial);

  @override
  Future<bool> openSettings() async => true;
}

class _FakeScreenAwake implements ScreenAwake {
  int enableCalls = 0;
  int disableCalls = 0;
  bool failDisable = false;

  @override
  Future<void> enable() async => enableCalls++;

  @override
  Future<void> disable() async {
    disableCalls++;
    if (failDisable) throw StateError('test wakelock disable failure');
  }
}

class _FakeOrientation {
  Future<void>? holdApply;

  late final manager = OrientationManager(
    setOrientations: (_) => holdApply ?? Future.value(),
  );
}

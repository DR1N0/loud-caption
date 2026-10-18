import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/captions/caption_controller.dart';
import 'package:loud_caption/captions/caption_line.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/translation/noop_translation_engine.dart';

void main() {
  group('CaptionController', () {
    late FakeSpeechEngine engine;
    late MemorySettingsStore store;
    late CaptionController captions;

    setUp(() {
      engine = FakeSpeechEngine();
      store = MemorySettingsStore();
      captions = CaptionController(engine: engine, settingsStore: store);
    });

    tearDown(() async {
      await captions.stop();
      captions.dispose();
      await engine.dispose();
    });

    test('a partial replaces its open line and a final commits it', () async {
      await captions.initialize();
      await captions.start();

      engine.emit(const SpeechEvent(SpeechEventKind.partial, 'he', 1));
      await flushEvents();
      engine.emit(const SpeechEvent(SpeechEventKind.partial, 'hello', 1));
      await flushEvents();

      expect(captions.partialText, 'hello');
      expect(captions.displayText, 'hello');
      expect(captions.committedLines, isEmpty);

      engine.emit(const SpeechEvent(SpeechEventKind.finalText, 'hello', 1));
      await flushEvents();

      expect(captions.committedLines, [const CaptionLine('hello')]);
      expect(captions.partialText, isEmpty);
      expect(captions.displayText, 'hello');
    });

    test(
      'completed lines keep accumulating — how many are shown is the UI\'s '
      'call, not a fixed controller-level limit',
      () async {
        await captions.initialize();
        await captions.start();

        for (final text in ['one', 'two', 'three', 'four', 'five']) {
          engine.emit(SpeechEvent(SpeechEventKind.finalText, text, 1));
          await flushEvents();
        }
        engine.emit(const SpeechEvent(SpeechEventKind.partial, 'six', 1));
        await flushEvents();

        expect(captions.committedLines, [
          const CaptionLine('one'),
          const CaptionLine('two'),
          const CaptionLine('three'),
          const CaptionLine('four'),
          const CaptionLine('five'),
        ]);
        expect(captions.partialText, 'six');
        expect(store.saved, isEmpty);
      },
    );

    test('an unchanged partial does not notify listeners', () async {
      await captions.initialize();
      await captions.start();
      var notifications = 0;
      captions.addListener(() => notifications++);

      engine.emit(const SpeechEvent(SpeechEventKind.partial, 'same', 1));
      await flushEvents();
      final afterFirstPartial = notifications;
      engine.emit(const SpeechEvent(SpeechEventKind.partial, 'same', 1));
      await flushEvents();

      expect(notifications, afterFirstPartial);
    });

    test('an error preserves readable captions while it retries', () async {
      await captions.initialize();
      await captions.start();
      engine.emit(const SpeechEvent(SpeechEventKind.finalText, 'readable', 1));
      await flushEvents();
      engine.emit(const SpeechEvent(SpeechEventKind.partial, 'open line', 1));
      await flushEvents();

      engine.emit(const SpeechEvent(SpeechEventKind.error, 'stream lost', 1));
      await flushEvents();

      expect(captions.committedLines, [const CaptionLine('readable')]);
      expect(captions.partialText, 'open line');
      expect(captions.displayText, 'readable\nopen line');
      expect(captions.message, 'stream lost');
      expect(captions.status, CaptionStatus.retrying);
      expect(engine.started, ['auto']);
    });

    test(
      'only three scheduled retries follow an initial start failure',
      () async {
        engine.failuresRemaining = 4;
        final waits = <Duration>[];
        final retryingCaptions = CaptionController(
          engine: engine,
          settingsStore: store,
          retryDelay: (duration) async => waits.add(duration),
        );
        addTearDown(() async {
          await retryingCaptions.stop();
          retryingCaptions.dispose();
        });

        await retryingCaptions.initialize();
        await retryingCaptions.start();

        expect(waits, [
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
          const Duration(seconds: 2),
        ]);
        expect(engine.started, hasLength(4));
        expect(retryingCaptions.status, CaptionStatus.failed);
      },
    );

    test('stop invalidates a pending retry and prevents a restart', () async {
      engine.failuresRemaining = 1;
      final waitStarted = Completer<void>();
      final releaseWait = Completer<void>();
      final retryingCaptions = CaptionController(
        engine: engine,
        settingsStore: store,
        retryDelay: (duration) {
          waitStarted.complete();
          return releaseWait.future;
        },
      );
      addTearDown(() async {
        retryingCaptions.dispose();
      });

      await retryingCaptions.initialize();
      final starting = retryingCaptions.start();
      await waitStarted.future;
      await retryingCaptions.stop();
      releaseWait.complete();
      await starting;

      expect(engine.started, ['auto']);
      expect(captions.status, CaptionStatus.idle);
      expect(retryingCaptions.status, CaptionStatus.idle);
    });

    test(
      'revoked gate rejects a late native start and confirms cleanup',
      () async {
        var canCapture = true;
        final started = Completer<void>();
        final releaseStart = Completer<void>();
        final gatedEngine = FakeSpeechEngine()..holdStart = releaseStart.future;
        final controller = CaptionController(
          engine: gatedEngine,
          settingsStore: MemorySettingsStore(),
          mayStartCapture: () => canCapture,
        );
        addTearDown(() async {
          await controller.stop();
          controller.dispose();
          await gatedEngine.dispose();
        });

        await controller.initialize();
        gatedEngine.onStart = started.complete;
        final starting = controller.start();
        await started.future;
        canCapture = false;
        releaseStart.complete();
        await starting;

        expect(gatedEngine.started, ['auto']);
        expect(gatedEngine.stopCalls, 1);
        expect(controller.currentSessionId, isNull);
        expect(controller.status, CaptionStatus.idle);
        expect(controller.isStopConfirmed, isTrue);
      },
    );

    test('failed late-start cleanup never confirms a stopped mic', () async {
      var canCapture = true;
      final started = Completer<void>();
      final releaseStart = Completer<void>();
      final gatedEngine = FakeSpeechEngine()
        ..holdStart = releaseStart.future
        ..stopFailuresRemaining = 1;
      final controller = CaptionController(
        engine: gatedEngine,
        settingsStore: MemorySettingsStore(),
        mayStartCapture: () => canCapture,
        retryDelay: (_) async {},
      );
      addTearDown(() async {
        await controller.stop();
        controller.dispose();
        await gatedEngine.dispose();
      });

      await controller.initialize();
      gatedEngine.onStart = started.complete;
      final starting = controller.start();
      await started.future;
      canCapture = false;
      releaseStart.complete();
      await starting;

      expect(controller.currentSessionId, isNull);
      expect(controller.status, CaptionStatus.failed);
      expect(controller.message, contains('停止识别失败'));
      expect(controller.isStopConfirmed, isFalse);
    });

    test('revoked capture gate blocks the next retry', () async {
      var canCapture = true;
      final retryStarted = Completer<void>();
      final retry = Completer<void>();
      final gatedEngine = FakeSpeechEngine();
      final controller = CaptionController(
        engine: gatedEngine,
        settingsStore: MemorySettingsStore(),
        mayStartCapture: () => canCapture,
        retryDelay: (_) {
          retryStarted.complete();
          return retry.future;
        },
      );
      addTearDown(() async {
        await controller.stop();
        controller.dispose();
        await gatedEngine.dispose();
      });

      await controller.initialize();
      await controller.start();
      expect(controller.currentSessionId, 1);
      gatedEngine.emit(const SpeechEvent(SpeechEventKind.error, 'mic lost', 1));
      await retryStarted.future;
      canCapture = false;
      retry.complete();
      await flushEvents();
      await flushEvents();

      expect(gatedEngine.started, ['auto']);
      expect(controller.currentSessionId, isNull);
      expect(controller.isStopConfirmed, isTrue);
      expect(controller.status, CaptionStatus.idle);
    });

    test(
      'a stream-error stop failure becomes stable without a new start',
      () async {
        await captions.initialize();
        await captions.start();
        engine.emit(const SpeechEvent(SpeechEventKind.finalText, 'kept', 1));
        await flushEvents();
        engine.stopFailuresRemaining = 1;

        engine.emit(const SpeechEvent(SpeechEventKind.error, 'stream lost', 1));
        await flushEvents();
        await flushEvents();

        expect(engine.started, ['auto']);
        expect(captions.committedLines, [const CaptionLine('kept')]);
        expect(captions.status, CaptionStatus.failed);
        expect(captions.message, contains('停止识别失败'));
      },
    );

    test(
      'failed stop blocks dispose until an explicit successful retry',
      () async {
        await captions.initialize();
        await captions.start();
        engine.stopFailuresRemaining = 1;

        await expectLater(captions.stop(), throwsStateError);

        expect(captions.status, CaptionStatus.failed);
        expect(captions.message, contains('停止识别失败'));
        expect(() => captions.dispose(), throwsStateError);

        await captions.stop();

        expect(captions.status, CaptionStatus.idle);
        expect(captions.message, isNull);
        captions.dispose();
      },
    );

    test('font size steps at the presets and orientation persists', () async {
      await captions.initialize();

      await captions.increaseFont();
      await captions.increaseFont();
      await captions.increaseFont();
      await captions.decreaseFont();
      await captions.toggleOrientation();

      expect(captions.settings.fontSize, 64.0);
      expect(captions.settings.landscape, isTrue);
      expect(store.value, captions.settings);
    });

    test(
      'cycleMode advances captions -> translateAll -> translateCustom',
      () async {
        await captions.initialize();

        await captions.cycleMode();
        expect(captions.settings.captionMode, CaptionMode.translateAll);
        await captions.cycleMode();
        expect(captions.settings.captionMode, CaptionMode.translateCustom);
        await captions.cycleMode();
        expect(captions.settings.captionMode, CaptionMode.captions);
        expect(store.value, captions.settings);
      },
    );

    test('toggleTheme flips between dark and light and persists', () async {
      await captions.initialize();
      expect(captions.settings.themeMode, AppThemeMode.dark);

      await captions.toggleTheme();
      expect(captions.settings.themeMode, AppThemeMode.light);
      await captions.toggleTheme();
      expect(captions.settings.themeMode, AppThemeMode.dark);
      expect(store.value, captions.settings);
    });

    test('setTranslateAllTarget and setRoutingTarget persist', () async {
      await captions.initialize();

      await captions.setTranslateAllTarget('ja');
      await captions.setRoutingTarget('zh', 'en');

      expect(captions.settings.translateAllTarget, 'ja');
      expect(captions.settings.routingTargetFor('zh'), 'en');
      expect(captions.settings.routingTargetFor('en'), 'en');
      expect(store.value, captions.settings);
    });

    test('a translation engine is exposed but not otherwise used yet', () {
      final translationEngine = NoopTranslationEngine();
      final translatingCaptions = CaptionController(
        engine: FakeSpeechEngine(),
        settingsStore: MemorySettingsStore(),
        translationEngine: translationEngine,
      );
      addTearDown(translatingCaptions.dispose);

      expect(translatingCaptions.translationEngine, same(translationEngine));
    });
  });
}

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore({CaptionSettings? initial})
    : value = initial ?? CaptionSettings();

  CaptionSettings value;
  final List<CaptionSettings> saved = [];
  bool failSaves = false;

  @override
  Future<CaptionSettings> load() async => value;

  @override
  Future<void> save(CaptionSettings next) async {
    if (failSaves) throw StateError('test-only save failure');
    value = next;
    saved.add(next);
  }
}

class FakeSpeechEngine implements SpeechEngine {
  final controller = StreamController<SpeechEvent>.broadcast();
  final started = <String>[];
  int nextId = 0;
  int failuresRemaining = 0;
  int stopFailuresRemaining = 0;
  int stopCalls = 0;
  Future<void>? holdStart;
  void Function()? onStart;
  int? _activeSessionId;

  @override
  Stream<SpeechEvent> get events => controller.stream;

  @override
  Future<int> start(String languageCode) async {
    started.add(languageCode);
    onStart?.call();
    await holdStart;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('test-only start failure');
    }
    return _activeSessionId = ++nextId;
  }

  @override
  Future<bool> isSessionActive(int sessionId) async =>
      _activeSessionId == sessionId;

  @override
  Future<void> stop() async {
    stopCalls++;
    if (stopFailuresRemaining > 0) {
      stopFailuresRemaining--;
      throw StateError('test-only stop failure');
    }
    _activeSessionId = null;
  }

  @override
  Future<void> dispose() => controller.close();

  void emit(SpeechEvent event) => controller.add(event);

  @override
  List<SpeechEngineConfigOption> get configOptions => const [];
  @override
  Map<String, String> get currentConfig => const {};
  @override
  Future<void> applyConfig(Map<String, String> values) async {}
}

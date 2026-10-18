import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/lifecycle/screen_awake.dart';
import 'package:loud_caption/main.dart';
import 'package:loud_caption/permissions/microphone_access.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/orientation_manager.dart';

import '../translation/fake_translation_engine.dart';

void main() {
  testWidgets('requests microphone access only after tapping 开始', (
    tester,
  ) async {
    final fixture = _Fixture(access: MicAccessState.denied);
    await fixture.pump(tester);

    expect(find.text('开始'), findsOneWidget);
    expect(fixture.engine.startCalls, 0);
    await tester.tap(find.text('开始'));
    await fixture.advance(tester);

    expect(fixture.microphone.requestCalls, 1);
    expect(fixture.engine.startCalls, 1);
    expect(fixture.awake.enableCalls, 1);
    expect(find.text('正在聆听'), findsOneWidget);
    await fixture.close(tester);
  });

  testWidgets('permanent denial opens OS settings, not a microphone session', (
    tester,
  ) async {
    final fixture = _Fixture(access: MicAccessState.permanentlyDenied);
    await fixture.pump(tester);

    await tester.tap(find.text('去设置开启权限'));
    await fixture.advance(tester);
    expect(fixture.microphone.openSettingsCalls, 1);
    expect(fixture.engine.startCalls, 0);
    await fixture.close(tester);
  });

  testWidgets(
    'portrait shows six controls in one left-to-right row and renders '
    'changing partial captions',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final fixture = _Fixture();
      await fixture.pump(tester);

      expect(find.bySemanticsLabel('增大字幕字号'), findsOneWidget);
      expect(find.bySemanticsLabel('减小字幕字号'), findsOneWidget);
      expect(find.bySemanticsLabel('切换屏幕方向'), findsOneWidget);
      expect(find.bySemanticsLabel('切换模式'), findsOneWidget);
      expect(find.bySemanticsLabel('打开设置'), findsOneWidget);
      expect(find.bySemanticsLabel('切换昼夜模式'), findsOneWidget);
      expect(find.textContaining('暂停'), findsNothing);

      final order = [
        tester.getCenter(find.bySemanticsLabel('增大字幕字号')).dx,
        tester.getCenter(find.bySemanticsLabel('减小字幕字号')).dx,
        tester.getCenter(find.bySemanticsLabel('切换屏幕方向')).dx,
        tester.getCenter(find.bySemanticsLabel('切换模式')).dx,
        tester.getCenter(find.bySemanticsLabel('打开设置')).dx,
        tester.getCenter(find.bySemanticsLabel('切换昼夜模式')).dx,
      ];
      expect(order, equals(List<double>.from(order)..sort()));
      expect(
        tester.getCenter(find.bySemanticsLabel('增大字幕字号')).dy,
        tester.getCenter(find.bySemanticsLabel('切换昼夜模式')).dy,
      );

      final session = fixture.engine.activeSessionId!;
      fixture.engine.emit(SpeechEvent(SpeechEventKind.partial, '你', session));
      await fixture.advance(tester);
      fixture.engine.emit(SpeechEvent(SpeechEventKind.partial, '你好', session));
      await fixture.advance(tester);
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('你'), findsNothing);

      await tester.tap(find.bySemanticsLabel('增大字幕字号'));
      await fixture.advance(tester);
      expect(fixture.store.value.fontSize, 64);
      await tester.tap(find.bySemanticsLabel('减小字幕字号'));
      await fixture.advance(tester);
      expect(fixture.store.value.fontSize, 48);
      expect(fixture.engine.stopCalls, 0);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'committing enough lines to overflow the viewport auto-scrolls so the '
    'latest one is visible without a manual scroll',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      final session = fixture.engine.activeSessionId!;

      for (var i = 0; i < 10; i++) {
        fixture.engine.emit(
          SpeechEvent(SpeechEventKind.finalText, 'caption line $i', session),
        );
        await fixture.advance(tester);
      }

      final position = tester.state<ScrollableState>(
        find.byType(Scrollable),
      ).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, closeTo(position.maxScrollExtent, 1.0));
      await fixture.close(tester);
    },
  );

  testWidgets(
    'scrolling away from the bottom to re-read older lines pauses '
    'auto-scroll until scrolling back near the bottom',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      final session = fixture.engine.activeSessionId!;

      for (var i = 0; i < 10; i++) {
        fixture.engine.emit(
          SpeechEvent(SpeechEventKind.finalText, 'caption line $i', session),
        );
        await fixture.advance(tester);
      }

      final position = tester.state<ScrollableState>(
        find.byType(Scrollable),
      ).position;

      // Drag far enough to guarantee landing away from the bottom,
      // regardless of exact content height.
      await tester.drag(find.byType(Scrollable), const Offset(0, 10000));
      await fixture.advance(tester);
      final scrolledAwayPixels = position.pixels;
      expect(scrolledAwayPixels, lessThan(position.maxScrollExtent - 24));

      // A new line arrives while the user is reading history — the view
      // must not be yanked back down to the bottom.
      fixture.engine.emit(
        SpeechEvent(SpeechEventKind.finalText, 'new line', session),
      );
      await fixture.advance(tester);
      expect(position.pixels, closeTo(scrolledAwayPixels, 1.0));

      // Scrolling back near the bottom resumes auto-scroll for the next
      // new line.
      await tester.drag(find.byType(Scrollable), const Offset(0, -10000));
      await fixture.advance(tester);
      fixture.engine.emit(
        SpeechEvent(SpeechEventKind.finalText, 'another line', session),
      );
      await fixture.advance(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 1.0));

      await fixture.close(tester);
    },
  );

  testWidgets('landscape rotates the control bar into a side rail, '
      'reversed top-to-bottom', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final fixture = _Fixture();
    await fixture.pump(tester);

    expect(find.bySemanticsLabel('增大字幕字号'), findsOneWidget);
    expect(find.bySemanticsLabel('减小字幕字号'), findsOneWidget);
    expect(find.bySemanticsLabel('切换屏幕方向'), findsOneWidget);
    expect(find.bySemanticsLabel('切换模式'), findsOneWidget);
    expect(find.bySemanticsLabel('打开设置'), findsOneWidget);
    expect(find.bySemanticsLabel('切换昼夜模式'), findsOneWidget);

    final topToBottom = [
      tester.getCenter(find.bySemanticsLabel('切换昼夜模式')).dy,
      tester.getCenter(find.bySemanticsLabel('打开设置')).dy,
      tester.getCenter(find.bySemanticsLabel('切换模式')).dy,
      tester.getCenter(find.bySemanticsLabel('切换屏幕方向')).dy,
      tester.getCenter(find.bySemanticsLabel('减小字幕字号')).dy,
      tester.getCenter(find.bySemanticsLabel('增大字幕字号')).dy,
    ];
    expect(topToBottom, equals(List<double>.from(topToBottom)..sort()));
    expect(
      tester.getCenter(find.bySemanticsLabel('切换昼夜模式')).dx,
      tester.getCenter(find.bySemanticsLabel('增大字幕字号')).dx,
    );
    await fixture.close(tester);
  });

  testWidgets('rotation keeps one active speech session and wakelock', (
    tester,
  ) async {
    final applied = <List<DeviceOrientation>>[];
    final fixture = _Fixture(
      setOrientations: (orientations) async => applied.add(orientations),
    );
    await fixture.pump(tester);
    final session = fixture.engine.activeSessionId;

    await tester.tap(find.bySemanticsLabel('切换屏幕方向'));
    await fixture.advance(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await fixture.advance(tester);

    expect(applied.last, const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    expect(fixture.store.value.landscape, isTrue);
    expect(fixture.engine.activeSessionId, session);
    expect(fixture.engine.startCalls, 1);
    expect(fixture.engine.stopCalls, 0);
    expect(fixture.awake.disableCalls, 0);
    await fixture.close(tester);
  });

  testWidgets('system UI platform failure does not become an uncaught error', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        throw PlatformException(code: 'test-system-ui-failure');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final fixture = _Fixture(access: MicAccessState.denied);
    await fixture.pump(tester);
    expect(find.text('开始'), findsOneWidget);
    await fixture.close(tester);
  });

  testWidgets(
    'cycling into 翻译 mode prompts to download the model, showing live '
    'progress, then loads it',
    (tester) async {
      final fixture = _Fixture();
      fixture.translation.modelDownloaded = false;
      await fixture.pump(tester);

      await tester.tap(find.bySemanticsLabel('切换模式'));
      await fixture.advance(tester);
      expect(find.text('下载翻译模型'), findsOneWidget);
      expect(fixture.translation.isLoaded, isFalse);

      await tester.tap(find.text('下载'));
      await fixture.advance(tester);
      expect(find.text('正在下载翻译模型…'), findsOneWidget);

      fixture.translation.emitLoadProgress(
        50 * 1024 * 1024,
        totalBytes: 100 * 1024 * 1024,
      );
      await fixture.advance(tester);
      expect(find.text('50.0 MB / 100.0 MB'), findsOneWidget);

      fixture.translation.completeLoad();
      await fixture.advance(tester);

      expect(fixture.translation.isLoaded, isTrue);
      expect(find.text('正在下载翻译模型…'), findsNothing);
      expect(fixture.store.value.captionMode, CaptionMode.translateAll);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'cycling into 翻译 mode skips the confirm dialog when the model file is '
    'already on disk from a previous session — isLoaded resets every '
    'process start, but the download does not need to happen again',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);

      await tester.tap(find.bySemanticsLabel('切换模式'));
      await fixture.advance(tester);
      expect(find.text('下载翻译模型'), findsNothing);
      expect(find.text('正在加载翻译模型…'), findsOneWidget);

      fixture.translation.completeLoad();
      await fixture.advance(tester);

      expect(fixture.translation.isLoaded, isTrue);
      expect(fixture.store.value.captionMode, CaptionMode.translateAll);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'a translation mode already active from a previous session loads the '
    'engine on startup, without requiring the user to cycle the mode again',
    (tester) async {
      final fixture = _Fixture();
      fixture.store.value = fixture.store.value
          .withCaptionMode(CaptionMode.translateAll)
          .withTranslateAllTarget('en');
      await fixture.pump(tester);

      expect(find.text('正在加载翻译模型…'), findsOneWidget);
      fixture.translation.completeLoad();
      await fixture.advance(tester);

      expect(fixture.translation.isLoaded, isTrue);
      await fixture.close(tester);
    },
  );

  testWidgets('a failed translation model download returns the mode to 字幕', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.translation.modelDownloaded = false;
    await fixture.pump(tester);

    await tester.tap(find.bySemanticsLabel('切换模式'));
    await fixture.advance(tester);
    await tester.tap(find.text('下载'));
    await fixture.advance(tester);

    fixture.translation.failLoad(StateError('network error'));
    await fixture.advance(tester);

    expect(fixture.translation.isLoaded, isFalse);
    expect(fixture.store.value.captionMode, CaptionMode.captions);
    expect(find.textContaining('翻译模型下载失败'), findsOneWidget);
    await fixture.close(tester);
  });

  testWidgets('declining the download returns the mode to 字幕', (tester) async {
    final fixture = _Fixture();
    fixture.translation.modelDownloaded = false;
    await fixture.pump(tester);

    await tester.tap(find.bySemanticsLabel('切换模式'));
    await fixture.advance(tester);
    await tester.tap(find.text('取消'));
    await fixture.advance(tester);

    expect(fixture.translation.isLoaded, isFalse);
    expect(fixture.store.value.captionMode, CaptionMode.captions);
    await fixture.close(tester);
  });

  testWidgets(
    'a translated committed line shows both original and translation',
    (tester) async {
      final fixture = _Fixture();
      fixture.translation.isLoaded = true;
      fixture.store.value = fixture.store.value
          .withCaptionMode(CaptionMode.translateAll)
          .withTranslateAllTarget('en');
      await fixture.pump(tester);

      final session = fixture.engine.activeSessionId!;
      fixture.engine.emit(
        SpeechEvent(
          SpeechEventKind.finalText,
          '你好',
          session,
          detectedLanguage: 'zh',
        ),
      );
      await fixture.advance(tester);

      fixture.translation.calls.single.request.emit('Hello');
      await fixture.advance(tester);

      expect(find.text('你好'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      await fixture.close(tester);
    },
  );
}

class _Fixture {
  _Fixture({
    MicAccessState access = MicAccessState.granted,
    SetOrientations? setOrientations,
  }) : microphone = _FakeMicrophoneAccess(access),
       store = _MemorySettingsStore(CaptionSettings()),
       orientationManager = OrientationManager(
         setOrientations: setOrientations ?? (_) async {},
       );

  final engine = _FakeSpeechEngine();
  final awake = _FakeScreenAwake();
  final translation = FakeTranslationEngine();
  final _FakeMicrophoneAccess microphone;
  final _MemorySettingsStore store;
  final OrientationManager orientationManager;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      CaptionApp(
        engine: engine,
        settingsStore: store,
        translationEngine: translation,
        microphoneAccess: microphone,
        screenAwake: awake,
        orientationManager: orientationManager,
        isModelReady: () async => true,
      ),
    );
    await advance(tester);
  }

  Future<void> advance(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester);
    expect(engine.disposed, isTrue);
  }
}

class _FakeMicrophoneAccess implements MicrophoneAccess {
  _FakeMicrophoneAccess(this.state);

  MicAccessState state;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<MicAccessState> status() async => state;

  @override
  Future<MicAccessState> request() async {
    requestCalls++;
    return state = MicAccessState.granted;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}

class _FakeScreenAwake implements ScreenAwake {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enable() async => enableCalls++;

  @override
  Future<void> disable() async => disableCalls++;
}

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore(this.value);

  CaptionSettings value;

  @override
  Future<CaptionSettings> load() async => value;

  @override
  Future<void> save(CaptionSettings next) async => value = next;
}

class _FakeSpeechEngine implements SpeechEngine {
  final _events = StreamController<SpeechEvent>.broadcast();
  final startedLanguages = <String>[];
  int? activeSessionId;
  int nextSessionId = 0;
  int stopCalls = 0;
  bool disposed = false;

  int get startCalls => startedLanguages.length;

  void emit(SpeechEvent event) => _events.add(event);

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<int> start(String languageCode) async {
    startedLanguages.add(languageCode);
    return activeSessionId = ++nextSessionId;
  }

  @override
  Future<bool> isSessionActive(int id) async => activeSessionId == id;

  @override
  Future<void> stop() async {
    stopCalls++;
    activeSessionId = null;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }

  @override
  List<SpeechEngineConfigOption> get configOptions => const [];
  @override
  Map<String, String> get currentConfig => const {};
  @override
  Future<void> applyConfig(Map<String, String> values) async {}
}

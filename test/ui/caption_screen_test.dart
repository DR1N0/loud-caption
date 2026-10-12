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

  testWidgets('shows five controls and renders changing partial captions', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);

    expect(find.bySemanticsLabel('增大字幕字号'), findsOneWidget);
    expect(find.bySemanticsLabel('减小字幕字号'), findsOneWidget);
    expect(find.bySemanticsLabel('切换语言'), findsOneWidget);
    expect(find.bySemanticsLabel('切换屏幕方向'), findsOneWidget);
    expect(find.bySemanticsLabel('打开设置'), findsOneWidget);
    expect(find.textContaining('暂停'), findsNothing);

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
  });

  testWidgets('one enabled language disables the switch control', (
    tester,
  ) async {
    final fixture = _Fixture(
      settings: CaptionSettings(enabledLanguages: const ['zh']),
    );
    await fixture.pump(tester);

    final switchButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '切换语言',
      ),
    );
    expect(switchButton.onPressed, isNull);
    expect(fixture.engine.startCalls, 1);
    await fixture.close(tester);
  });

  testWidgets('two languages switch the model without clearing the last line', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    fixture.engine.emit(
      SpeechEvent(
        SpeechEventKind.finalText,
        '上一句',
        fixture.engine.activeSessionId!,
      ),
    );
    await fixture.advance(tester);

    await tester.tap(find.bySemanticsLabel('切换语言'));
    await fixture.advance(tester);
    expect(fixture.engine.startedLanguages, ['zh', 'en']);
    expect(fixture.engine.stopCalls, 1);
    expect(find.text('上一句'), findsOneWidget);
    await fixture.close(tester);
  });

  testWidgets('three enabled languages use a picker', (tester) async {
    final fixture = _Fixture(
      settings: CaptionSettings(
        catalog: const [
          InstalledLanguage('zh', '中文'),
          InstalledLanguage('en', 'English'),
          InstalledLanguage('es', 'Español'),
        ],
        enabledLanguages: const ['zh', 'en', 'es'],
      ),
    );
    await fixture.pump(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Español'));
    await fixture.advance(tester);
    expect(fixture.engine.startedLanguages, ['zh', 'es']);
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
}

class _Fixture {
  _Fixture({
    MicAccessState access = MicAccessState.granted,
    CaptionSettings? settings,
    SetOrientations? setOrientations,
  }) : microphone = _FakeMicrophoneAccess(access),
       store = _MemorySettingsStore(settings ?? CaptionSettings()),
       orientationManager = OrientationManager(
         setOrientations: setOrientations ?? (_) async {},
       );

  final engine = _FakeSpeechEngine();
  final awake = _FakeScreenAwake();
  final _FakeMicrophoneAccess microphone;
  final _MemorySettingsStore store;
  final OrientationManager orientationManager;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      CaptionApp(
        engine: engine,
        settingsStore: store,
        microphoneAccess: microphone,
        screenAwake: awake,
        orientationManager: orientationManager,
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
}

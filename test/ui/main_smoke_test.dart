import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/lifecycle/screen_awake.dart';
import 'package:loud_caption/main.dart';
import 'package:loud_caption/permissions/microphone_access.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/orientation_manager.dart';

void main() {
  testWidgets(
    'root keeps permission guidance and the same speech session through settings',
    (tester) async {
      final engine = _FakeSpeechEngine();
      final microphone = _FakeMicrophoneAccess();
      final awake = _FakeScreenAwake();
      await tester.pumpWidget(
        CaptionApp(
          engine: engine,
          settingsStore: _MemorySettingsStore(),
          microphoneAccess: microphone,
          screenAwake: awake,
          orientationManager: OrientationManager(setOrientations: (_) async {}),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('开启麦克风权限后即可显示实时字幕'), findsOneWidget);
      expect(find.text('正在聆听'), findsNothing);
      expect(engine.startCalls, 0);

      await tester.tap(find.text('开始'));
      await tester.pump();
      await tester.pump();

      expect(find.text('正在聆听'), findsOneWidget);
      expect(find.text('A+'), findsOneWidget);
      expect(find.text('A-'), findsOneWidget);
      expect(find.bySemanticsLabel('识别语言'), findsOneWidget);
      expect(find.bySemanticsLabel('切换屏幕方向'), findsOneWidget);
      expect(find.bySemanticsLabel('打开设置'), findsOneWidget);
      expect(awake.enableCalls, 1);
      expect(find.textContaining('暂停'), findsNothing);
      expect(find.textContaining('恢复'), findsNothing);

      final sessionBeforeSettings = engine.activeSessionId;
      await tester.tap(find.bySemanticsLabel('打开设置'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(engine.stopCalls, 0);
      expect(engine.startCalls, 1);
      expect(engine.activeSessionId, sessionBeforeSettings);
      expect(awake.disableCalls, 0);
      expect(find.text('设置'), findsAtLeastNWidgets(1));
      expect(find.text('暂无可配置项'), findsOneWidget);
      engine.emit(
        SpeechEvent(
          SpeechEventKind.finalText,
          '设置里继续说话',
          sessionBeforeSettings!,
        ),
      );
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('返回'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('正在聆听'), findsOneWidget);
      expect(find.text('设置里继续说话'), findsOneWidget);
      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 0);
      expect(engine.activeSessionId, sessionBeforeSettings);
      expect(awake.enableCalls, 1);
      expect(awake.disableCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets('root stops on background and resumes one session', (
    tester,
  ) async {
    final engine = _FakeSpeechEngine();
    final microphone = _FakeMicrophoneAccess();
    final awake = _FakeScreenAwake();
    await tester.pumpWidget(
      CaptionApp(
        engine: engine,
        settingsStore: _MemorySettingsStore(),
        microphoneAccess: microphone,
        screenAwake: awake,
        orientationManager: OrientationManager(setOrientations: (_) async {}),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('开始'));
    await tester.pump();
    await tester.pump();
    expect(engine.startCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(engine.stopCalls, 1);
    expect(awake.disableCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(engine.startCalls, 2);
    expect(awake.enableCalls, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });
}

class _FakeMicrophoneAccess implements MicrophoneAccess {
  MicAccessState _state = MicAccessState.denied;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<MicAccessState> request() async {
    _state = MicAccessState.granted;
    return _state;
  }

  @override
  Future<MicAccessState> status() async => _state;
}

class _FakeScreenAwake implements ScreenAwake {
  var enableCalls = 0;
  var disableCalls = 0;

  @override
  Future<void> disable() async => disableCalls++;

  @override
  Future<void> enable() async => enableCalls++;
}

class _MemorySettingsStore implements SettingsStore {
  CaptionSettings settings = CaptionSettings();

  @override
  Future<CaptionSettings> load() async => settings;

  @override
  Future<void> save(CaptionSettings next) async => settings = next;
}

class _FakeSpeechEngine implements SpeechEngine {
  var startCalls = 0;
  var stopCalls = 0;
  int? _activeSessionId;
  final _events = StreamController<SpeechEvent>.broadcast();

  int? get activeSessionId => _activeSessionId;
  void emit(SpeechEvent event) => _events.add(event);

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<int> start(String languageCode) async =>
      _activeSessionId = ++startCalls;

  @override
  Future<bool> isSessionActive(int sessionId) async =>
      _activeSessionId == sessionId;

  @override
  Future<void> stop() async {
    stopCalls++;
    _activeSessionId = null;
  }

  @override
  List<SpeechEngineConfigOption> get configOptions => const [];
  @override
  Map<String, String> get currentConfig => const {};
  @override
  Future<void> applyConfig(Map<String, String> values) async {}
}

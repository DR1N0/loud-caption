import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/downloads/download_preflight.dart';
import 'package:loud_caption/lifecycle/screen_awake.dart';
import 'package:loud_caption/main.dart';
import 'package:loud_caption/permissions/microphone_access.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/sense_voice_model_download.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/orientation_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'shows the model download screen first, then the live caption route '
    'once the download completes',
    (tester) async {
      final engine = _FakeSpeechEngine();
      final downloadController = StreamController<ModelDownloadEvent>();

      await tester.pumpWidget(
        CaptionApp(
          engine: engine,
          settingsStore: _MemorySettingsStore(),
          microphoneAccess: _GrantedMicrophoneAccess(),
          screenAwake: _NoopScreenAwake(),
          orientationManager: OrientationManager(setOrientations: (_) async {}),
          isModelReady: () async => false,
          downloadModel: () => downloadController.stream,
          preflightCheck: ({required requiredBytes}) async =>
              const DownloadPreflight(isWifi: true),
        ),
      );
      await tester.pump();

      expect(find.text('下载语音识别模型中…'), findsOneWidget);
      expect(find.text('正在聆听'), findsNothing);
      expect(engine.events, isNotNull); // engine constructed, never started
      expect(downloadController.hasListener, isTrue);

      await downloadController.close();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('下载语音识别模型中…'), findsNothing);
      expect(find.text('正在聆听'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();
    },
  );

  test('fake speech engine invalidates stale session IDs', () async {
    final engine = _FakeSpeechEngine();
    addTearDown(engine.dispose);

    final first = await engine.start('zh');
    await engine.stop();
    final second = await engine.start('en');

    expect(second, isNot(first));
    expect(await engine.isSessionActive(first), isFalse);
    expect(await engine.isSessionActive(second), isTrue);
  });

  testWidgets('the app root opens the live caption route', (tester) async {
    final engine = _FakeSpeechEngine();
    await tester.pumpWidget(
      CaptionApp(
        engine: engine,
        settingsStore: _MemorySettingsStore(),
        microphoneAccess: _GrantedMicrophoneAccess(),
        screenAwake: _NoopScreenAwake(),
        orientationManager: OrientationManager(setOrientations: (_) async {}),
        isModelReady: () async => true,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('正在聆听'), findsOneWidget);
    expect(find.text('开始测试'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
    expect(engine.stopCalls, 1);
    expect(engine.disposed, isTrue);
  });

  testWidgets(
    'a recreated root applies its saved orientation before captions',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesSettingsStore.landscapeKey: true,
      });
      final firstCalls = <List<DeviceOrientation>>[];
      await tester.pumpWidget(
        CaptionApp(
          engine: _FakeSpeechEngine(),
          settingsStore: SharedPreferencesSettingsStore(),
          microphoneAccess: _GrantedMicrophoneAccess(),
          screenAwake: _NoopScreenAwake(),
          orientationManager: OrientationManager(
            setOrientations: (orientations) async =>
                firstCalls.add(orientations),
          ),
          isModelReady: () async => true,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(firstCalls, [
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();

      SharedPreferences.setMockInitialValues({
        SharedPreferencesSettingsStore.landscapeKey: false,
      });
      final recreatedCalls = <List<DeviceOrientation>>[];
      await tester.pumpWidget(
        CaptionApp(
          engine: _FakeSpeechEngine(),
          settingsStore: SharedPreferencesSettingsStore(),
          microphoneAccess: _GrantedMicrophoneAccess(),
          screenAwake: _NoopScreenAwake(),
          orientationManager: OrientationManager(
            setOrientations: (orientations) async =>
                recreatedCalls.add(orientations),
          ),
          isModelReady: () async => true,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(recreatedCalls, [
        const [DeviceOrientation.portraitUp],
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();
    },
  );
}

class _GrantedMicrophoneAccess implements MicrophoneAccess {
  @override
  Future<bool> openSettings() async => true;

  @override
  Future<MicAccessState> request() async => MicAccessState.granted;

  @override
  Future<MicAccessState> status() async => MicAccessState.granted;
}

class _NoopScreenAwake implements ScreenAwake {
  @override
  Future<void> disable() async {}

  @override
  Future<void> enable() async {}
}

class _MemorySettingsStore implements SettingsStore {
  CaptionSettings settings = CaptionSettings();

  @override
  Future<CaptionSettings> load() async => settings;

  @override
  Future<void> save(CaptionSettings next) async => settings = next;
}

class _FakeSpeechEngine implements SpeechEngine {
  var stopCalls = 0;
  var disposed = false;
  var _nextSessionId = 0;
  int? _activeSessionId;

  @override
  Stream<SpeechEvent> get events => const Stream<SpeechEvent>.empty();

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<int> start(String languageCode) async =>
      _activeSessionId = ++_nextSessionId;

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

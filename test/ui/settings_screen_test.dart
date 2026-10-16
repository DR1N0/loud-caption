import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/captions/caption_controller.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/settings_screen.dart';

void main() {
  testWidgets('renders its placeholder without crashing', (tester) async {
    final controller = await _controller();
    addTearDown(() => _dispose(controller));

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(controller: controller)),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('暂无可配置项'), findsOneWidget);
  });
}

Future<CaptionController> _controller() async {
  final controller = CaptionController(
    engine: _FakeSpeechEngine(),
    settingsStore: _MemorySettingsStore(CaptionSettings()),
    retryDelay: (_) async {},
  );
  await controller.initialize();
  return controller;
}

Future<void> _dispose(CaptionController controller) async {
  await controller.stop();
  controller.dispose();
}

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore(this.settings);

  CaptionSettings settings;

  @override
  Future<CaptionSettings> load() async => settings;

  @override
  Future<void> save(CaptionSettings next) async => settings = next;
}

class _FakeSpeechEngine implements SpeechEngine {
  final StreamController<SpeechEvent> _events = StreamController.broadcast();
  int? _activeSessionId;
  int _nextId = 0;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<int> start(String languageCode) async => _activeSessionId = ++_nextId;

  @override
  Future<bool> isSessionActive(int sessionId) async =>
      _activeSessionId == sessionId;

  @override
  Future<void> stop() async => _activeSessionId = null;

  @override
  List<SpeechEngineConfigOption> get configOptions => const [];
  @override
  Map<String, String> get currentConfig => const {};
  @override
  Future<void> applyConfig(Map<String, String> values) async {}
}

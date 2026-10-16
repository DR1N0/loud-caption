import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/captions/caption_controller.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/settings_screen.dart';

void main() {
  testWidgets('shows the translate-all target and the four routing rows', (
    tester,
  ) async {
    final controller = CaptionController(
      engine: _FakeSpeechEngine(),
      settingsStore: _MemorySettingsStore(),
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('设置'), findsOneWidget);
    expect(find.bySemanticsLabel('翻译模式目标语言'), findsOneWidget);
    // '英文' is the currently selected translate-all target, so it renders
    // twice (the closed dropdown's visible text, plus an offstage duplicate
    // Flutter keeps for sizing) — everything else renders once.
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('英文'), findsNWidgets(2));
    expect(find.text('日文'), findsOneWidget);
    expect(find.text('韩文'), findsOneWidget);
  });

  testWidgets('changing the translate-all target persists through the controller', (
    tester,
  ) async {
    final store = _MemorySettingsStore();
    final controller = CaptionController(
      engine: _FakeSpeechEngine(),
      settingsStore: store,
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(controller: controller)),
    );
    await tester.pump();

    // Opening via the dropdown's own displayed text (rather than the
    // Semantics wrapper) is what actually hit-tests the button in widget
    // tests; the Semantics label is still asserted above for accessibility.
    await tester.tap(find.text('英文').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('日文').last);
    await tester.pumpAndSettle();

    expect(controller.settings.translateAllTarget, 'ja');
    expect(store.value.translateAllTarget, 'ja');
  });

  testWidgets('back button pops the route', (tester) async {
    final controller = CaptionController(
      engine: _FakeSpeechEngine(),
      settingsStore: _MemorySettingsStore(),
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(controller: controller),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsNothing);
  });
}

class _MemorySettingsStore implements SettingsStore {
  CaptionSettings value = CaptionSettings();

  @override
  Future<CaptionSettings> load() async => value;

  @override
  Future<void> save(CaptionSettings next) async => value = next;
}

class _FakeSpeechEngine implements SpeechEngine {
  final _events = StreamController<SpeechEvent>.broadcast();

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<int> start(String languageCode) async => 1;

  @override
  Future<bool> isSessionActive(int sessionId) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _events.close();

  @override
  List<SpeechEngineConfigOption> get configOptions => const [];
  @override
  Map<String, String> get currentConfig => const {};
  @override
  Future<void> applyConfig(Map<String, String> values) async {}
}

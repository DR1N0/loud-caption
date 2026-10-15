import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/captions/caption_controller.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/settings_screen.dart';

void main() {
  testWidgets(
    'shows installed built-in languages and persists an unchecked language',
    (tester) async {
      final controller = await _controller(CaptionSettings());
      addTearDown(() => _dispose(controller));

      await _pump(tester, controller);

      expect(find.text('中文'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Español'), findsNothing);

      await tester.tap(find.text('English'));
      await tester.pump();
      await tester.pump();

      expect(controller.settings.enabledLanguages, const ['zh']);
    },
  );

  testWidgets('changing languages while stopped does not start recognition', (
    tester,
  ) async {
    final engine = _FakeSpeechEngine();
    final controller = await _controller(CaptionSettings(), engine: engine);
    addTearDown(() => _dispose(controller));

    await _pump(tester, controller);
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump();

    expect(controller.settings.enabledLanguages, const ['zh']);
    expect(engine.startCalls, 0);
  });

  testWidgets('does not allow the sole enabled language to be unchecked', (
    tester,
  ) async {
    final controller = await _controller(
      CaptionSettings(enabledLanguages: const ['zh']),
    );
    addTearDown(() => _dispose(controller));

    await _pump(tester, controller);

    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '中文'),
    );
    expect(checkbox.value, isTrue);
    expect(checkbox.onChanged, isNull);
    expect(controller.settings.enabledLanguages, const ['zh']);
  });

  testWidgets('keeps the selection and reports a failed language change', (
    tester,
  ) async {
    final store = _MemorySettingsStore(CaptionSettings())..failSaves = true;
    final controller = await _controller(CaptionSettings(), store: store);
    addTearDown(() => _dispose(controller));

    await _pump(tester, controller);
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump();

    expect(controller.settings.enabledLanguages, const ['zh', 'en']);
    expect(find.text('切换失败'), findsOneWidget);
  });

  testWidgets(
    'a failed language action reports failure and unlocks the tiles',
    (tester) async {
      final controller = await _controller(CaptionSettings());
      addTearDown(() => _dispose(controller));
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            controller: controller,
            onLanguageEnabled: (code, enabled) async {
              attempts++;
              if (attempts == 1) throw StateError('test model stop failure');
              await controller.setLanguageEnabled(code, enabled);
            },
          ),
        ),
      );

      await tester.tap(find.text('English'));
      await tester.pump();
      expect(find.text('切换失败'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'English'),
            )
            .onChanged,
        isNotNull,
      );

      await tester.tap(find.text('English'));
      await tester.pump();
      expect(attempts, 2);
      expect(controller.settings.enabledLanguages, const ['zh']);
    },
  );

  testWidgets('uses an injected catalog and each enabled language state', (
    tester,
  ) async {
    final controller = await _controller(
      CaptionSettings(
        catalog: const [
          InstalledLanguage('zh', '中文'),
          InstalledLanguage('en', 'English'),
          InstalledLanguage('es', 'Español'),
        ],
        enabledLanguages: const ['zh', 'es'],
      ),
    );
    addTearDown(() => _dispose(controller));

    await _pump(tester, controller);

    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'English'),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Español'),
          )
          .value,
      isTrue,
    );
    expect(find.textContaining('翻译'), findsNothing);
    expect(find.textContaining('下载'), findsNothing);
  });
}

Future<void> _pump(WidgetTester tester, CaptionController controller) =>
    tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          controller: controller,
          onLanguageEnabled: controller.setLanguageEnabled,
        ),
      ),
    );

Future<CaptionController> _controller(
  CaptionSettings settings, {
  SettingsStore? store,
  _FakeSpeechEngine? engine,
}) async {
  final controller = CaptionController(
    engine: engine ?? _FakeSpeechEngine(),
    settingsStore: store ?? _MemorySettingsStore(settings),
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
  var failSaves = false;

  @override
  Future<CaptionSettings> load() async => settings;

  @override
  Future<void> save(CaptionSettings next) async {
    if (failSaves) throw StateError('save failed');
    settings = next;
  }
}

class _FakeSpeechEngine implements SpeechEngine {
  final StreamController<SpeechEvent> _events = StreamController.broadcast();
  var startCalls = 0;
  int? _activeSessionId;

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
  Future<void> stop() async => _activeSessionId = null;

  @override
  List<SpeechEngineConfigOption> get configOptions => const [];
  @override
  Map<String, String> get currentConfig => const {};
  @override
  Future<void> applyConfig(Map<String, String> values) async {}
}

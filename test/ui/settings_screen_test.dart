import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/captions/caption_controller.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:loud_caption/speech/speech_engine.dart';
import 'package:loud_caption/ui/settings_screen.dart';

void main() {
  testWidgets('shows the translate-all target and the four routing rows', (
    tester,
  ) async {
    // Tall enough that the ListView's lazy sliver builds every section
    // (recognition-language picker, translate-all picker, all four routing
    // rows) without needing to scroll first.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
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
    expect(find.bySemanticsLabel('字幕模式识别语言\n自动'), findsOneWidget);
    expect(find.bySemanticsLabel('翻译模式目标语言\n英语'), findsOneWidget);
    // Each routing row is a ListTile, which merges its title + trailing
    // dropdown into one multi-line semantics label rather than keeping the
    // dropdown's own label isolated — match the routing-target substring
    // instead of the full merged string.
    expect(find.bySemanticsLabel(RegExp('中文的翻译目标')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('英语的翻译目标')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('日语的翻译目标')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('韩语的翻译目标')), findsOneWidget);
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
    // Plain '英语' (no routing self-mapping suffix) uniquely identifies the
    // translate-all picker's closed display — every routing row defaults
    // to a self-mapped ('…（不翻译）'-suffixed) selection instead.
    await tester.tap(find.text('英语').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('日语').last);
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

  testWidgets(
    '诊断 section shows the crash log and supports copy and clear',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final controller = CaptionController(
        engine: _FakeSpeechEngine(),
        settingsStore: _MemorySettingsStore(),
      );
      await controller.initialize();
      addTearDown(controller.dispose);

      // Plain in-memory fakes, not real file I/O: readCrashLog/clearCrashLog
      // normally do genuine dart:io work, which testWidgets()'s zone doesn't
      // let resolve on its own — matching this project's own established DI
      // pattern for exactly this reason (see ModelDownloadScreen.downloadModel,
      // CaptionScreen.preflightCheck). The real file-backed
      // implementation is covered separately in
      // test/diagnostics/crash_log_test.dart.
      var log = 'a recorded crash';
      var cleared = false;

      // flutter_test registers no default handler for the clipboard
      // platform channel, so an unmocked Clipboard.setData/getData call
      // falls through to the real (nonexistent in tests) platform and
      // never responds — hangs forever rather than throwing.
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                clipboardText = (call.arguments as Map)['text'] as String?;
                return null;
              case 'Clipboard.getData':
                return {'text': clipboardText};
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            controller: controller,
            readCrashLog: () async => log,
            clearCrashLog: () async {
              cleared = true;
              log = '暂无崩溃记录';
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('查看崩溃日志'));
      await tester.pumpAndSettle();
      expect(find.textContaining('a recorded crash'), findsOneWidget);

      await tester.tap(find.text('复制'));
      await tester.pump();
      final copied = await Clipboard.getData(Clipboard.kTextPlain);
      expect(copied?.text, contains('a recorded crash'));

      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
    },
  );
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

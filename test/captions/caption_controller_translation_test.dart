import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/captions/caption_controller.dart';
import 'package:loud_caption/captions/caption_line.dart';
import 'package:loud_caption/speech/speech_engine.dart';

import '../translation/fake_translation_engine.dart';
import 'caption_controller_test.dart'
    show FakeSpeechEngine, MemorySettingsStore;

void main() {
  group('CaptionController translation', () {
    late FakeSpeechEngine engine;
    late FakeTranslationEngine translation;
    late CaptionController captions;

    setUp(() {
      engine = FakeSpeechEngine();
      translation = FakeTranslationEngine()..isLoaded = true;
      captions = CaptionController(
        engine: engine,
        settingsStore: MemorySettingsStore(),
        translationEngine: translation,
      );
    });

    tearDown(() async {
      await captions.stop();
      captions.dispose();
      await engine.dispose();
    });

    Future<void> inCaptionsMode() async {
      await captions.initialize();
      await captions.start();
    }

    Future<void> inTranslateAllMode(String target) async {
      await inCaptionsMode();
      await captions.cycleMode(); // captions -> translateAll
      await captions.setTranslateAllTarget(target);
    }

    test('字幕 mode never triggers a translation', () async {
      await inCaptionsMode();

      engine.emit(
        const SpeechEvent(
          SpeechEventKind.partial,
          '你',
          1,
          detectedLanguage: 'zh',
        ),
      );
      await flushEvents();
      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          '你好',
          1,
          detectedLanguage: 'zh',
        ),
      );
      await flushEvents();

      expect(translation.calls, isEmpty);
      expect(captions.committedLines, [const CaptionLine('你好')]);
    });

    test('a committed line is translated under 翻译 mode', () async {
      await inTranslateAllMode('en');

      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          '你好',
          1,
          detectedLanguage: 'zh',
        ),
      );
      await flushEvents();

      expect(translation.calls, hasLength(1));
      expect(translation.calls.single.text, '你好');
      expect(translation.calls.single.sourceLang, 'zh');
      expect(translation.calls.single.targetLang, 'en');

      translation.calls.single.request
        ..emit('Hel')
        ..emit('lo');
      await flushEvents();
      expect(captions.committedLines.single.translation, 'Hello');

      translation.calls.single.request.complete();
      await flushEvents();
      expect(captions.committedLines.single.translation, 'Hello');
    });

    test('a self-mapped language is never translated', () async {
      await inTranslateAllMode('zh'); // target equals the source below

      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          '你好',
          1,
          detectedLanguage: 'zh',
        ),
      );
      await flushEvents();

      expect(translation.calls, isEmpty);
      expect(captions.committedLines.single.translation, isNull);
    });

    test('an unrecognized language (Cantonese) is never translated', () async {
      await inTranslateAllMode('en');

      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          '你好',
          1,
          detectedLanguage: 'yue',
        ),
      );
      await flushEvents();

      expect(translation.calls, isEmpty);
    });

    test('nothing is translated before the engine finishes loading', () async {
      translation.isLoaded = false;
      await inTranslateAllMode('en');

      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          '你好',
          1,
          detectedLanguage: 'zh',
        ),
      );
      await flushEvents();

      expect(translation.calls, isEmpty);
    });

    test('自定义翻译 mode routes per detected source language', () async {
      await inCaptionsMode();
      await captions.cycleMode(); // -> translateAll
      await captions.cycleMode(); // -> translateCustom
      await captions.setRoutingTarget('zh', 'en');
      await captions.setRoutingTarget('ja', 'ko');

      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          'line1',
          1,
          detectedLanguage: 'zh',
        ),
      );
      await flushEvents();
      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          'line2',
          1,
          detectedLanguage: 'ja',
        ),
      );
      await flushEvents();
      // 'en' keeps its default self-mapping, so it should be skipped.
      engine.emit(
        const SpeechEvent(
          SpeechEventKind.finalText,
          'line3',
          1,
          detectedLanguage: 'en',
        ),
      );
      await flushEvents();

      expect(translation.calls, hasLength(2));
      expect(translation.calls[0].targetLang, 'en');
      expect(translation.calls[1].targetLang, 'ko');
    });

    test(
      'a partial event never triggers a translation — on-device inference '
      'latency can\'t keep up with live speech, confirmed on real hardware',
      () async {
        await inTranslateAllMode('en');

        engine.emit(
          const SpeechEvent(
            SpeechEventKind.partial,
            '你',
            1,
            detectedLanguage: 'zh',
          ),
        );
        await flushEvents();
        engine.emit(
          const SpeechEvent(
            SpeechEventKind.partial,
            '你好',
            1,
            detectedLanguage: 'zh',
          ),
        );
        await flushEvents();

        expect(translation.calls, isEmpty);
      },
    );
  });
}

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

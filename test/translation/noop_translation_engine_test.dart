import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/translation/noop_translation_engine.dart';

void main() {
  test('reports never loaded even after ensureLoaded', () async {
    final engine = NoopTranslationEngine();

    expect(engine.isLoaded, isFalse);
    await engine.ensureLoaded();
    expect(engine.isLoaded, isFalse);
  });

  test('translate passes the source text through unchanged', () async {
    final engine = NoopTranslationEngine();

    final request = engine.translate(
      text: 'hello',
      sourceLang: 'en',
      targetLang: 'zh',
    );

    expect(await request.output.toList(), ['hello']);
  });
}

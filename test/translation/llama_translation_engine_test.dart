import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/translation/llama_translation_engine.dart';

void main() {
  test('builds the Hy-MT2 dense prompt with no system turn', () {
    final prompt = buildHyMt2Prompt('今天天气真好。', 'en');

    expect(
      prompt,
      '<｜hy_begin▁of▁sentence｜><｜hy_User｜>'
      '将以下文本翻译为 英语，注意只需要输出翻译后的结果，不要额外解释：\n\n'
      '今天天气真好。'
      '<｜hy_Assistant｜>',
    );
  });

  test('uses the official Chinese name for each supported target language', () {
    expect(buildHyMt2Prompt('x', 'zh'), contains('翻译为 中文，'));
    expect(buildHyMt2Prompt('x', 'en'), contains('翻译为 英语，'));
    expect(buildHyMt2Prompt('x', 'ja'), contains('翻译为 日语，'));
    expect(buildHyMt2Prompt('x', 'ko'), contains('翻译为 韩语，'));
  });

  test('an unrecognized language code falls back to the raw code', () {
    expect(buildHyMt2Prompt('x', 'fr'), contains('翻译为 fr，'));
  });
}

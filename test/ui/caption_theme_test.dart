import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/ui/caption_theme.dart';

void main() {
  test('light and dark palettes differ', () {
    expect(CaptionColors.light.background, isNot(CaptionColors.dark.background));
    expect(CaptionColors.light.primaryText, isNot(CaptionColors.dark.primaryText));
  });

  test('lerp at t=0 and t=1 returns the matching endpoint colors', () {
    final atStart = CaptionColors.dark.lerp(CaptionColors.light, 0);
    final atEnd = CaptionColors.dark.lerp(CaptionColors.light, 1);

    expect(atStart.background, CaptionColors.dark.background);
    expect(atEnd.background, CaptionColors.light.background);
  });

  test('lerp against a foreign extension type is a no-op', () {
    expect(identical(CaptionColors.dark.lerp(null, 0.5), CaptionColors.dark), isTrue);
  });

  test('copyWith overrides only the given fields', () {
    final copy = CaptionColors.dark.copyWith(background: CaptionColors.light.background);

    expect(copy.background, CaptionColors.light.background);
    expect(copy.primaryText, CaptionColors.dark.primaryText);
  });
}

/// One committed caption line: the original recognized text, and its
/// translation once one has been produced — `null` before a translation
/// finishes, or permanently when translation is disabled or doesn't apply
/// to this line's detected language.
class CaptionLine {
  const CaptionLine(this.original, {this.translation});

  final String original;
  final String? translation;

  CaptionLine withTranslation(String translation) =>
      CaptionLine(original, translation: translation);

  @override
  bool operator ==(Object other) =>
      other is CaptionLine &&
      other.original == original &&
      other.translation == translation;

  @override
  int get hashCode => Object.hash(original, translation);
}

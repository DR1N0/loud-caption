import 'package:flutter/material.dart';

/// The caption screen's day/night palette, looked up via
/// `Theme.of(context).extension<CaptionColors>()!`.
class CaptionColors extends ThemeExtension<CaptionColors> {
  const CaptionColors({
    required this.background,
    required this.primaryText,
    required this.dimText,
    required this.statusText,
    required this.errorText,
  });

  static const dark = CaptionColors(
    background: Color(0xFF101114),
    primaryText: Colors.white,
    dimText: Color(0xFFCACDD3),
    statusText: Color(0xFFE1E3E8),
    errorText: Color(0xFFFFC5C0),
  );

  static const light = CaptionColors(
    background: Color(0xFFF5F5F7),
    primaryText: Color(0xFF1A1B1E),
    dimText: Color(0xFF55585E),
    statusText: Color(0xFF34363B),
    errorText: Color(0xFFB3261E),
  );

  final Color background;
  final Color primaryText;
  final Color dimText;
  final Color statusText;
  final Color errorText;

  @override
  CaptionColors copyWith({
    Color? background,
    Color? primaryText,
    Color? dimText,
    Color? statusText,
    Color? errorText,
  }) => CaptionColors(
    background: background ?? this.background,
    primaryText: primaryText ?? this.primaryText,
    dimText: dimText ?? this.dimText,
    statusText: statusText ?? this.statusText,
    errorText: errorText ?? this.errorText,
  );

  @override
  CaptionColors lerp(ThemeExtension<CaptionColors>? other, double t) {
    if (other is! CaptionColors) return this;
    return CaptionColors(
      background: Color.lerp(background, other.background, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      dimText: Color.lerp(dimText, other.dimText, t)!,
      statusText: Color.lerp(statusText, other.statusText, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
    );
  }
}

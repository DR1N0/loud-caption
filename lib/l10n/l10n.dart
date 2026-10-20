import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_zh.dart';

/// Access point for generated strings.
///
/// Widgets use [of], which follows the ambient [Localizations] and falls back
/// to Chinese when a widget is built outside a localized [MaterialApp] (as in
/// many widget tests). Non-widget code (controllers, download preflight) uses
/// [current], which is refreshed whenever a localized tree is built.
class L10n {
  L10n._();

  static final AppLocalizations _fallback = AppLocalizationsZh();
  static AppLocalizations _current = _fallback;

  static AppLocalizations get current => _current;

  static AppLocalizations of(BuildContext context) {
    final localized = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    if (localized != null) {
      _current = localized;
      return localized;
    }
    // A tree without the generated delegates (most widget tests) is treated
    // as Chinese, and must not inherit a previous test's active language.
    _current = _fallback;
    return _fallback;
  }
}

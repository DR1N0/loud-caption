import 'package:flutter/widgets.dart' show Locale;
import 'package:shared_preferences/shared_preferences.dart';

/// The language used for the app's own interface (not recognition or
/// translation). [system] follows the device locale, falling back to English
/// when the device language is neither Chinese nor English.
enum AppLanguage { system, zh, en }

extension AppLanguageX on AppLanguage {
  String get storageValue => name;

  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.zh => const Locale('zh'),
    AppLanguage.en => const Locale('en'),
  };
}

AppLanguage appLanguageFromStorage(String? value) {
  for (final language in AppLanguage.values) {
    if (language.storageValue == value) return language;
  }
  return AppLanguage.system;
}

/// The four languages SenseVoice recognizes that translation can route from
/// — used for 互译's routing-table rows and for validating a detected
/// source language. Translation *targets* are not limited to this list; see
/// [translationTargetLanguages].
const List<String> translationLanguages = ['zh', 'en', 'ja', 'ko'];

/// Every language Hy-MT2 can translate into (its own README's language
/// table, verbatim), with [translationLanguages] pinned first since those
/// are the most common targets. Used for 翻译 mode's single target and for
/// each 互译 routing row's target — unlike [translationLanguages], this is
/// not limited to languages SenseVoice can recognize as a *source*.
const List<String> translationTargetLanguages = [
  'zh', 'en', 'ja', 'ko',
  'fr', 'pt', 'es', 'tr', 'ru', 'ar', 'th', 'it', 'de', 'vi', 'ms', 'id',
  'tl', 'hi', 'zh-Hant', 'pl', 'cs', 'nl', 'km', 'my', 'fa', 'gu', 'ur',
  'te', 'mr', 'he', 'bn', 'ta', 'uk', 'bo', 'kk', 'mn', 'ug', 'yue',
];

/// Chinese display name for every code in [translationTargetLanguages] plus
/// `'auto'` — matches Hy-MT2's own README table wording exactly (e.g.
/// `英语`/`日语`/`韩语`, not `英文`/`日文`/`韩文`), since this map is also
/// used to build the actual model prompt in
/// `lib/translation/llama_translation_engine.dart`, where matching the
/// model's own convention is more than cosmetic.
const Map<String, String> languageNames = {
  'auto': '自动',
  'zh': '中文',
  'en': '英语',
  'ja': '日语',
  'ko': '韩语',
  'fr': '法语',
  'pt': '葡萄牙语',
  'es': '西班牙语',
  'tr': '土耳其语',
  'ru': '俄语',
  'ar': '阿拉伯语',
  'th': '泰语',
  'it': '意大利语',
  'de': '德语',
  'vi': '越南语',
  'ms': '马来语',
  'id': '印尼语',
  'tl': '菲律宾语',
  'hi': '印地语',
  'zh-Hant': '繁体中文',
  'pl': '波兰语',
  'cs': '捷克语',
  'nl': '荷兰语',
  'km': '高棉语',
  'my': '缅甸语',
  'fa': '波斯语',
  'gu': '古吉拉特语',
  'ur': '乌尔都语',
  'te': '泰卢固语',
  'mr': '马拉地语',
  'he': '希伯来语',
  'bn': '孟加拉语',
  'ta': '泰米尔语',
  'uk': '乌克兰语',
  'bo': '藏语',
  'kk': '哈萨克语',
  'mn': '蒙古语',
  'ug': '维吾尔语',
  'yue': '粤语',
};

/// How committed caption lines are displayed.
enum CaptionMode {
  /// No translation; today's behavior.
  captions,

  /// Every line is translated into one fixed [CaptionSettings.translateAllTarget].
  translateAll,

  /// Each source language is translated per its own routing-table entry.
  translateCustom;

  CaptionMode get next => switch (this) {
    CaptionMode.captions => CaptionMode.translateAll,
    CaptionMode.translateAll => CaptionMode.translateCustom,
    CaptionMode.translateCustom => CaptionMode.captions,
  };
}

/// The app's display theme.
enum AppThemeMode {
  dark,
  light;

  AppThemeMode get other =>
      this == AppThemeMode.dark ? AppThemeMode.light : AppThemeMode.dark;
}

/// The user-configurable caption preferences.
class CaptionSettings {
  factory CaptionSettings({
    double fontSize = 48.0,
    bool landscape = false,
    CaptionMode captionMode = CaptionMode.captions,
    String translateAllTarget = 'en',
    Map<String, String> routing = const {},
    AppThemeMode themeMode = AppThemeMode.dark,
    AppLanguage appLanguage = AppLanguage.system,
  }) => CaptionSettings._(
    _nearestFontSize(fontSize),
    landscape,
    captionMode,
    _validatedFromList(translateAllTarget, translationTargetLanguages, fallback: 'en'),
    _validatedRouting(routing),
    themeMode,
    appLanguage,
  );

  const CaptionSettings._(
    this._fontSize,
    this._landscape,
    this._captionMode,
    this._translateAllTarget,
    this._routing,
    this._themeMode,
    this._appLanguage,
  );

  static const List<double> fontSizePresets = [16, 20, 24, 32, 48, 64, 80];

  final double _fontSize;
  final bool _landscape;
  final CaptionMode _captionMode;
  final String _translateAllTarget;
  final Map<String, String> _routing;
  final AppThemeMode _themeMode;
  final AppLanguage _appLanguage;

  double get fontSize => _fontSize;
  bool get landscape => _landscape;
  CaptionMode get captionMode => _captionMode;
  String get translateAllTarget => _translateAllTarget;
  AppThemeMode get themeMode => _themeMode;
  AppLanguage get appLanguage => _appLanguage;

  /// The configured translation target for [sourceLanguage], or
  /// [sourceLanguage] itself (no translation) if it isn't one of
  /// [translationLanguages] or has no routing entry.
  String routingTargetFor(String sourceLanguage) =>
      _routing[sourceLanguage] ?? sourceLanguage;

  CaptionSettings withFontSize(double size) => _copy(fontSize: size);

  CaptionSettings withLandscape(bool value) => _copy(landscape: value);

  CaptionSettings withCaptionMode(CaptionMode mode) =>
      _copy(captionMode: mode);

  CaptionSettings withTranslateAllTarget(String language) =>
      _copy(translateAllTarget: language);

  CaptionSettings withRoutingTarget(String sourceLanguage, String target) =>
      _copy(routing: {..._routing, sourceLanguage: target});

  CaptionSettings withThemeMode(AppThemeMode mode) => _copy(themeMode: mode);

  CaptionSettings withAppLanguage(AppLanguage language) =>
      _copy(appLanguage: language);

  CaptionSettings _copy({
    double? fontSize,
    bool? landscape,
    CaptionMode? captionMode,
    String? translateAllTarget,
    Map<String, String>? routing,
    AppThemeMode? themeMode,
    AppLanguage? appLanguage,
  }) => CaptionSettings(
    fontSize: fontSize ?? this.fontSize,
    landscape: landscape ?? this.landscape,
    captionMode: captionMode ?? this.captionMode,
    translateAllTarget: translateAllTarget ?? this.translateAllTarget,
    routing: routing ?? _routing,
    themeMode: themeMode ?? this.themeMode,
    appLanguage: appLanguage ?? this.appLanguage,
  );

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.fontSize == fontSize &&
      other.landscape == landscape &&
      other.captionMode == captionMode &&
      other.translateAllTarget == translateAllTarget &&
      other.themeMode == themeMode &&
      other.appLanguage == appLanguage &&
      translationLanguages.every(
        (language) =>
            other.routingTargetFor(language) == routingTargetFor(language),
      );

  @override
  int get hashCode => Object.hash(
    fontSize,
    landscape,
    captionMode,
    translateAllTarget,
    themeMode,
    appLanguage,
    Object.hashAll([
      for (final language in translationLanguages) routingTargetFor(language),
    ]),
  );
}

double _nearestFontSize(double size) {
  var closest = CaptionSettings.fontSizePresets.first;
  for (final preset in CaptionSettings.fontSizePresets.skip(1)) {
    if ((preset - size).abs() < (closest - size).abs()) {
      closest = preset;
    }
  }
  return closest;
}

String _validatedFromList(
  String value,
  List<String> allowedValues, {
  required String fallback,
}) => allowedValues.contains(value) ? value : fallback;

/// Fills in any of [translationLanguages] missing from [routing] with a
/// self-mapping (translate to itself = don't translate), and drops unknown
/// source languages or invalid targets (targets may be anything in
/// [translationTargetLanguages], not just [translationLanguages]).
Map<String, String> _validatedRouting(Map<String, String> routing) => {
  for (final language in translationLanguages)
    language: _validatedFromList(
      routing[language] ?? language,
      translationTargetLanguages,
      fallback: language,
    ),
};

abstract interface class SettingsStore {
  Future<CaptionSettings> load();

  Future<void> save(CaptionSettings settings);
}

/// Minimal preference API used by the settings store and its focused tests.
abstract interface class SettingsPreferences {
  bool containsKey(String key);
  String? getString(String key);
  List<String>? getStringList(String key);
  double? getDouble(String key);
  bool? getBool(String key);
  Future<bool> setString(String key, String value);
  Future<bool> setStringList(String key, List<String> value);
  Future<bool> setDouble(String key, double value);
  Future<bool> setBool(String key, bool value);
  Future<bool> remove(String key);
}

/// Reports the original save failure and an optional rollback failure.
class SettingsPersistenceException implements Exception {
  SettingsPersistenceException(this.writeError, {this.rollbackError});

  final Object writeError;
  final Object? rollbackError;

  @override
  String toString() => rollbackError == null
      ? 'SettingsPersistenceException: $writeError'
      : 'SettingsPersistenceException: $writeError; rollback failed: '
            '$rollbackError';
}

/// Persists caption preferences using the platform shared-preferences store.
class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore({SettingsPreferences? preferences})
    : _injectedPreferences = preferences;

  static const fontSizeKey = 'caption.fontSize';
  static const landscapeKey = 'caption.landscape';
  static const captionModeKey = 'caption.mode';
  static const translateAllTargetKey = 'caption.translateAllTarget';
  static const themeModeKey = 'caption.themeMode';
  static const appLanguageKey = 'caption.appLanguage';

  static String routingKeyFor(String language) => 'caption.routing.$language';

  final SettingsPreferences? _injectedPreferences;

  @override
  Future<CaptionSettings> load() async {
    final preferences = await _preferences();
    return CaptionSettings(
      fontSize: preferences.getDouble(fontSizeKey) ?? 48,
      landscape: preferences.getBool(landscapeKey) ?? false,
      captionMode: _readCaptionMode(preferences),
      translateAllTarget: preferences.getString(translateAllTargetKey) ?? 'en',
      routing: {
        for (final language in translationLanguages)
          language: preferences.getString(routingKeyFor(language)) ?? language,
      },
      themeMode: _readThemeMode(preferences),
      appLanguage: appLanguageFromStorage(
        preferences.getString(appLanguageKey),
      ),
    );
  }

  CaptionMode _readCaptionMode(SettingsPreferences preferences) {
    final stored = preferences.getString(captionModeKey);
    for (final mode in CaptionMode.values) {
      if (mode.name == stored) return mode;
    }
    return CaptionMode.captions;
  }

  AppThemeMode _readThemeMode(SettingsPreferences preferences) {
    final stored = preferences.getString(themeModeKey);
    for (final mode in AppThemeMode.values) {
      if (mode.name == stored) return mode;
    }
    return AppThemeMode.dark;
  }

  @override
  Future<void> save(CaptionSettings settings) async {
    final preferences = await _preferences();
    final snapshot = _SettingsSnapshot.capture(preferences);
    try {
      await _write(
        preferences.setDouble(fontSizeKey, settings.fontSize),
        fontSizeKey,
      );
      await _write(
        preferences.setBool(landscapeKey, settings.landscape),
        landscapeKey,
      );
      await _write(
        preferences.setString(captionModeKey, settings.captionMode.name),
        captionModeKey,
      );
      await _write(
        preferences.setString(
          translateAllTargetKey,
          settings.translateAllTarget,
        ),
        translateAllTargetKey,
      );
      for (final language in translationLanguages) {
        await _write(
          preferences.setString(
            routingKeyFor(language),
            settings.routingTargetFor(language),
          ),
          routingKeyFor(language),
        );
      }
      await _write(
        preferences.setString(themeModeKey, settings.themeMode.name),
        themeModeKey,
      );
      await _write(
        preferences.setString(
          appLanguageKey,
          settings.appLanguage.storageValue,
        ),
        appLanguageKey,
      );
    } catch (error) {
      final rollbackError = await snapshot.restore(preferences);
      throw SettingsPersistenceException(error, rollbackError: rollbackError);
    }
  }

  Future<SettingsPreferences> _preferences() async {
    if (_injectedPreferences != null) return _injectedPreferences;
    return _SharedPreferencesAdapter(await SharedPreferences.getInstance());
  }

  Future<void> _write(Future<bool> write, String key) async {
    if (!await write) {
      throw StateError('Could not persist $key.');
    }
  }
}

class _SharedPreferencesAdapter implements SettingsPreferences {
  _SharedPreferencesAdapter(this._preferences);

  final SharedPreferences _preferences;

  @override
  bool containsKey(String key) => _preferences.containsKey(key);
  @override
  String? getString(String key) => _preferences.getString(key);
  @override
  List<String>? getStringList(String key) => _preferences.getStringList(key);
  @override
  double? getDouble(String key) => _preferences.getDouble(key);
  @override
  bool? getBool(String key) => _preferences.getBool(key);
  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _preferences.setStringList(key, value);
  @override
  Future<bool> setDouble(String key, double value) =>
      _preferences.setDouble(key, value);
  @override
  Future<bool> setBool(String key, bool value) =>
      _preferences.setBool(key, value);
  @override
  Future<bool> remove(String key) => _preferences.remove(key);
}

class _SettingsSnapshot {
  _SettingsSnapshot({
    required this.fontSize,
    required this.landscape,
    required this.captionMode,
    required this.translateAllTarget,
    required this.routing,
    required this.themeMode,
    required this.appLanguage,
  });

  factory _SettingsSnapshot.capture(SettingsPreferences preferences) =>
      _SettingsSnapshot(
        fontSize: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.fontSizeKey,
          () =>
              preferences.getDouble(SharedPreferencesSettingsStore.fontSizeKey),
        ),
        landscape: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.landscapeKey,
          () =>
              preferences.getBool(SharedPreferencesSettingsStore.landscapeKey),
        ),
        captionMode: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.captionModeKey,
          () => preferences.getString(
            SharedPreferencesSettingsStore.captionModeKey,
          ),
        ),
        translateAllTarget: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.translateAllTargetKey,
          () => preferences.getString(
            SharedPreferencesSettingsStore.translateAllTargetKey,
          ),
        ),
        routing: {
          for (final language in translationLanguages)
            language: _StoredValue.capture(
              preferences,
              SharedPreferencesSettingsStore.routingKeyFor(language),
              () => preferences.getString(
                SharedPreferencesSettingsStore.routingKeyFor(language),
              ),
            ),
        },
        themeMode: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.themeModeKey,
          () => preferences.getString(
            SharedPreferencesSettingsStore.themeModeKey,
          ),
        ),
        appLanguage: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.appLanguageKey,
          () => preferences.getString(
            SharedPreferencesSettingsStore.appLanguageKey,
          ),
        ),
      );

  final _StoredValue<double> fontSize;
  final _StoredValue<bool> landscape;
  final _StoredValue<String> captionMode;
  final _StoredValue<String> translateAllTarget;
  final Map<String, _StoredValue<String>> routing;
  final _StoredValue<String> themeMode;
  final _StoredValue<String> appLanguage;

  Future<Object?> restore(SettingsPreferences preferences) async {
    Object? firstFailure;
    Future<void> attempt(Future<void> Function() restore) async {
      try {
        await restore();
      } catch (error) {
        firstFailure ??= error;
      }
    }

    await attempt(
      () => fontSize.restore(
        preferences,
        SharedPreferencesSettingsStore.fontSizeKey,
        (value) => preferences.setDouble(
          SharedPreferencesSettingsStore.fontSizeKey,
          value,
        ),
      ),
    );
    await attempt(
      () => landscape.restore(
        preferences,
        SharedPreferencesSettingsStore.landscapeKey,
        (value) => preferences.setBool(
          SharedPreferencesSettingsStore.landscapeKey,
          value,
        ),
      ),
    );
    await attempt(
      () => captionMode.restore(
        preferences,
        SharedPreferencesSettingsStore.captionModeKey,
        (value) => preferences.setString(
          SharedPreferencesSettingsStore.captionModeKey,
          value,
        ),
      ),
    );
    await attempt(
      () => translateAllTarget.restore(
        preferences,
        SharedPreferencesSettingsStore.translateAllTargetKey,
        (value) => preferences.setString(
          SharedPreferencesSettingsStore.translateAllTargetKey,
          value,
        ),
      ),
    );
    for (final language in translationLanguages) {
      await attempt(
        () => routing[language]!.restore(
          preferences,
          SharedPreferencesSettingsStore.routingKeyFor(language),
          (value) => preferences.setString(
            SharedPreferencesSettingsStore.routingKeyFor(language),
            value,
          ),
        ),
      );
    }
    await attempt(
      () => themeMode.restore(
        preferences,
        SharedPreferencesSettingsStore.themeModeKey,
        (value) => preferences.setString(
          SharedPreferencesSettingsStore.themeModeKey,
          value,
        ),
      ),
    );
    await attempt(
      () => appLanguage.restore(
        preferences,
        SharedPreferencesSettingsStore.appLanguageKey,
        (value) => preferences.setString(
          SharedPreferencesSettingsStore.appLanguageKey,
          value,
        ),
      ),
    );
    return firstFailure;
  }
}

class _StoredValue<T> {
  _StoredValue(this.present, this.value);

  factory _StoredValue.capture(
    SettingsPreferences preferences,
    String key,
    T? Function() read,
  ) {
    final present = preferences.containsKey(key);
    return _StoredValue(present, present ? read() : null);
  }

  final bool present;
  final T? value;

  Future<void> restore(
    SettingsPreferences preferences,
    String key,
    Future<bool> Function(T value) write,
  ) async {
    final completed = present
        ? await write(value as T)
        : await preferences.remove(key);
    if (!completed) {
      throw StateError('Could not restore $key.');
    }
  }
}

import 'package:shared_preferences/shared_preferences.dart';

/// The four languages SenseVoice recognizes that translation can target.
const List<String> translationLanguages = ['zh', 'en', 'ja', 'ko'];

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
  }) => CaptionSettings._(
    _nearestFontSize(fontSize),
    landscape,
    captionMode,
    _validatedLanguage(translateAllTarget, fallback: 'en'),
    _validatedRouting(routing),
    themeMode,
  );

  const CaptionSettings._(
    this._fontSize,
    this._landscape,
    this._captionMode,
    this._translateAllTarget,
    this._routing,
    this._themeMode,
  );

  static const List<double> fontSizePresets = [16, 20, 24, 32, 48, 64, 80];

  final double _fontSize;
  final bool _landscape;
  final CaptionMode _captionMode;
  final String _translateAllTarget;
  final Map<String, String> _routing;
  final AppThemeMode _themeMode;

  double get fontSize => _fontSize;
  bool get landscape => _landscape;
  CaptionMode get captionMode => _captionMode;
  String get translateAllTarget => _translateAllTarget;
  AppThemeMode get themeMode => _themeMode;

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

  CaptionSettings _copy({
    double? fontSize,
    bool? landscape,
    CaptionMode? captionMode,
    String? translateAllTarget,
    Map<String, String>? routing,
    AppThemeMode? themeMode,
  }) => CaptionSettings(
    fontSize: fontSize ?? this.fontSize,
    landscape: landscape ?? this.landscape,
    captionMode: captionMode ?? this.captionMode,
    translateAllTarget: translateAllTarget ?? this.translateAllTarget,
    routing: routing ?? _routing,
    themeMode: themeMode ?? this.themeMode,
  );

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.fontSize == fontSize &&
      other.landscape == landscape &&
      other.captionMode == captionMode &&
      other.translateAllTarget == translateAllTarget &&
      other.themeMode == themeMode &&
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

String _validatedLanguage(String language, {required String fallback}) =>
    translationLanguages.contains(language) ? language : fallback;

/// Fills in any of [translationLanguages] missing from [routing] with a
/// self-mapping (translate to itself = don't translate), and drops unknown
/// languages or targets.
Map<String, String> _validatedRouting(Map<String, String> routing) => {
  for (final language in translationLanguages)
    language: _validatedLanguage(
      routing[language] ?? language,
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
      );

  final _StoredValue<double> fontSize;
  final _StoredValue<bool> landscape;
  final _StoredValue<String> captionMode;
  final _StoredValue<String> translateAllTarget;
  final Map<String, _StoredValue<String>> routing;
  final _StoredValue<String> themeMode;

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

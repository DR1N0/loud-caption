import 'package:shared_preferences/shared_preferences.dart';

const List<InstalledLanguage> _defaultCatalog = [
  InstalledLanguage('zh', '中文'),
  InstalledLanguage('en', 'English'),
];

/// A language pack that is available on this device.
class InstalledLanguage {
  const InstalledLanguage(this.code, this.displayName);

  final String code;
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is InstalledLanguage &&
      other.code == code &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(code, displayName);
}

/// The user-configurable caption preferences.
class CaptionSettings {
  factory CaptionSettings({
    String languageCode = 'zh',
    List<String> enabledLanguages = const ['zh', 'en'],
    double fontSize = 48.0,
    bool landscape = false,
    List<InstalledLanguage> catalog = _defaultCatalog,
  }) {
    final copiedCatalog = _validatedCatalog(catalog);
    final copiedEnabled = _validatedEnabledLanguages(
      enabledLanguages,
      copiedCatalog,
    );
    if (!copiedEnabled.contains(languageCode)) {
      throw ArgumentError.value(
        languageCode,
        'languageCode',
        'Language must be enabled.',
      );
    }
    return CaptionSettings._(
      languageCode,
      copiedEnabled,
      _nearestFontSize(fontSize),
      landscape,
      copiedCatalog,
    );
  }

  const CaptionSettings._(
    this._languageCode,
    this._enabledLanguages,
    this._fontSize,
    this._landscape,
    this._catalog,
  );

  static const List<InstalledLanguage> defaultCatalog = _defaultCatalog;
  static const List<double> fontSizePresets = [32, 48, 64, 80];

  final String _languageCode;
  final List<String> _enabledLanguages;
  final double _fontSize;
  final bool _landscape;
  final List<InstalledLanguage> _catalog;

  String get languageCode => _languageCode;
  List<String> get enabledLanguages => _enabledLanguages;
  double get fontSize => _fontSize;
  bool get landscape => _landscape;
  List<InstalledLanguage> get catalog => _catalog;

  CaptionSettings withLanguageEnabled(String code, bool enabled) {
    _requireInstalled(code);

    if (!enabled &&
        _enabledLanguages.length == 1 &&
        _enabledLanguages.single == code) {
      return this;
    }

    final changed = <String>{..._enabledLanguages};
    if (enabled) {
      changed.add(code);
    } else {
      changed.remove(code);
    }
    final ordered = _catalog
        .where((language) => changed.contains(language.code))
        .map((language) => language.code)
        .toList();

    return _copy(
      languageCode: ordered.contains(languageCode)
          ? languageCode
          : ordered.first,
      enabledLanguages: ordered,
    );
  }

  CaptionSettings withLanguage(String code) {
    if (!_enabledLanguages.contains(code)) {
      throw ArgumentError.value(code, 'code', 'Language must be enabled.');
    }
    return _copy(languageCode: code);
  }

  CaptionSettings withFontSize(double size) => _copy(fontSize: size);

  CaptionSettings withLandscape(bool value) => _copy(landscape: value);

  CaptionSettings _copy({
    String? languageCode,
    List<String>? enabledLanguages,
    double? fontSize,
    bool? landscape,
  }) => CaptionSettings(
    languageCode: languageCode ?? this.languageCode,
    enabledLanguages: enabledLanguages ?? _enabledLanguages,
    fontSize: fontSize ?? this.fontSize,
    landscape: landscape ?? this.landscape,
    catalog: _catalog,
  );

  void _requireInstalled(String code) {
    if (!_catalog.any((language) => language.code == code)) {
      throw ArgumentError.value(code, 'code', 'Language is not installed.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.languageCode == languageCode &&
      other.fontSize == fontSize &&
      other.landscape == landscape &&
      _sameItems(other.enabledLanguages, enabledLanguages) &&
      _sameItems(other.catalog, catalog);

  @override
  int get hashCode => Object.hash(
    languageCode,
    fontSize,
    landscape,
    Object.hashAll(enabledLanguages),
    Object.hashAll(catalog),
  );
}

List<InstalledLanguage> _validatedCatalog(List<InstalledLanguage> catalog) {
  if (catalog.isEmpty) {
    throw ArgumentError.value(catalog, 'catalog', 'Catalog cannot be empty.');
  }
  final codes = <String>{};
  for (final language in catalog) {
    if (language.code.isEmpty || !codes.add(language.code)) {
      throw ArgumentError.value(
        catalog,
        'catalog',
        'Catalog codes must be nonempty and unique.',
      );
    }
  }
  return List<InstalledLanguage>.unmodifiable(catalog);
}

List<String> _validatedEnabledLanguages(
  List<String> enabledLanguages,
  List<InstalledLanguage> catalog,
) {
  if (enabledLanguages.isEmpty) {
    throw ArgumentError.value(
      enabledLanguages,
      'enabledLanguages',
      'At least one language must be enabled.',
    );
  }
  final enabled = enabledLanguages.toSet();
  if (enabled.length != enabledLanguages.length) {
    throw ArgumentError.value(
      enabledLanguages,
      'enabledLanguages',
      'Enabled language codes must be unique.',
    );
  }
  final installed = catalog.map((language) => language.code).toSet();
  if (!enabled.every(installed.contains)) {
    throw ArgumentError.value(
      enabledLanguages,
      'enabledLanguages',
      'Enabled languages must be installed.',
    );
  }
  return List<String>.unmodifiable(
    catalog
        .where((language) => enabled.contains(language.code))
        .map((language) => language.code),
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

bool _sameItems<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

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
  SharedPreferencesSettingsStore({
    List<InstalledLanguage> catalog = CaptionSettings.defaultCatalog,
    SettingsPreferences? preferences,
  }) : _catalog = _validatedCatalog(catalog),
       _injectedPreferences = preferences;

  static const languageKey = 'caption.language';
  static const enabledLanguagesKey = 'caption.enabledLanguages';
  static const fontSizeKey = 'caption.fontSize';
  static const landscapeKey = 'caption.landscape';

  final List<InstalledLanguage> _catalog;
  final SettingsPreferences? _injectedPreferences;

  @override
  Future<CaptionSettings> load() async {
    final preferences = await _preferences();
    final savedEnabled =
        preferences.getStringList(enabledLanguagesKey) ??
        _catalog.map((language) => language.code).toList();
    final enabled = _catalog
        .where((language) => savedEnabled.contains(language.code))
        .map((language) => language.code)
        .toList();
    if (enabled.isEmpty) {
      enabled.addAll(_catalog.map((language) => language.code));
    }

    final savedLanguage = preferences.getString(languageKey);
    return CaptionSettings(
      languageCode: enabled.contains(savedLanguage)
          ? savedLanguage!
          : enabled.first,
      enabledLanguages: enabled,
      fontSize: preferences.getDouble(fontSizeKey) ?? 48,
      landscape: preferences.getBool(landscapeKey) ?? false,
      catalog: _catalog,
    );
  }

  @override
  Future<void> save(CaptionSettings settings) async {
    if (!_sameItems(settings.catalog, _catalog)) {
      throw ArgumentError.value(
        settings,
        'settings',
        'Settings catalog must match the installed catalog.',
      );
    }

    final preferences = await _preferences();
    final snapshot = _SettingsSnapshot.capture(preferences);
    try {
      await _write(
        preferences.setString(languageKey, settings.languageCode),
        languageKey,
      );
      await _write(
        preferences.setStringList(
          enabledLanguagesKey,
          settings.enabledLanguages,
        ),
        enabledLanguagesKey,
      );
      await _write(
        preferences.setDouble(fontSizeKey, settings.fontSize),
        fontSizeKey,
      );
      await _write(
        preferences.setBool(landscapeKey, settings.landscape),
        landscapeKey,
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
    required this.language,
    required this.enabledLanguages,
    required this.fontSize,
    required this.landscape,
  });

  factory _SettingsSnapshot.capture(SettingsPreferences preferences) =>
      _SettingsSnapshot(
        language: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.languageKey,
          () =>
              preferences.getString(SharedPreferencesSettingsStore.languageKey),
        ),
        enabledLanguages: _StoredValue.capture(
          preferences,
          SharedPreferencesSettingsStore.enabledLanguagesKey,
          () => preferences.getStringList(
            SharedPreferencesSettingsStore.enabledLanguagesKey,
          ),
        ),
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
      );

  final _StoredValue<String> language;
  final _StoredValue<List<String>> enabledLanguages;
  final _StoredValue<double> fontSize;
  final _StoredValue<bool> landscape;

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
      () => language.restore(
        preferences,
        SharedPreferencesSettingsStore.languageKey,
        (value) => preferences.setString(
          SharedPreferencesSettingsStore.languageKey,
          value,
        ),
      ),
    );
    await attempt(
      () => enabledLanguages.restore(
        preferences,
        SharedPreferencesSettingsStore.enabledLanguagesKey,
        (value) => preferences.setStringList(
          SharedPreferencesSettingsStore.enabledLanguagesKey,
          value,
        ),
      ),
    );
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

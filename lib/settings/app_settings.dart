import 'package:shared_preferences/shared_preferences.dart';

/// The user-configurable caption preferences.
class CaptionSettings {
  factory CaptionSettings({double fontSize = 48.0, bool landscape = false}) =>
      CaptionSettings._(_nearestFontSize(fontSize), landscape);

  const CaptionSettings._(this._fontSize, this._landscape);

  static const List<double> fontSizePresets = [32, 48, 64, 80];

  final double _fontSize;
  final bool _landscape;

  double get fontSize => _fontSize;
  bool get landscape => _landscape;

  CaptionSettings withFontSize(double size) => _copy(fontSize: size);

  CaptionSettings withLandscape(bool value) => _copy(landscape: value);

  CaptionSettings _copy({double? fontSize, bool? landscape}) =>
      CaptionSettings(
        fontSize: fontSize ?? this.fontSize,
        landscape: landscape ?? this.landscape,
      );

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.fontSize == fontSize &&
      other.landscape == landscape;

  @override
  int get hashCode => Object.hash(fontSize, landscape);
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

  final SettingsPreferences? _injectedPreferences;

  @override
  Future<CaptionSettings> load() async {
    final preferences = await _preferences();
    return CaptionSettings(
      fontSize: preferences.getDouble(fontSizeKey) ?? 48,
      landscape: preferences.getBool(landscapeKey) ?? false,
    );
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
  _SettingsSnapshot({required this.fontSize, required this.landscape});

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
      );

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

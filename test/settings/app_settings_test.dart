import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fresh settings use the phase-one defaults', () {
    final settings = CaptionSettings();

    expect(settings.fontSize, 48.0);
    expect(settings.landscape, isFalse);
  });

  test('font size selects the nearest supported preset', () {
    final settings = CaptionSettings();

    expect(settings.withFontSize(30).fontSize, 32.0);
    expect(settings.withFontSize(58).fontSize, 64.0);
    expect(settings.withFontSize(100).fontSize, 80.0);
    expect(settings.withLandscape(true).landscape, isTrue);
  });

  test('save and reload retain font size and orientation', () async {
    final store = SharedPreferencesSettingsStore();
    final settings = CaptionSettings(fontSize: 64, landscape: true);

    await store.save(settings);
    final reloaded = await SharedPreferencesSettingsStore().load();

    expect(reloaded, settings);
  });

  test('load falls back to defaults when nothing is persisted', () async {
    final settings = await SharedPreferencesSettingsStore().load();

    expect(settings.fontSize, 48.0);
    expect(settings.landscape, isFalse);
  });

  test('a false write restores the prior coherent settings', () async {
    final oldSettings = CaptionSettings(fontSize: 48, landscape: false);
    final preferences = _MemorySettingsPreferences(
      _serialized(oldSettings),
      failOnWrite: 2,
    );
    final store = SharedPreferencesSettingsStore(preferences: preferences);
    final updated = CaptionSettings(fontSize: 80, landscape: true);

    await expectLater(
      store.save(updated),
      throwsA(isA<SettingsPersistenceException>()),
    );

    expect(await store.load(), oldSettings);
  });

  test('a thrown write restores the prior coherent settings', () async {
    final oldSettings = CaptionSettings(fontSize: 48, landscape: false);
    final preferences = _MemorySettingsPreferences(
      _serialized(oldSettings),
      failOnWrite: 2,
      throwOnFailure: true,
    );
    final store = SharedPreferencesSettingsStore(preferences: preferences);
    final updated = CaptionSettings(fontSize: 80, landscape: true);

    await expectLater(
      store.save(updated),
      throwsA(isA<SettingsPersistenceException>()),
    );

    expect(await store.load(), oldSettings);
  });
}

Map<String, Object> _serialized(CaptionSettings settings) => {
  SharedPreferencesSettingsStore.fontSizeKey: settings.fontSize,
  SharedPreferencesSettingsStore.landscapeKey: settings.landscape,
};

class _MemorySettingsPreferences implements SettingsPreferences {
  _MemorySettingsPreferences(
    this.values, {
    this.failOnWrite,
    this.throwOnFailure = false,
  });

  final Map<String, Object> values;
  final int? failOnWrite;
  final bool throwOnFailure;
  int writeAttempts = 0;

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  String? getString(String key) => values[key] as String?;

  @override
  List<String>? getStringList(String key) {
    final value = values[key];
    return value is List<String> ? List<String>.from(value) : null;
  }

  @override
  double? getDouble(String key) => values[key] as double?;

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<bool> remove(String key) => _write(key, null, remove: true);

  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);

  @override
  Future<bool> setDouble(String key, double value) => _write(key, value);

  @override
  Future<bool> setString(String key, String value) => _write(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, List<String>.from(value));

  Future<bool> _write(String key, Object? value, {bool remove = false}) async {
    writeAttempts++;
    if (writeAttempts == failOnWrite) {
      if (throwOnFailure) {
        throw StateError('Injected write failure for $key.');
      }
      return false;
    }
    if (remove) {
      values.remove(key);
    } else {
      values[key] = value!;
    }
    return true;
  }
}

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

  test('font size supports a smaller floor than the original presets', () {
    final settings = CaptionSettings();

    expect(settings.withFontSize(14).fontSize, 16.0);
  });

  test('fresh settings default to captions mode and a self-routing table', () {
    final settings = CaptionSettings();

    expect(settings.captionMode, CaptionMode.captions);
    expect(settings.translateAllTarget, 'en');
    expect(settings.themeMode, AppThemeMode.dark);
    for (final language in translationLanguages) {
      expect(settings.routingTargetFor(language), language);
    }
  });

  test(
    'translation targets are not limited to the four recognizable source '
    'languages — Hy-MT2 translates among many more',
    () {
      final settings = CaptionSettings()
          .withTranslateAllTarget('fr')
          .withRoutingTarget('zh', 'ar');

      expect(settings.translateAllTarget, 'fr');
      expect(settings.routingTargetFor('zh'), 'ar');
    },
  );

  test('mode cycles captions -> translateAll -> translateCustom -> captions', () {
    expect(CaptionMode.captions.next, CaptionMode.translateAll);
    expect(CaptionMode.translateAll.next, CaptionMode.translateCustom);
    expect(CaptionMode.translateCustom.next, CaptionMode.captions);
  });

  test('withRoutingTarget only changes the given source language', () {
    final settings = CaptionSettings().withRoutingTarget('zh', 'en');

    expect(settings.routingTargetFor('zh'), 'en');
    expect(settings.routingTargetFor('en'), 'en');
    expect(settings.routingTargetFor('ja'), 'ja');
    expect(settings.routingTargetFor('ko'), 'ko');
  });

  test('an unrecognized language falls back to self-routing', () {
    final settings = CaptionSettings(routing: const {'zh': 'not-a-language'});

    expect(settings.routingTargetFor('zh'), 'zh');
  });

  test('toggling theme mode flips dark and light', () {
    final settings = CaptionSettings();

    expect(settings.withThemeMode(AppThemeMode.light).themeMode, AppThemeMode.light);
    expect(AppThemeMode.dark.other, AppThemeMode.light);
    expect(AppThemeMode.light.other, AppThemeMode.dark);
  });

  test('save and reload retain every field', () async {
    final store = SharedPreferencesSettingsStore();
    final settings = CaptionSettings(
      fontSize: 64,
      landscape: true,
      captionMode: CaptionMode.translateCustom,
      translateAllTarget: 'ja',
      routing: const {'zh': 'en', 'en': 'zh'},
      themeMode: AppThemeMode.light,
    );

    await store.save(settings);
    final reloaded = await SharedPreferencesSettingsStore().load();

    expect(reloaded, settings);
  });

  test('load falls back to defaults when nothing is persisted', () async {
    final settings = await SharedPreferencesSettingsStore().load();

    expect(settings.fontSize, 48.0);
    expect(settings.landscape, isFalse);
    expect(settings.captionMode, CaptionMode.captions);
    expect(settings.translateAllTarget, 'en');
    expect(settings.themeMode, AppThemeMode.dark);
  });

  test('an unrecognized stored mode falls back to captions', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesSettingsStore.captionModeKey: 'not-a-mode',
    });
    final settings = await SharedPreferencesSettingsStore().load();

    expect(settings.captionMode, CaptionMode.captions);
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

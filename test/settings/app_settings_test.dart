import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fresh settings use the phase-one defaults', () {
    final settings = CaptionSettings();

    expect(settings.languageCode, 'zh');
    expect(settings.enabledLanguages, ['zh', 'en']);
    expect(settings.fontSize, 48.0);
    expect(settings.landscape, isFalse);
    expect(settings.catalog, const [
      InstalledLanguage('zh', '中文'),
      InstalledLanguage('en', 'English'),
    ]);
  });

  test('construction rejects invalid language selection and catalogs', () {
    expect(() => CaptionSettings(enabledLanguages: []), throwsArgumentError);
    expect(
      () => CaptionSettings(enabledLanguages: ['zh', 'zh']),
      throwsArgumentError,
    );
    expect(
      () => CaptionSettings(enabledLanguages: ['ko']),
      throwsArgumentError,
    );
    expect(
      () => CaptionSettings(languageCode: 'en', enabledLanguages: ['zh']),
      throwsArgumentError,
    );
    expect(() => CaptionSettings(catalog: []), throwsArgumentError);
    expect(
      () => CaptionSettings(
        catalog: const [
          InstalledLanguage('zh', '中文'),
          InstalledLanguage('zh', 'Chinese'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('construction copies caller-owned lists into immutable storage', () {
    final enabled = ['zh'];
    final catalog = [
      const InstalledLanguage('zh', '中文'),
      const InstalledLanguage('en', 'English'),
    ];
    final settings = CaptionSettings(
      enabledLanguages: enabled,
      catalog: catalog,
    );
    final originalHashCode = settings.hashCode;

    enabled.add('en');
    catalog.add(const InstalledLanguage('ja', '日本語'));

    expect(settings.enabledLanguages, ['zh']);
    expect(settings.catalog, [
      const InstalledLanguage('zh', '中文'),
      const InstalledLanguage('en', 'English'),
    ]);
    expect(settings.hashCode, originalHashCode);
    expect(() => settings.enabledLanguages.add('en'), throwsUnsupportedError);
    expect(
      () => settings.catalog.add(const InstalledLanguage('ja', '日本語')),
      throwsUnsupportedError,
    );
  });

  test('the last enabled language cannot be disabled', () {
    final settings = CaptionSettings(enabledLanguages: ['zh']);

    expect(settings.withLanguageEnabled('zh', false).enabledLanguages, ['zh']);
  });

  test('disabling the active language selects the first enabled language', () {
    final settings = CaptionSettings(languageCode: 'en');

    final updated = settings.withLanguageEnabled('en', false);

    expect(updated.enabledLanguages, ['zh']);
    expect(updated.languageCode, 'zh');
  });

  test('language changes reject disabled and unknown language codes', () {
    final settings = CaptionSettings(enabledLanguages: ['zh']);

    expect(() => settings.withLanguage('en'), throwsArgumentError);
    expect(() => settings.withLanguageEnabled('ko', true), throwsArgumentError);
  });

  test('language enabling preserves the installed catalog order', () {
    final settings = CaptionSettings(
      languageCode: 'en',
      enabledLanguages: ['en'],
    );

    expect(settings.withLanguageEnabled('zh', true).enabledLanguages, [
      'zh',
      'en',
    ]);
  });

  test('font size selects the nearest supported preset', () {
    final settings = CaptionSettings();

    expect(settings.withFontSize(30).fontSize, 32.0);
    expect(settings.withFontSize(58).fontSize, 64.0);
    expect(settings.withFontSize(100).fontSize, 80.0);
    expect(settings.withLandscape(true).landscape, isTrue);
  });

  test(
    'save and reload retain language, font, orientation, and enabled list',
    () async {
      final store = SharedPreferencesSettingsStore();
      final settings = CaptionSettings(
        languageCode: 'en',
        enabledLanguages: ['zh', 'en'],
        fontSize: 64,
        landscape: true,
      );

      await store.save(settings);
      final reloaded = await SharedPreferencesSettingsStore().load();

      expect(reloaded, settings);
    },
  );

  test(
    'load discards unknown ids and falls back to the first enabled language',
    () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesSettingsStore.enabledLanguagesKey: ['ko', 'en'],
        SharedPreferencesSettingsStore.languageKey: 'ko',
        SharedPreferencesSettingsStore.fontSizeKey: 64.0,
        SharedPreferencesSettingsStore.landscapeKey: true,
      });

      final settings = await SharedPreferencesSettingsStore().load();

      expect(settings.enabledLanguages, ['en']);
      expect(settings.languageCode, 'en');
      expect(settings.fontSize, 64.0);
      expect(settings.landscape, isTrue);
    },
  );

  test(
    'load restores all installed languages when persisted ids are invalid',
    () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesSettingsStore.enabledLanguagesKey: ['ko'],
        SharedPreferencesSettingsStore.languageKey: 'ko',
      });

      final settings = await SharedPreferencesSettingsStore().load();

      expect(settings.enabledLanguages, ['zh', 'en']);
      expect(settings.languageCode, 'zh');
    },
  );

  test(
    'an injected installed-language catalog supports a third UI-test language',
    () async {
      const catalog = [
        InstalledLanguage('zh', '中文'),
        InstalledLanguage('en', 'English'),
        InstalledLanguage('ja', '日本語'),
      ];
      final store = SharedPreferencesSettingsStore(catalog: catalog);
      final settings = CaptionSettings(
        languageCode: 'ja',
        enabledLanguages: ['ja'],
        catalog: catalog,
      );

      await store.save(settings);
      final reloaded = await store.load();

      expect(reloaded.catalog, catalog);
      expect(reloaded.enabledLanguages, ['ja']);
      expect(reloaded.languageCode, 'ja');
    },
  );

  test(
    'save rejects settings built with a different installed catalog',
    () async {
      final preferences = _MemorySettingsPreferences({});
      final store = SharedPreferencesSettingsStore(preferences: preferences);
      const catalog = [
        InstalledLanguage('zh', '中文'),
        InstalledLanguage('en', 'English'),
        InstalledLanguage('ja', '日本語'),
      ];
      final settings = CaptionSettings(
        languageCode: 'ja',
        enabledLanguages: ['ja'],
        catalog: catalog,
      );

      await expectLater(store.save(settings), throwsArgumentError);

      expect(preferences.writeAttempts, 0);
      expect(preferences.values, isEmpty);
    },
  );

  test('a false write restores the prior coherent settings', () async {
    final oldSettings = CaptionSettings(
      languageCode: 'zh',
      enabledLanguages: ['zh'],
      fontSize: 48,
      landscape: false,
    );
    final preferences = _MemorySettingsPreferences(
      _serialized(oldSettings),
      failOnWrite: 3,
    );
    final store = SharedPreferencesSettingsStore(preferences: preferences);
    final updated = CaptionSettings(
      languageCode: 'en',
      enabledLanguages: ['zh', 'en'],
      fontSize: 80,
      landscape: true,
    );

    await expectLater(
      store.save(updated),
      throwsA(isA<SettingsPersistenceException>()),
    );

    expect(await store.load(), oldSettings);
  });

  test('a thrown write restores the prior coherent settings', () async {
    final oldSettings = CaptionSettings(
      languageCode: 'zh',
      enabledLanguages: ['zh'],
      fontSize: 48,
      landscape: false,
    );
    final preferences = _MemorySettingsPreferences(
      _serialized(oldSettings),
      failOnWrite: 2,
      throwOnFailure: true,
    );
    final store = SharedPreferencesSettingsStore(preferences: preferences);
    final updated = CaptionSettings(
      languageCode: 'en',
      enabledLanguages: ['zh', 'en'],
      fontSize: 80,
      landscape: true,
    );

    await expectLater(
      store.save(updated),
      throwsA(isA<SettingsPersistenceException>()),
    );

    expect(await store.load(), oldSettings);
  });
}

Map<String, Object> _serialized(CaptionSettings settings) => {
  SharedPreferencesSettingsStore.languageKey: settings.languageCode,
  SharedPreferencesSettingsStore.enabledLanguagesKey: List<String>.from(
    settings.enabledLanguages,
  ),
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

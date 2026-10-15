import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/sense_voice_model_assets.dart';
// path_provider_platform_interface is a transitive dependency of
// path_provider (already a direct dependency of this app); importing it
// directly here to install a fake platform is the standard path_provider
// testing pattern and doesn't warrant adding it as its own pubspec entry.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fake platform implementation that answers `getApplicationSupportPath`
/// with a test-controlled temp directory, so [prepareSenseVoiceModelAssets]
/// never touches a real device path during tests.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._supportPath);

  final String _supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => _supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPlatform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sense_voice_assets_test_',
    );
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Installs a fake `AssetBundle` by intercepting the `flutter/assets`
  /// platform channel that `rootBundle.load` sends to under the hood.
  void mockAssets(Map<String, List<int>> assets) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          final bytes = assets[key];
          if (bytes == null) return null;
          return ByteData.sublistView(Uint8List.fromList(bytes));
        });
  }

  const senseVoiceModelKey = 'assets/models/sense-voice/model.int8.onnx';
  const senseVoiceTokensKey = 'assets/models/sense-voice/tokens.txt';
  const sileroVadModelKey = 'assets/models/silero-vad/silero_vad.onnx';

  test('copies all three model assets into app-private storage', () async {
    mockAssets({
      senseVoiceModelKey: List.filled(10, 1),
      senseVoiceTokensKey: List.filled(5, 2),
      sileroVadModelKey: List.filled(7, 3),
    });

    final paths = await prepareSenseVoiceModelAssets();

    expect(paths.senseVoiceModel, startsWith(tempDir.path));
    expect(
      await File(paths.senseVoiceModel).readAsBytes(),
      List.filled(10, 1),
    );
    expect(
      await File(paths.senseVoiceTokens).readAsBytes(),
      List.filled(5, 2),
    );
    expect(
      await File(paths.sileroVadModel).readAsBytes(),
      List.filled(7, 3),
    );
  });

  test(
    'skips re-copy when destination length already matches the asset',
    () async {
      mockAssets({
        senseVoiceModelKey: List.filled(10, 1),
        senseVoiceTokensKey: List.filled(5, 2),
        sileroVadModelKey: List.filled(7, 3),
      });

      final first = await prepareSenseVoiceModelAssets();

      // Overwrite the copied file's *content* (keeping its length the same)
      // to prove a second call with a same-length asset does not rewrite it.
      await File(first.senseVoiceModel).writeAsBytes(List.filled(10, 9));

      final second = await prepareSenseVoiceModelAssets();

      expect(second.senseVoiceModel, first.senseVoiceModel);
      expect(
        await File(second.senseVoiceModel).readAsBytes(),
        List.filled(10, 9),
        reason: 'destination content should be untouched when lengths match',
      );
    },
  );

  test(
    're-copies when the bundled asset length changes (model version bump)',
    () async {
      mockAssets({
        senseVoiceModelKey: List.filled(10, 1),
        senseVoiceTokensKey: List.filled(5, 2),
        sileroVadModelKey: List.filled(7, 3),
      });
      await prepareSenseVoiceModelAssets();

      mockAssets({
        senseVoiceModelKey: List.filled(20, 4), // different length
        senseVoiceTokensKey: List.filled(5, 2),
        sileroVadModelKey: List.filled(7, 3),
      });

      final updated = await prepareSenseVoiceModelAssets();

      expect(
        await File(updated.senseVoiceModel).readAsBytes(),
        List.filled(20, 4),
      );
    },
  );
}

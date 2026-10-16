import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/sense_voice_model_assets.dart';
// path_provider_platform_interface is a transitive dependency of
// path_provider (already a direct dependency of this app); importing it
// directly here to install a fake platform is the standard path_provider
// testing pattern and doesn't warrant adding it as its own pubspec entry.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._supportPath);

  final String _supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => _supportPath;
}

void main() {
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
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'senseVoiceModelDestinationPaths resolves fixed paths under app support',
    () async {
      final paths = await senseVoiceModelDestinationPaths();

      expect(
        paths.senseVoiceModel,
        '${tempDir.path}/sense-voice/model.int8.onnx',
      );
      expect(paths.senseVoiceTokens, '${tempDir.path}/sense-voice/tokens.txt');
      expect(
        paths.sileroVadModel,
        '${tempDir.path}/silero-vad/silero_vad.onnx',
      );
    },
  );

  test(
    'prepareSenseVoiceModelAssets returns the paths when all three files exist',
    () async {
      final paths = await senseVoiceModelDestinationPaths();
      for (final path in [
        paths.senseVoiceModel,
        paths.senseVoiceTokens,
        paths.sileroVadModel,
      ]) {
        await File(path).create(recursive: true);
      }

      final resolved = await prepareSenseVoiceModelAssets();

      expect(resolved.senseVoiceModel, paths.senseVoiceModel);
      expect(resolved.senseVoiceTokens, paths.senseVoiceTokens);
      expect(resolved.sileroVadModel, paths.sileroVadModel);
    },
  );

  test(
    'prepareSenseVoiceModelAssets throws StateError when a file is missing',
    () async {
      final paths = await senseVoiceModelDestinationPaths();
      // Only create two of the three — the model download gate is supposed
      // to guarantee all three exist before this is ever called.
      await File(paths.senseVoiceModel).create(recursive: true);
      await File(paths.senseVoiceTokens).create(recursive: true);

      await expectLater(
        prepareSenseVoiceModelAssets,
        throwsA(isA<StateError>()),
      );
    },
  );
}

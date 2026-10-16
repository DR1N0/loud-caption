import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Absolute on-disk paths to the three sherpa-onnx model files sherpa-onnx
/// needs real filesystem paths for (its native FFI layer cannot read a
/// Flutter asset key or a network stream directly).
class SenseVoiceModelPaths {
  const SenseVoiceModelPaths({
    required this.senseVoiceModel,
    required this.senseVoiceTokens,
    required this.sileroVadModel,
  });

  final String senseVoiceModel;
  final String senseVoiceTokens;
  final String sileroVadModel;
}

/// Computes the fixed destination paths the model files live at, without
/// touching the filesystem. Shared by [prepareSenseVoiceModelAssets] (which
/// requires the files already exist there) and
/// `sense_voice_model_download.dart` (which downloads them there).
Future<SenseVoiceModelPaths> senseVoiceModelDestinationPaths() async {
  final destinationDir = await getApplicationSupportDirectory();
  return SenseVoiceModelPaths(
    senseVoiceModel: '${destinationDir.path}/sense-voice/model.int8.onnx',
    senseVoiceTokens: '${destinationDir.path}/sense-voice/tokens.txt',
    sileroVadModel: '${destinationDir.path}/silero-vad/silero_vad.onnx',
  );
}

/// Resolves the on-disk paths to the model files, which must already have
/// been downloaded (see `sense_voice_model_download.dart`'s
/// `isSenseVoiceModelReady`/`downloadSenseVoiceModel`) — `main.dart` gates
/// app startup on that before constructing anything that calls this.
///
/// Throws [StateError] if any expected file is missing, since that
/// indicates a caller skipped the download gate rather than a recoverable
/// runtime condition.
Future<SenseVoiceModelPaths> prepareSenseVoiceModelAssets() async {
  final paths = await senseVoiceModelDestinationPaths();
  for (final path in [
    paths.senseVoiceModel,
    paths.senseVoiceTokens,
    paths.sileroVadModel,
  ]) {
    if (!await File(path).exists()) {
      throw StateError(
        'Model file missing at $path — the model download gate should '
        'have ensured this before the recognition pipeline starts.',
      );
    }
  }
  return paths;
}

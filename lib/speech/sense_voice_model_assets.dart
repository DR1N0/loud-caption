import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Absolute on-disk paths to the three bundled sherpa-onnx model files, once
/// copied out of the Flutter asset bundle into app-private storage.
///
/// sherpa-onnx's native FFI layer needs real filesystem paths — it cannot
/// read a Flutter asset key directly — so these files must live on disk
/// before any isolate constructs a `VoiceActivityDetector` or
/// `OfflineRecognizer` from them.
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

const _senseVoiceModelAsset = 'assets/models/sense-voice/model.int8.onnx';
const _senseVoiceTokensAsset = 'assets/models/sense-voice/tokens.txt';
const _sileroVadModelAsset = 'assets/models/silero-vad/silero_vad.onnx';

/// Copies the bundled SenseVoice + Silero VAD model files into app-private
/// storage and returns their absolute paths.
///
/// Idempotent: a destination file is rewritten only when its byte length
/// doesn't match the bundled asset's length, so repeat app launches don't
/// re-copy ~230 MB of model weights every start. A length mismatch (e.g.
/// after a model-version bump ships a different `model.int8.onnx`) does
/// trigger a re-copy.
Future<SenseVoiceModelPaths> prepareSenseVoiceModelAssets() async {
  final destinationDir = await getApplicationSupportDirectory();

  final senseVoiceModel = await _copyAssetIfNeeded(
    _senseVoiceModelAsset,
    '${destinationDir.path}/sense-voice/model.int8.onnx',
  );
  final senseVoiceTokens = await _copyAssetIfNeeded(
    _senseVoiceTokensAsset,
    '${destinationDir.path}/sense-voice/tokens.txt',
  );
  final sileroVadModel = await _copyAssetIfNeeded(
    _sileroVadModelAsset,
    '${destinationDir.path}/silero-vad/silero_vad.onnx',
  );

  return SenseVoiceModelPaths(
    senseVoiceModel: senseVoiceModel,
    senseVoiceTokens: senseVoiceTokens,
    sileroVadModel: sileroVadModel,
  );
}

/// Copies [assetKey] to [destinationPath] unless a file already there has
/// the same byte length as the bundled asset. Returns [destinationPath].
Future<String> _copyAssetIfNeeded(
  String assetKey,
  String destinationPath,
) async {
  final file = File(destinationPath);
  final assetData = await rootBundle.load(assetKey);

  if (await file.exists() && await file.length() == assetData.lengthInBytes) {
    return destinationPath;
  }

  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    ),
    flush: true,
  );
  return destinationPath;
}

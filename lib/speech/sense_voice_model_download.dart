import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../downloads/model_downloader.dart';
import 'sense_voice_model_assets.dart';

// Pinned sources — identical to the ones `scripts/fetch_models.py` has
// always used for the build-time bundling pipeline this replaces. See
// docs/model-sources.md for the authoritative record.
const _senseVoiceBaseUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/';
const _senseVoiceArchiveName =
    'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2';
const _senseVoiceArchiveSha256 =
    '7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e';
const _sileroVadFileName = 'silero_vad.onnx';
const _sileroVadSha256 =
    '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6';

/// Which step of [downloadSenseVoiceModel] is in progress.
enum ModelDownloadPhase { downloadingAsr, extracting, downloadingVad }

/// Progress for an in-flight [downloadSenseVoiceModel] call.
class ModelDownloadEvent {
  const ModelDownloadEvent({
    required this.phase,
    required this.receivedBytes,
    this.totalBytes,
  });

  final ModelDownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;
}

/// Whether both model files are already present at their fixed destination
/// paths. Safe to trust without re-hashing: the only way a file lands at a
/// destination path is via [downloadAndVerify]'s atomic verify-then-rename,
/// so existence alone implies a prior successful verification.
Future<bool> isSenseVoiceModelReady() async {
  final paths = await senseVoiceModelDestinationPaths();
  for (final path in [
    paths.senseVoiceModel,
    paths.senseVoiceTokens,
    paths.sileroVadModel,
  ]) {
    if (!await File(path).exists()) return false;
  }
  return true;
}

/// Downloads and installs the SenseVoice ASR model + Silero VAD model to
/// their fixed destination paths (see [senseVoiceModelDestinationPaths]).
///
/// Three phases, in order: download the SenseVoice `.tar.bz2` archive to a
/// scratch location and verify it; extract the two files the app actually
/// needs (`model.int8.onnx`, `tokens.txt`) out of it and discard the rest;
/// download + verify Silero VAD directly to its destination (it's already a
/// single file, no extraction needed). Safe to call again after a failure —
/// each step re-checks whether its own output already exists and verifies
/// before re-downloading.
///
/// [senseVoiceArchiveUrl]/[senseVoiceArchiveSha256] and
/// [sileroVadUrl]/[sileroVadSha256] default to the real pinned sources and
/// exist as parameters only so tests can point this at a local fixture
/// server instead — production call sites should never need to pass them.
Stream<ModelDownloadEvent> downloadSenseVoiceModel({
  String senseVoiceArchiveUrl = _senseVoiceBaseUrl + _senseVoiceArchiveName,
  String senseVoiceArchiveSha256 = _senseVoiceArchiveSha256,
  String sileroVadUrl = _senseVoiceBaseUrl + _sileroVadFileName,
  String sileroVadSha256 = _sileroVadSha256,
}) async* {
  final destinationPaths = await senseVoiceModelDestinationPaths();
  final scratchDir = await getTemporaryDirectory();
  final archivePath = '${scratchDir.path}/$_senseVoiceArchiveName';
  final extractDir = '${scratchDir.path}/sense-voice-extract';

  await for (final progress
      in downloadAndVerify(
        DownloadSpec(
          url: senseVoiceArchiveUrl,
          destinationPath: archivePath,
          sha256: senseVoiceArchiveSha256,
        ),
      )) {
    yield ModelDownloadEvent(
      phase: ModelDownloadPhase.downloadingAsr,
      receivedBytes: progress.receivedBytes,
      totalBytes: progress.totalBytes,
    );
  }

  yield const ModelDownloadEvent(
    phase: ModelDownloadPhase.extracting,
    receivedBytes: 0,
  );
  await Isolate.run(
    () => _extractSenseVoiceFiles(
      archivePath: archivePath,
      extractDir: extractDir,
      destinationModelPath: destinationPaths.senseVoiceModel,
      destinationTokensPath: destinationPaths.senseVoiceTokens,
    ),
  );
  await File(archivePath).delete();
  await Directory(extractDir).delete(recursive: true);

  await for (final progress
      in downloadAndVerify(
        DownloadSpec(
          url: sileroVadUrl,
          destinationPath: destinationPaths.sileroVadModel,
          sha256: sileroVadSha256,
        ),
      )) {
    yield ModelDownloadEvent(
      phase: ModelDownloadPhase.downloadingVad,
      receivedBytes: progress.receivedBytes,
      totalBytes: progress.totalBytes,
    );
  }
}

/// Runs on a background isolate (via [Isolate.run] in
/// [downloadSenseVoiceModel]) since tar/bzip2 decoding is synchronous and
/// would otherwise block the UI isolate for the several seconds a ~240MB
/// archive can take to extract.
///
/// Extracts the whole archive to [extractDir] (via `package:archive`'s
/// `extractFileToDisk`, which streams via file-backed `InputFileStream`
/// views rather than loading the archive into memory — safe for a file this
/// size) and then moves just the two files the app needs out to their final
/// destinations, mirroring `scripts/fetch_models.py`'s
/// basename-based matching rather than assuming a specific internal
/// directory layout for the archive.
Future<void> _extractSenseVoiceFiles({
  required String archivePath,
  required String extractDir,
  required String destinationModelPath,
  required String destinationTokensPath,
}) async {
  await extractFileToDisk(archivePath, extractDir);

  final wanted = {
    'model.int8.onnx': destinationModelPath,
    'tokens.txt': destinationTokensPath,
  };
  final found = <String>{};
  await for (final entity
      in Directory(extractDir).list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final basename = entity.uri.pathSegments.last;
    final destinationPath = wanted[basename];
    if (destinationPath == null) continue;
    await File(destinationPath).parent.create(recursive: true);
    await entity.rename(destinationPath);
    found.add(basename);
  }

  final missing = wanted.keys.toSet().difference(found);
  if (missing.isNotEmpty) {
    throw StateError(
      'SenseVoice archive is missing expected file(s): ${missing.join(', ')}',
    );
  }
}

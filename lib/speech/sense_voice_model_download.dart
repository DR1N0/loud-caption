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

/// Free space actually needed to get through [downloadSenseVoiceModel]: the
/// peak moment is just before extraction finishes, when the (not yet
/// deleted) ~164MB archive and the ~240MB of files it's being extracted to
/// coexist on disk — archive + installed size (both pinned exactly in
/// docs/model-sources.md), plus ~10% headroom.
const senseVoiceRequiredFreeBytes = 450000000;

// GitHub Releases is unreliable from mainland China, so each file also has
// two GitHub-release-proxy mirrors as fallbacks — both verified (via a HEAD
// request matching the pinned size above) to serve the exact same bytes as
// the original, not a re-packaged copy, so the single pinned SHA-256 per
// file applies to every mirror. Proxy availability is known to churn (an
// earlier pair, ghfast.top and gh-proxy.com, both went unreachable from a
// real mainland-China network this app was tested on, replaced below with
// gh.monlor.com and gh-proxy.org), hence two independent ones rather than
// just one. Which candidate actually gets tried first is decided at
// download time by `downloadAndVerify`'s concurrent reachability race, not
// by this list's order — see model_downloader.dart.
const _senseVoiceArchiveUrls = [
  '$_senseVoiceBaseUrl$_senseVoiceArchiveName',
  'https://gh.monlor.com/$_senseVoiceBaseUrl$_senseVoiceArchiveName',
  'https://gh-proxy.org/$_senseVoiceBaseUrl$_senseVoiceArchiveName',
];
const _sileroVadUrls = [
  '$_senseVoiceBaseUrl$_sileroVadFileName',
  'https://gh.monlor.com/$_senseVoiceBaseUrl$_sileroVadFileName',
  'https://gh-proxy.org/$_senseVoiceBaseUrl$_sileroVadFileName',
];

/// Which step of [downloadSenseVoiceModel] is in progress.
enum ModelDownloadPhase { downloadingAsr, extracting, downloadingVad }

/// Progress for an in-flight [downloadSenseVoiceModel] call. [source] (see
/// [DownloadProgress.source]) is null during [ModelDownloadPhase.extracting],
/// which isn't a network step.
class ModelDownloadEvent {
  const ModelDownloadEvent({
    required this.phase,
    required this.receivedBytes,
    this.totalBytes,
    this.source,
  });

  final ModelDownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;
  final String? source;
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
/// [senseVoiceArchiveUrls]/[senseVoiceArchiveSha256] and
/// [sileroVadUrls]/[sileroVadSha256] default to the real pinned sources (a
/// primary plus mirrors — see the fallback note above) and exist as
/// parameters only so tests can point this at a local fixture server
/// instead — production call sites should never need to pass them.
Stream<ModelDownloadEvent> downloadSenseVoiceModel({
  List<String> senseVoiceArchiveUrls = _senseVoiceArchiveUrls,
  String senseVoiceArchiveSha256 = _senseVoiceArchiveSha256,
  List<String> sileroVadUrls = _sileroVadUrls,
  String sileroVadSha256 = _sileroVadSha256,
}) async* {
  final destinationPaths = await senseVoiceModelDestinationPaths();
  final scratchDir = await getTemporaryDirectory();
  final archivePath = '${scratchDir.path}/$_senseVoiceArchiveName';
  final extractDir = '${scratchDir.path}/sense-voice-extract';

  await for (final progress
      in downloadAndVerify(
        DownloadSpec(
          urls: senseVoiceArchiveUrls,
          destinationPath: archivePath,
          sha256: senseVoiceArchiveSha256,
        ),
      )) {
    yield ModelDownloadEvent(
      phase: ModelDownloadPhase.downloadingAsr,
      receivedBytes: progress.receivedBytes,
      totalBytes: progress.totalBytes,
      source: progress.source,
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
          urls: sileroVadUrls,
          destinationPath: destinationPaths.sileroVadModel,
          sha256: sileroVadSha256,
        ),
      )) {
    yield ModelDownloadEvent(
      phase: ModelDownloadPhase.downloadingVad,
      receivedBytes: progress.receivedBytes,
      totalBytes: progress.totalBytes,
      source: progress.source,
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

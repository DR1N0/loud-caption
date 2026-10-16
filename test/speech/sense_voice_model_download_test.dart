import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/sense_voice_model_assets.dart';
import 'package:loud_caption/speech/sense_voice_model_download.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({required this.supportPath, required this.tempPath});

  final String supportPath;
  final String tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

/// Builds a small, real `.tar.bz2` archive (via `package:archive`'s own
/// encoders, not a hand-written byte fixture) containing the two files the
/// app looks for, nested inside a top-level directory the way a real
/// sherpa-onnx release archive is — so the test also exercises the
/// basename-matching extraction logic, not just "it's the only file in the
/// archive."
List<int> _buildFixtureArchive({
  required List<int> modelBytes,
  required List<int> tokensBytes,
}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/model.int8.onnx',
        modelBytes.length,
        modelBytes,
      ),
    )
    ..addFile(
      ArchiveFile(
        'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/tokens.txt',
        tokensBytes.length,
        tokensBytes,
      ),
    );
  final tarBytes = TarEncoder().encode(archive);
  return BZip2Encoder().encode(tarBytes);
}

String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory tempDir;
  late Directory supportDir;
  late Directory scratchDir;
  late PathProviderPlatform originalPlatform;
  late HttpServer server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sense_voice_download_test_',
    );
    supportDir = Directory('${tempDir.path}/support')..createSync();
    scratchDir = Directory('${tempDir.path}/scratch')..createSync();
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      supportPath: supportDir.path,
      tempPath: scratchDir.path,
    );
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPlatform;
    await server.close(force: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('isSenseVoiceModelReady', () {
    test('false when no model files exist yet', () async {
      server = await HttpServer.bind('localhost', 0);
      expect(await isSenseVoiceModelReady(), isFalse);
    });

    test('true once all three destination files exist', () async {
      server = await HttpServer.bind('localhost', 0);
      final paths = await senseVoiceModelDestinationPaths();
      for (final path in [
        paths.senseVoiceModel,
        paths.senseVoiceTokens,
        paths.sileroVadModel,
      ]) {
        await File(path).create(recursive: true);
      }

      expect(await isSenseVoiceModelReady(), isTrue);
    });
  });

  group('downloadSenseVoiceModel', () {
    test(
      'downloads the archive, extracts the two wanted files by basename '
      '(ignoring the archive internal directory and any other members), '
      'and downloads Silero VAD, all to the fixed destination paths',
      () async {
        final modelBytes = List<int>.generate(500, (i) => i % 256);
        final tokensBytes = 'fake tokens'.codeUnits;
        final vadBytes = List<int>.generate(50, (i) => (i * 3) % 256);
        final archiveBytes = _buildFixtureArchive(
          modelBytes: modelBytes,
          tokensBytes: tokensBytes,
        );
        final archiveSha256 = sha256OfBytes(archiveBytes);
        final vadSha256 = sha256OfBytes(vadBytes);

        server = await HttpServer.bind('localhost', 0);
        server.listen((request) {
          final bytes = request.uri.path.endsWith('.tar.bz2')
              ? archiveBytes
              : vadBytes;
          request.response.statusCode = HttpStatus.ok;
          request.response.add(bytes);
          request.response.close();
        });
        final base = 'http://localhost:${server.port}/';

        final events = await downloadSenseVoiceModel(
          senseVoiceArchiveUrl: '${base}archive.tar.bz2',
          senseVoiceArchiveSha256: archiveSha256,
          sileroVadUrl: '${base}silero_vad.onnx',
          sileroVadSha256: vadSha256,
        ).toList();

        expect(
          events.map((e) => e.phase).toSet(),
          {
            ModelDownloadPhase.downloadingAsr,
            ModelDownloadPhase.extracting,
            ModelDownloadPhase.downloadingVad,
          },
        );

        final paths = await senseVoiceModelDestinationPaths();
        expect(await File(paths.senseVoiceModel).readAsBytes(), modelBytes);
        expect(
          await File(paths.senseVoiceTokens).readAsBytes(),
          tokensBytes,
        );
        expect(await File(paths.sileroVadModel).readAsBytes(), vadBytes);
        expect(await isSenseVoiceModelReady(), isTrue);

        // Scratch files are cleaned up, not left behind.
        expect(
          await Directory(scratchDir.path).list().toList(),
          isEmpty,
        );
      },
    );

    test(
      'a checksum mismatch on the archive throws without writing any '
      'destination file',
      () async {
        final archiveBytes = _buildFixtureArchive(
          modelBytes: [1, 2, 3],
          tokensBytes: [4, 5],
        );
        server = await HttpServer.bind('localhost', 0);
        server.listen((request) {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(archiveBytes);
          request.response.close();
        });

        await expectLater(
          downloadSenseVoiceModel(
            senseVoiceArchiveUrl:
                'http://localhost:${server.port}/archive.tar.bz2',
            senseVoiceArchiveSha256: '0' * 64,
          ).drain<void>(),
          throwsA(isA<StateError>()),
        );

        expect(await isSenseVoiceModelReady(), isFalse);
      },
    );
  });
}

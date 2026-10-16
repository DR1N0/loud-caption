import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Describes one file to download, verify, and atomically publish.
class DownloadSpec {
  const DownloadSpec({
    required this.url,
    required this.destinationPath,
    required this.sha256,
  });

  final String url;
  final String destinationPath;

  /// Expected SHA-256 digest of the downloaded file, as a lowercase hex
  /// string.
  final String sha256;
}

/// Progress for an in-flight [downloadAndVerify] call. [totalBytes] is null
/// when the server didn't report a `Content-Length`.
class DownloadProgress {
  const DownloadProgress({required this.receivedBytes, this.totalBytes});

  final int receivedBytes;
  final int? totalBytes;
}

/// A minimal [Sink] that just remembers the last [Digest] it was given —
/// everything [sha256.startChunkedConversion] needs, without pulling in
/// `package:convert` for `AccumulatorSink`.
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}

  Digest get digest {
    final digest = _digest;
    if (digest == null) {
      throw StateError('No digest was produced.');
    }
    return digest;
  }
}

/// Streams [path]'s SHA-256 digest (reading in chunks, never loading the
/// whole file into memory) and compares it to [expectedSha256].
Future<bool> verifyExisting(String path, String expectedSha256) async {
  final digestSink = _DigestSink();
  final hashSink = sha256.startChunkedConversion(digestSink);
  await for (final chunk in File(path).openRead()) {
    hashSink.add(chunk);
  }
  hashSink.close();
  return digestSink.digest.toString() == expectedSha256;
}

/// Downloads [spec.url] to a sibling `.part` file while incrementally
/// hashing it, verifies the result against [spec.sha256], and atomically
/// renames it into place at [spec.destinationPath] on success.
///
/// If something goes wrong partway through — a network error, a checksum
/// mismatch — the `.part` file is deleted and [spec.destinationPath] is
/// never touched, so an interrupted or corrupted download can never leave a
/// bad file at the final path; callers can simply retry. If
/// [spec.destinationPath] already exists and verifies, completes
/// immediately without downloading anything.
Stream<DownloadProgress> downloadAndVerify(
  DownloadSpec spec, {
  HttpClient? client,
}) async* {
  final destination = File(spec.destinationPath);
  if (await destination.exists() &&
      await verifyExisting(destination.path, spec.sha256)) {
    final length = await destination.length();
    yield DownloadProgress(receivedBytes: length, totalBytes: length);
    return;
  }

  await destination.parent.create(recursive: true);
  final partFile = File('${spec.destinationPath}.part');
  final sink = partFile.openWrite();
  final digestSink = _DigestSink();
  final hashSink = sha256.startChunkedConversion(digestSink);
  final httpClient = client ?? HttpClient();

  try {
    final request = await httpClient.getUrl(Uri.parse(spec.url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Download failed: HTTP ${response.statusCode} for ${spec.url}',
      );
    }
    final totalBytes = response.contentLength >= 0
        ? response.contentLength
        : null;
    var receivedBytes = 0;

    await for (final chunk in response) {
      sink.add(chunk);
      hashSink.add(chunk);
      receivedBytes += chunk.length;
      yield DownloadProgress(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
      );
    }

    await sink.flush();
    await sink.close();
    hashSink.close();
    final actual = digestSink.digest.toString();
    if (actual != spec.sha256) {
      throw StateError(
        'Checksum mismatch for ${spec.url}: expected ${spec.sha256}, got $actual',
      );
    }
    await partFile.rename(spec.destinationPath);
  } catch (_) {
    await sink.close().catchError((_) {});
    if (await partFile.exists()) await partFile.delete();
    rethrow;
  } finally {
    if (client == null) httpClient.close();
  }
}

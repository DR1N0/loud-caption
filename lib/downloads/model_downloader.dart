import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Describes one file to download, verify, and atomically publish.
class DownloadSpec {
  DownloadSpec({
    required this.urls,
    required this.destinationPath,
    required this.sha256,
  }) : assert(urls.isNotEmpty, 'DownloadSpec needs at least one URL.');

  /// Candidate source URLs for the same byte-identical file, tried in order
  /// until one succeeds — e.g. a primary host plus region-specific mirrors
  /// for places (like mainland China) where the primary is unreliable. The
  /// single pinned [sha256] below is verified against whichever one answers.
  final List<String> urls;

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

/// Downloads a file matching [spec.sha256] to [spec.destinationPath],
/// trying each of [spec.urls] in order until one produces a verified file.
///
/// Streams to a sibling `.part` file while incrementally hashing it. If a
/// candidate URL fails — a network error, a non-200 response, a checksum
/// mismatch — the `.part` file is deleted and the next URL is tried; only
/// once every candidate has failed does this rethrow (the last URL's
/// error). [spec.destinationPath] is never touched until a candidate's
/// download verifies, so an interrupted or corrupted attempt can never
/// leave a bad file at the final path. If [spec.destinationPath] already
/// exists and verifies, completes immediately without downloading anything.
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
  final httpClient = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  try {
    Object? lastError;
    for (final url in spec.urls) {
      try {
        // `await for` (not `yield*`) is required here: a `try`/`catch`
        // wrapped around `yield* someStream` does NOT catch errors from
        // that delegated stream — they bypass the catch and propagate
        // straight to this function's own consumer. `await for` throws
        // synchronously into this generator's control flow instead, which
        // a surrounding `catch` does see, letting a failed URL fall
        // through to the next candidate instead of aborting immediately.
        await for (final progress
            in _downloadOnce(
              url: url,
              partFile: partFile,
              expectedSha256: spec.sha256,
              httpClient: httpClient,
            )) {
          yield progress;
        }
        await partFile.rename(spec.destinationPath);
        return;
      } catch (error) {
        lastError = error;
        if (await partFile.exists()) await partFile.delete();
      }
    }
    throw lastError!;
  } finally {
    if (client == null) httpClient.close();
  }
}

/// One attempt against a single [url]; throws without renaming
/// [partFile] into place on any failure, leaving cleanup to the caller so it
/// can retry against the next candidate URL.
Stream<DownloadProgress> _downloadOnce({
  required String url,
  required File partFile,
  required String expectedSha256,
  required HttpClient httpClient,
}) async* {
  final sink = partFile.openWrite();
  final digestSink = _DigestSink();
  final hashSink = sha256.startChunkedConversion(digestSink);

  try {
    final request = await httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Download failed: HTTP ${response.statusCode} for $url');
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
    if (actual != expectedSha256) {
      throw StateError(
        'Checksum mismatch for $url: expected $expectedSha256, got $actual',
      );
    }
  } catch (_) {
    await sink.close().catchError((_) {});
    rethrow;
  }
}

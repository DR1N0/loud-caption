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
/// Streams to a sibling `.part` file while incrementally hashing it. A
/// leftover `.part` file from an earlier interrupted attempt (app killed,
/// connection dropped) is resumed via an HTTP `Range` request rather than
/// re-downloaded from scratch — see [_downloadOnce]. Only a proven-corrupt
/// download (failed checksum) deletes the `.part` file; any other failure —
/// a network error, a non-200/206 response — leaves it in place so the next
/// attempt (the next candidate URL, or a future call after the app
/// restarts) can resume from it. Only once every candidate has failed does
/// this rethrow (the last URL's error). [spec.destinationPath] is never
/// touched until a candidate's download verifies, so an interrupted or
/// corrupted attempt can never leave a bad file at the final path. If
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
      }
    }
    throw lastError!;
  } finally {
    if (client == null) httpClient.close();
  }
}

/// One attempt against a single [url]. If [partFile] already has bytes on
/// disk (from a previous interrupted attempt against this or any other
/// candidate URL — they're all meant to serve the same [expectedSha256]
/// content), this requests only the remainder via a `Range: bytes=N-`
/// header. If the server doesn't honor it (responds `200` instead of `206`,
/// i.e. it's sending the whole file from byte 0 again), this falls back to
/// overwriting [partFile] from scratch rather than corrupting it by
/// appending full content after existing bytes.
///
/// Throws without renaming [partFile] into place on any failure. Only a
/// checksum mismatch deletes it — a network error or bad status code
/// leaves whatever prefix was already written for a later resume attempt.
Stream<DownloadProgress> _downloadOnce({
  required String url,
  required File partFile,
  required String expectedSha256,
  required HttpClient httpClient,
}) async* {
  final resumeFrom = await partFile.exists() ? await partFile.length() : 0;

  final request = await httpClient.getUrl(Uri.parse(url));
  if (resumeFrom > 0) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
  }
  final response = await request.close();

  final resuming = resumeFrom > 0 && response.statusCode == HttpStatus.partialContent;
  if (!resuming && response.statusCode != HttpStatus.ok) {
    throw StateError('Download failed: HTTP ${response.statusCode} for $url');
  }

  final digestSink = _DigestSink();
  final hashSink = sha256.startChunkedConversion(digestSink);
  var receivedBytes = 0;
  int? totalBytes;
  final IOSink sink;

  if (resuming) {
    // Re-hash the bytes already on disk (a fast local read) so the final
    // digest still covers the whole file, then append what the server
    // sends starting at `resumeFrom`.
    await for (final chunk in partFile.openRead()) {
      hashSink.add(chunk);
    }
    receivedBytes = resumeFrom;
    sink = partFile.openWrite(mode: FileMode.writeOnlyAppend);
    final remaining = response.contentLength;
    totalBytes = remaining >= 0 ? resumeFrom + remaining : null;
  } else {
    sink = partFile.openWrite();
    totalBytes = response.contentLength >= 0 ? response.contentLength : null;
  }

  try {
    yield DownloadProgress(receivedBytes: receivedBytes, totalBytes: totalBytes);

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
      await partFile.delete();
      throw StateError(
        'Checksum mismatch for $url: expected $expectedSha256, got $actual',
      );
    }
  } catch (_) {
    await sink.close().catchError((_) {});
    rethrow;
  }
}

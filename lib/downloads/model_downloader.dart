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
/// when the server didn't report a `Content-Length`. [source] is the
/// authority (host, plus port if non-default) of the candidate URL this
/// progress came from — null only for the "already verified, nothing to
/// download" short-circuit — surfaced in the UI so a user hitting a slow or
/// failing download can tell which mirror is actually in use without
/// digging through logs.
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
    this.source,
  });

  final int receivedBytes;
  final int? totalBytes;
  final String? source;
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
/// trying each of [spec.urls] until one produces a verified file.
///
/// Which candidate is tried first is decided by [_reachabilityOrdered]: a
/// short concurrent HEAD-request race, not the fixed order [spec.urls] was
/// declared in. Mirror reachability from mainland China is unpredictable
/// and ISP/region-dependent — a GitHub-release proxy that works on one
/// network can be fully blocked on another, while direct github.com (always
/// tried too, never skipped) sometimes gets through when neither proxy
/// does — so a fixed priority order risks burning the full per-candidate
/// connection timeout on sources that are actually dead on this network
/// before ever reaching the one that works.
///
/// Streams to a sibling `.part` file while incrementally hashing it. A
/// server that accepts the connection but then goes silent — whether before
/// ever sending response headers, or after headers but with no (or only
/// partial) body bytes — counts as a failure too, not just a dropped
/// connection or bad status code: [stallTimeout] bounds how long this waits
/// at each of those two stages (and, within the body stage, between
/// individual chunks), so a slow-but-steady transfer is never cut off, only
/// one that's gone completely silent. This was observed on-device: a proxy
/// mirror answered the reachability race's `HEAD` probe fine, won the race,
/// then accepted the real `GET`'s connection and returned headers but never
/// sent a single body byte — `httpClient.connectionTimeout` alone doesn't
/// catch that, since the TCP handshake itself succeeded. A leftover `.part`
/// file from an earlier interrupted
/// attempt (app killed, connection dropped, or exactly this kind of stall)
/// is resumed via an HTTP `Range` request rather than re-downloaded from
/// scratch — see [_downloadOnce]. Only a proven-corrupt
/// download (failed checksum) deletes the `.part` file; any other failure —
/// a network error, a non-200/206 response — leaves it in place so the next
/// attempt (the next candidate URL, or a future call after the app
/// restarts) can resume from it. Only once every candidate has failed does
/// this throw — a single StateError listing every URL's individual
/// failure, not just the last one, since on a flaky connection the earlier
/// candidates' errors are often the more informative ones (e.g. the primary
/// host timing out vs. a mirror returning 403). [spec.destinationPath] is
/// never touched until a candidate's download verifies, so an interrupted
/// or corrupted attempt can never leave a bad file at the final path. If
/// [spec.destinationPath] already exists and verifies, completes
/// immediately without downloading anything.
Stream<DownloadProgress> downloadAndVerify(
  DownloadSpec spec, {
  HttpClient? client,
  Duration probeTimeout = const Duration(seconds: 5),
  Duration stallTimeout = const Duration(seconds: 20),
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
    final orderedUrls = spec.urls.length > 1
        ? await _reachabilityOrdered(spec.urls, httpClient, probeTimeout)
        : spec.urls;
    final failures = <String>[];
    for (final url in orderedUrls) {
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
              stallTimeout: stallTimeout,
            )) {
          yield progress;
        }
        await partFile.rename(spec.destinationPath);
        return;
      } catch (error) {
        failures.add('$url: $error');
      }
    }
    throw StateError(
      'All ${spec.urls.length} source(s) failed:\n${failures.join('\n')}',
    );
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Probes every candidate in [urls] concurrently with a short `HEAD`
/// request and returns them reordered so ones that answered successfully
/// come first — in the order they answered, so the fastest-reachable
/// candidate is tried first — followed by any that failed or didn't
/// respond within [probeTimeout], in their original order as a fallback.
/// Returns [urls] unchanged if every probe fails, since the normal
/// try-each-in-order loop's own error reporting already covers that case.
///
/// A `HEAD` request (rather than opening a real `GET` and cancelling it) is
/// enough to establish reachability: every mirror this app points at was
/// already confirmed to answer `HEAD` with a matching `Content-Length` when
/// it was vetted as a source (see docs/model-sources.md).
Future<List<String>> _reachabilityOrdered(
  List<String> urls,
  HttpClient httpClient,
  Duration probeTimeout,
) async {
  final reachable = <String>[];
  await Future.wait(
    urls.map((url) async {
      try {
        final request = await httpClient
            .headUrl(Uri.parse(url))
            .timeout(probeTimeout);
        final response = await request.close().timeout(probeTimeout);
        await response.drain<void>();
        if (response.statusCode < 400) reachable.add(url);
      } catch (_) {
        // Left out of `reachable`; still gets a real attempt below, just
        // not prioritized.
      }
    }),
  );
  if (reachable.isEmpty) return urls;
  final unreachable = urls.where((url) => !reachable.contains(url));
  return [...reachable, ...unreachable];
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
  required Duration stallTimeout,
}) async* {
  final source = Uri.parse(url).authority;
  final resumeFrom = await partFile.exists() ? await partFile.length() : 0;

  final request = await httpClient.getUrl(Uri.parse(url));
  if (resumeFrom > 0) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
  }
  // `httpClient.connectionTimeout` only bounds the TCP handshake — a server
  // that accepts the connection but never sends any HTTP response (not even
  // headers) would otherwise hang here indefinitely.
  final response = await request.close().timeout(stallTimeout);

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
    yield DownloadProgress(
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      source: source,
    );

    // `.timeout()` resets its clock on every chunk, not once for the whole
    // transfer — it only fires on genuine silence, so a slow-but-still-
    // moving download is never penalized, only one that's gone fully quiet
    // (see the stall this was added for: a proxy mirror that answered the
    // reachability probe's HEAD request fine, then accepted the real GET's
    // connection and returned headers, but never sent a single body byte).
    await for (final chunk in response.timeout(stallTimeout)) {
      sink.add(chunk);
      hashSink.add(chunk);
      receivedBytes += chunk.length;
      yield DownloadProgress(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        source: source,
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

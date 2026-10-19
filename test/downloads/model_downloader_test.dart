import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/downloads/model_downloader.dart';

// A real loopback HTTP server, not a mocked HttpClient: dart:io's HttpClient
// is a concrete class with no seams to inject a fake transport, but spinning
// up a server bound to localhost is fast, deterministic, and touches no real
// network — the standard way to test code built on HttpClient.
void main() {
  late Directory tempDir;
  late HttpServer server;

  const payload = 'hello loud caption model bytes';
  const payloadBytes = <int>[
    104, 101, 108, 108, 111, 32, 108, 111, 117, 100, 32, 99, 97, 112, 116,
    105, 111, 110, 32, 109, 111, 100, 101, 108, 32, 98, 121, 116, 101, 115,
  ];
  const payloadSha256 =
      'bc5a1c677d46fe82c75586dae88492003d56f2981b08f9d5c2e2d60e6efc79f9';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_downloader_test_');
    server = await HttpServer.bind('localhost', 0);
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('payload decodes to the expected bytes', () {
    // Guards the hand-transcribed byte list above against a typo breaking
    // every other test in a confusing way.
    expect(String.fromCharCodes(payloadBytes), payload);
  });

  test(
    'downloads, verifies, and atomically publishes a matching file',
    () async {
      server.listen((request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(payloadBytes);
        request.response.close();
      });
      final destinationPath = '${tempDir.path}/model.bin';

      final events = await downloadAndVerify(
        DownloadSpec(
          urls: ['http://localhost:${server.port}/model.bin'],
          destinationPath: destinationPath,
          sha256: payloadSha256,
        ),
      ).toList();

      expect(events, isNotEmpty);
      expect(events.last.receivedBytes, payloadBytes.length);
      final destination = File(destinationPath);
      expect(await destination.exists(), isTrue);
      expect(await destination.readAsBytes(), payloadBytes);
      expect(await File('$destinationPath.part').exists(), isFalse);
    },
  );

  test(
    'a checksum mismatch deletes the .part file and never touches the destination',
    () async {
      server.listen((request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(payloadBytes);
        request.response.close();
      });
      final destinationPath = '${tempDir.path}/model.bin';

      await expectLater(
        downloadAndVerify(
          DownloadSpec(
            urls: ['http://localhost:${server.port}/model.bin'],
            destinationPath: destinationPath,
            sha256: '0' * 64,
          ),
        ).drain<void>(),
        throwsA(isA<StateError>()),
      );

      expect(await File(destinationPath).exists(), isFalse);
      expect(await File('$destinationPath.part').exists(), isFalse);
    },
  );

  test('a non-200 response throws and leaves no partial file', () async {
    server.listen((request) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
    });
    final destinationPath = '${tempDir.path}/model.bin';

    await expectLater(
      downloadAndVerify(
        DownloadSpec(
          urls: ['http://localhost:${server.port}/missing.bin'],
          destinationPath: destinationPath,
          sha256: payloadSha256,
        ),
      ).drain<void>(),
      throwsA(isA<StateError>()),
    );

    expect(await File(destinationPath).exists(), isFalse);
    expect(await File('$destinationPath.part').exists(), isFalse);
  });

  test(
    'skips downloading entirely when the destination already verifies',
    () async {
      var requestCount = 0;
      server.listen((request) {
        requestCount++;
        request.response.statusCode = HttpStatus.ok;
        request.response.add(payloadBytes);
        request.response.close();
      });
      final destinationPath = '${tempDir.path}/model.bin';
      await File(destinationPath).writeAsBytes(payloadBytes);

      final events = await downloadAndVerify(
        DownloadSpec(
          urls: ['http://localhost:${server.port}/model.bin'],
          destinationPath: destinationPath,
          sha256: payloadSha256,
        ),
      ).toList();

      expect(requestCount, 0, reason: 'no HTTP request should be made');
      expect(events, hasLength(1));
      expect(events.single.receivedBytes, payloadBytes.length);
    },
  );

  test('verifyExisting confirms a matching file and rejects a mismatch', () async {
    final path = '${tempDir.path}/payload.bin';
    await File(path).writeAsBytes(payloadBytes);

    expect(await verifyExisting(path, payloadSha256), isTrue);
    expect(await verifyExisting(path, '0' * 64), isFalse);
  });

  group('multi-URL fallback', () {
    test(
      'falls back to the second URL when the first returns a non-200 response',
      () async {
        server.listen((request) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        });
        final goodServer = await HttpServer.bind('localhost', 0);
        addTearDown(() => goodServer.close(force: true));
        goodServer.listen((request) {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(payloadBytes);
          request.response.close();
        });
        final destinationPath = '${tempDir.path}/model.bin';

        final events = await downloadAndVerify(
          DownloadSpec(
            urls: [
              'http://localhost:${server.port}/missing.bin',
              'http://localhost:${goodServer.port}/model.bin',
            ],
            destinationPath: destinationPath,
            sha256: payloadSha256,
          ),
        ).toList();

        expect(events, isNotEmpty);
        expect(await File(destinationPath).readAsBytes(), payloadBytes);
        expect(await File('$destinationPath.part').exists(), isFalse);
      },
    );

    test(
      'falls back to the second URL when the first fails a connection entirely',
      () async {
        // A port nothing is listening on, so the connection itself fails
        // (not just a bad HTTP response) — a different failure mode than
        // the non-200 case above.
        final deadPortServer = await HttpServer.bind('localhost', 0);
        final deadPort = deadPortServer.port;
        await deadPortServer.close(force: true);
        final goodServer = await HttpServer.bind('localhost', 0);
        addTearDown(() => goodServer.close(force: true));
        goodServer.listen((request) {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(payloadBytes);
          request.response.close();
        });
        final destinationPath = '${tempDir.path}/model.bin';

        final events = await downloadAndVerify(
          DownloadSpec(
            urls: [
              'http://localhost:$deadPort/missing.bin',
              'http://localhost:${goodServer.port}/model.bin',
            ],
            destinationPath: destinationPath,
            sha256: payloadSha256,
          ),
        ).toList();

        expect(events, isNotEmpty);
        expect(await File(destinationPath).readAsBytes(), payloadBytes);
      },
    );

    test(
      'prioritizes a reachable candidate over an earlier one that never responds',
      () async {
        // The first URL's server accepts the TCP connection but never
        // answers the probe's HEAD request (or, if reachability-based
        // reordering weren't in place, a real GET) — mirroring a real
        // on-device finding where a GitHub-release proxy connected fine but
        // then hung until the 15s connection timeout, even though a
        // different, genuinely reachable mirror was listed right after it.
        // Without reordering, this test would hang waiting on that real GET
        // instead of ever reaching the good server.
        server.listen((request) {
          // Deliberately never responds.
        });
        final goodServer = await HttpServer.bind('localhost', 0);
        addTearDown(() => goodServer.close(force: true));
        goodServer.listen((request) {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(payloadBytes);
          request.response.close();
        });
        final destinationPath = '${tempDir.path}/model.bin';

        final events = await downloadAndVerify(
          DownloadSpec(
            urls: [
              'http://localhost:${server.port}/hangs.bin',
              'http://localhost:${goodServer.port}/model.bin',
            ],
            destinationPath: destinationPath,
            sha256: payloadSha256,
          ),
          probeTimeout: const Duration(milliseconds: 200),
        ).toList();

        expect(events, isNotEmpty);
        expect(await File(destinationPath).readAsBytes(), payloadBytes);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'falls back to the second URL when the first accepts the connection '
      'and answers HEAD but then never sends any body bytes for a real GET',
      () async {
        // Mirrors a real on-device finding: a proxy mirror answered the
        // concurrent reachability probe's HEAD request instantly (so it won
        // the race and was tried first), connected fine for the real GET
        // and returned headers, then never sent a single body byte or
        // closed the connection — a stall the original connection-timeout-
        // only design had no way to detect, since the connection itself
        // never failed.
        server.listen((request) {
          if (request.method == 'HEAD') {
            request.response.statusCode = HttpStatus.ok;
            request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentLength = payloadBytes.length;
          // Deliberately never writes a body or closes the response.
        });
        final goodServer = await HttpServer.bind('localhost', 0);
        addTearDown(() => goodServer.close(force: true));
        goodServer.listen((request) {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(payloadBytes);
          request.response.close();
        });
        final destinationPath = '${tempDir.path}/model.bin';

        final events = await downloadAndVerify(
          DownloadSpec(
            urls: [
              'http://localhost:${server.port}/stalls.bin',
              'http://localhost:${goodServer.port}/model.bin',
            ],
            destinationPath: destinationPath,
            sha256: payloadSha256,
          ),
          probeTimeout: const Duration(milliseconds: 200),
          stallTimeout: const Duration(milliseconds: 200),
        ).toList();

        expect(events, isNotEmpty);
        expect(await File(destinationPath).readAsBytes(), payloadBytes);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('throws an aggregated error listing every candidate\'s failure', () async {
      server.listen((request) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      });
      final secondServer = await HttpServer.bind('localhost', 0);
      addTearDown(() => secondServer.close(force: true));
      secondServer.listen((request) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.close();
      });
      final destinationPath = '${tempDir.path}/model.bin';

      await expectLater(
        downloadAndVerify(
          DownloadSpec(
            urls: [
              'http://localhost:${server.port}/missing.bin',
              'http://localhost:${secondServer.port}/forbidden.bin',
            ],
            destinationPath: destinationPath,
            sha256: payloadSha256,
          ),
        ).drain<void>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('404'), contains('403')),
          ),
        ),
      );

      expect(await File(destinationPath).exists(), isFalse);
      expect(await File('$destinationPath.part').exists(), isFalse);
    });
  });

  group('resuming an interrupted download', () {
    test(
      'resumes from a leftover .part file via a Range request when the '
      'server supports it',
      () async {
        final destinationPath = '${tempDir.path}/model.bin';
        final splitPoint = 10;
        await File(
          '$destinationPath.part',
        ).writeAsBytes(payloadBytes.sublist(0, splitPoint));

        String? receivedRangeHeader;
        server.listen((request) {
          receivedRangeHeader = request.headers.value('range');
          final remaining = payloadBytes.sublist(splitPoint);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.add(remaining);
          request.response.close();
        });

        final events = await downloadAndVerify(
          DownloadSpec(
            urls: ['http://localhost:${server.port}/model.bin'],
            destinationPath: destinationPath,
            sha256: payloadSha256,
          ),
        ).toList();

        expect(receivedRangeHeader, 'bytes=$splitPoint-');
        expect(events.first.receivedBytes, splitPoint);
        expect(await File(destinationPath).readAsBytes(), payloadBytes);
        expect(await File('$destinationPath.part').exists(), isFalse);
      },
    );

    test(
      'falls back to a clean full download when the server ignores the '
      'Range request',
      () async {
        final destinationPath = '${tempDir.path}/model.bin';
        await File(
          '$destinationPath.part',
        ).writeAsBytes('stale wrong bytes'.codeUnits);

        server.listen((request) {
          request.response.statusCode = HttpStatus.ok;
          request.response.add(payloadBytes);
          request.response.close();
        });

        final events = await downloadAndVerify(
          DownloadSpec(
            urls: ['http://localhost:${server.port}/model.bin'],
            destinationPath: destinationPath,
            sha256: payloadSha256,
          ),
        ).toList();

        expect(events.first.receivedBytes, 0);
        expect(await File(destinationPath).readAsBytes(), payloadBytes);
      },
    );
  });
}

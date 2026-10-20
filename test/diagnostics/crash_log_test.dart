import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/diagnostics/crash_log.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

// _appendEntry inside crash_log.dart is fire-and-forget (unawaited) from the
// FlutterError.onError/PlatformDispatcher hooks, matching how a real crash
// handler can't block on file I/O — give its local-file write time to land
// before asserting.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPlatform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crash_log_test_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPlatform;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('reports no crash log when nothing has been logged', () async {
    expect(await readCrashLog(), isEmpty);
  });

  test('a logged Flutter error is readable afterward', () async {
    initCrashLogging();
    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('boom-message')),
    );
    await _settle();

    expect(await readCrashLog(), contains('boom-message'));
  });

  test('clearCrashLog empties the log', () async {
    initCrashLogging();
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));
    await _settle();
    expect(await readCrashLog(), isNot('暂无崩溃记录'));

    await clearCrashLog();
    expect(await readCrashLog(), isEmpty);
  });

  test(
    'an entry larger than the size cap is truncated rather than growing unbounded',
    () async {
      initCrashLogging();
      // Comfortably larger than the 256KB cap in a single entry.
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('x' * 300000)),
      );
      await _settle();

      final log = await readCrashLog();
      expect(log.length, lessThanOrEqualTo(256 * 1024));
    },
  );
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Caps the log file so a crash loop can't grow it unboundedly — keeps the
/// most recent entries, dropping the oldest once this is exceeded.
const _maxLogBytes = 256 * 1024;
const _logFileName = 'crash_log.txt';

Future<File> _logFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/$_logFileName');
}

/// Hooks `FlutterError.onError`/`PlatformDispatcher.instance.onError` to
/// append a timestamped entry to a local, capped-size log file, viewable
/// later via Settings — a local-only alternative to telemetry, consistent
/// with the app's no-network-beyond-model-downloads privacy stance (see
/// README's Privacy section). Neither hook's existing behavior changes:
/// `FlutterError`'s prior handler (normally `FlutterError.presentError`,
/// Flutter's own default) still runs after logging, and the platform
/// dispatcher hook still returns `false` — this purely adds a side-channel
/// file write, never suppresses or alters how an error is otherwise
/// handled.
///
/// Call once, near the top of `main()`, before `runApp`.
void initCrashLogging() {
  final priorOnError = FlutterError.onError ?? FlutterError.presentError;
  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(_appendEntry('${details.exceptionAsString()}\n${details.stack}'));
    priorOnError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(_appendEntry('$error\n$stack'));
    return false;
  };
}

Future<void> _appendEntry(String details) async {
  try {
    final file = await _logFile();
    final entry = '[${DateTime.now().toIso8601String()}]\n$details\n\n';
    final existing = await file.exists() ? await file.readAsString() : '';
    var combined = existing + entry;
    if (combined.length > _maxLogBytes) {
      combined = combined.substring(combined.length - _maxLogBytes);
    }
    await file.writeAsString(combined);
  } catch (_) {
    // Logging must never itself become a second crash.
  }
}

/// The log's content, or an empty string if nothing has been logged. The UI
/// supplies a localized placeholder.
Future<String> readCrashLog() async {
  final file = await _logFile();
  if (!await file.exists()) return '';
  return file.readAsString();
}

Future<void> clearCrashLog() async {
  final file = await _logFile();
  if (await file.exists()) await file.delete();
}

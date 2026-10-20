import '../l10n/l10n.dart';
import 'device_status.dart' as device_status;

/// The facts a model download needs before it starts: whether the current
/// connection is Wi-Fi (so the UI can warn before spending mobile data), and
/// whether something blocks the download outright.
class DownloadPreflight {
  const DownloadPreflight({required this.isWifi, this.blockReason});

  /// Whether the active connection is Wi-Fi. Meaningless when [blockReason]
  /// is non-null; callers present that block first.
  final bool isWifi;

  /// Why the download cannot start at all (currently only insufficient disk
  /// space), or `null` when it can.
  final String? blockReason;

  bool get canStart => blockReason == null;
}

typedef DownloadPreflightCheck =
    Future<DownloadPreflight> Function({required int requiredBytes});

/// Checks the conditions common to both model downloads. Insufficient disk
/// space always blocks — such a download can only fail partway through.
/// A non-Wi-Fi connection does *not* block: it is reported through
/// [DownloadPreflight.isWifi] so each entry point can ask the user to confirm
/// using mobile data first.
///
/// [isWifiConnected]/[availableDiskSpace] default to the real device checks
/// and exist as parameters only so tests never touch the real platform
/// channel.
Future<DownloadPreflight> checkDownloadPreflight({
  required int requiredBytes,
  Future<bool> Function() isWifiConnected = device_status.isWifiConnected,
  Future<int> Function() availableDiskSpace =
      device_status.availableDiskSpaceBytes,
}) async {
  final available = await availableDiskSpace();
  if (available < requiredBytes) {
    return DownloadPreflight(
      isWifi: false,
      blockReason: L10n.current.insufficientSpace(
        _formatBytes(requiredBytes),
        _formatBytes(available),
      ),
    );
  }

  return DownloadPreflight(isWifi: await isWifiConnected());
}

String _formatBytes(int bytes) {
  const megabyte = 1024 * 1024;
  return '${(bytes / megabyte).toStringAsFixed(0)} MB';
}

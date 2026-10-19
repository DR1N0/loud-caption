import 'device_status.dart' as device_status;

/// Checks whether a download of [requiredBytes] should be allowed to start
/// right now. Disk space is always checked — an insufficient-space download
/// can only fail partway through. Wi-Fi is only checked when [wifiOnly] is
/// true (the user's own opt-in preference; nothing changes for anyone who
/// hasn't enabled it).
///
/// Returns a human-readable reason the download shouldn't start yet, or
/// `null` if it's clear to proceed. [isWifiConnected]/[availableDiskSpace]
/// default to the real device checks and exist as parameters only so tests
/// never touch the real platform channel.
Future<String?> downloadBlockReason({
  required int requiredBytes,
  required bool wifiOnly,
  Future<bool> Function() isWifiConnected = device_status.isWifiConnected,
  Future<int> Function() availableDiskSpace =
      device_status.availableDiskSpaceBytes,
}) async {
  final available = await availableDiskSpace();
  if (available < requiredBytes) {
    return '存储空间不足：需要约 ${_formatBytes(requiredBytes)}，仅剩 '
        '${_formatBytes(available)}。请清理空间后重试。';
  }

  if (wifiOnly && !await isWifiConnected()) {
    return '当前未连接 Wi-Fi。已在设置中开启"仅限 Wi-Fi 下载模型"——请连接 '
        'Wi-Fi 后重试，或在设置中关闭该选项以使用当前网络下载。';
  }

  return null;
}

String _formatBytes(int bytes) {
  const megabyte = 1024 * 1024;
  return '${(bytes / megabyte).toStringAsFixed(0)} MB';
}

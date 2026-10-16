import 'package:flutter/material.dart';

/// A labeled progress bar for an in-flight download, shared by the
/// full-screen first-launch ASR model gate and the inline on-demand
/// translation-model download.
///
/// Determinate (fills to [receivedBytes]/[totalBytes]) when [totalBytes] is
/// known; indeterminate otherwise (e.g. a server that didn't report
/// `Content-Length`).
class DownloadProgressBar extends StatelessWidget {
  const DownloadProgressBar({
    super.key,
    required this.label,
    required this.receivedBytes,
    this.totalBytes,
  });

  final String label;
  final int receivedBytes;
  final int? totalBytes;

  @override
  Widget build(BuildContext context) {
    final total = totalBytes;
    final value = total == null || total <= 0
        ? null
        : (receivedBytes / total).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: value),
        const SizedBox(height: 8),
        Text(
          total == null
              ? _formatBytes(receivedBytes)
              : '${_formatBytes(receivedBytes)} / ${_formatBytes(total)}',
          style: const TextStyle(color: Color(0xFFCACDD3), fontSize: 13),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  const megabyte = 1024 * 1024;
  return '${(bytes / megabyte).toStringAsFixed(1)} MB';
}

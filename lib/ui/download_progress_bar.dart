import 'package:flutter/material.dart';

import 'caption_theme.dart';

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
    this.detail,
    this.showByteCount = true,
  });

  final String label;
  final int receivedBytes;
  final int? totalBytes;

  /// Whether to render the byte-count line. Hidden during a phase whose
  /// progress isn't measured in transferred bytes yet, so the UI never shows
  /// a misleading `0.0 MB`.
  final bool showByteCount;

  /// Optional explanatory line under the byte count, used when the bar is
  /// determinate but the byte count alone doesn't explain the wait (e.g. a
  /// slow pure-Dart extraction).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CaptionColors>()!;
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
          style: TextStyle(color: colors.primaryText, fontSize: 16),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: value),
        const SizedBox(height: 8),
        if (showByteCount)
          Text(
            total == null
                ? _formatBytes(receivedBytes)
                : '${_formatBytes(receivedBytes)} / ${_formatBytes(total)}',
            style: TextStyle(color: colors.dimText, fontSize: 13),
          ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.dimText, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

String _formatBytes(int bytes) {
  const megabyte = 1024 * 1024;
  return '${(bytes / megabyte).toStringAsFixed(1)} MB';
}

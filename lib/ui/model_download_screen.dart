import 'dart:async';

import 'package:flutter/material.dart';

import '../downloads/download_preflight.dart';
import '../speech/sense_voice_model_download.dart';
import 'caption_theme.dart';
import 'download_progress_bar.dart';

/// Blocking first-launch gate: downloads the SenseVoice ASR + Silero VAD
/// models before any of the rest of the app (which assumes they're already
/// on disk) is constructed. See `main.dart`'s `_modelReady` gate.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({
    super.key,
    required this.onReady,
    this.downloadModel,
    this.preflightCheck = checkDownloadPreflight,
  });

  /// Called once the download stream completes successfully.
  final VoidCallback onReady;

  /// Defaults to [downloadSenseVoiceModel]; overridable so tests can inject
  /// a fake stream without touching the network.
  final Stream<ModelDownloadEvent> Function()? downloadModel;

  /// Defaults to [checkDownloadPreflight]; overridable so tests can simulate
  /// a blocked download or a non-Wi-Fi connection without touching the real
  /// platform channel.
  final DownloadPreflightCheck preflightCheck;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  ModelDownloadEvent? _event;
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _cancelled = false;
      _event = null;
    });

    final preflight = await widget.preflightCheck(
      requiredBytes: senseVoiceRequiredFreeBytes,
    );
    if (!mounted) return;
    if (preflight.blockReason != null) {
      setState(() => _error = preflight.blockReason);
      return;
    }

    if (!preflight.isWifi) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('使用移动数据下载模型？'),
          content: const Text(
            '首次使用需要下载约 240 MB 的语音识别模型。\n\n'
            '当前未连接 Wi-Fi，将继续使用移动数据下载。连接 Wi-Fi 可避免消耗流量。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续下载'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _cancelled = true);
        return;
      }
    }
    if (!mounted) return;

    (widget.downloadModel ?? downloadSenseVoiceModel)().listen(
      (event) {
        if (mounted) setState(() => _event = event);
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = '下载失败: $error');
      },
      onDone: () {
        if (mounted && _error == null) widget.onReady();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CaptionColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error != null
                ? _errorView(colors)
                : _cancelled
                ? _cancelledView(colors)
                : _progressView(colors),
          ),
        ),
      ),
    );
  }

  Widget _progressView(CaptionColors colors) {
    final event = _event;
    final extracting = event?.phase == ModelDownloadPhase.extracting;
    final receivedBytes = event?.receivedBytes ?? 0;
    // The first extraction poll can land before bzip2 has flushed anything;
    // show an indeterminate bar (without a misleading 0.0 MB) until real
    // output exists, then switch to the measured bar.
    final showExtractionBytes = !extracting || receivedBytes > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_download, color: colors.primaryText, size: 64),
        const SizedBox(height: 24),
        DownloadProgressBar(
          label: _phaseLabel(event),
          receivedBytes: receivedBytes,
          totalBytes: showExtractionBytes ? event?.totalBytes : null,
          showByteCount: showExtractionBytes,
          detail: extracting ? '正在解压约 240 MB 的模型文件，通常需要几十秒，请保持应用在前台。' : null,
        ),
      ],
    );
  }

  Widget _cancelledView(CaptionColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_off, color: colors.dimText, size: 64),
        const SizedBox(height: 20),
        Text(
          '已取消下载',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.primaryText, fontSize: 20),
        ),
        const SizedBox(height: 12),
        Text(
          '首次使用需要下载约 240 MB 的语音识别模型。\n'
          '连接 Wi-Fi 后重试可避免消耗移动数据。',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.dimText, fontSize: 15),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _start,
          child: const Text('重试', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  Widget _errorView(CaptionColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: colors.errorText, size: 64),
        const SizedBox(height: 20),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.errorText, fontSize: 16),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _start,
          child: const Text('重试', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  // Includes the active mirror's host so a user stuck on a slow or failing
  // download can tell which source is actually being used without digging
  // through logs — real-device testing found the same download can succeed
  // via one mirror and hang on another depending on the network.
  String _phaseLabel(ModelDownloadEvent? event) {
    final base = switch (event?.phase) {
      null || ModelDownloadPhase.downloadingAsr => '下载语音识别模型中…',
      ModelDownloadPhase.extracting => '解压模型中…',
      ModelDownloadPhase.downloadingVad => '下载降噪模型中…',
    };
    final source = event?.source;
    return source == null ? base : '$base\n来源: $source';
  }
}

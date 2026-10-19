import 'dart:async';

import 'package:flutter/material.dart';

import '../downloads/download_preflight.dart';
import '../settings/app_settings.dart';
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
    this.settingsStore,
    this.checkDownloadBlockReason = downloadBlockReason,
  });

  /// Called once the download stream completes successfully.
  final VoidCallback onReady;

  /// Defaults to [downloadSenseVoiceModel]; overridable so tests can inject
  /// a fake stream without touching the network.
  final Stream<ModelDownloadEvent> Function()? downloadModel;

  /// Defaults to a real [SharedPreferencesSettingsStore] — reads
  /// `wifiOnlyDownloads` directly rather than waiting on
  /// `CaptionController.initialize()`, since this screen renders before the
  /// rest of the app (including the controller) is constructed.
  final SettingsStore? settingsStore;

  /// Defaults to [downloadBlockReason]; overridable so tests can simulate a
  /// blocked preflight without touching the real platform channel.
  final Future<String?> Function({required int requiredBytes, required bool wifiOnly})
  checkDownloadBlockReason;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  ModelDownloadEvent? _event;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() => _error = null);
    final settings = await (widget.settingsStore ?? SharedPreferencesSettingsStore())
        .load();
    final blockReason = await widget.checkDownloadBlockReason(
      requiredBytes: senseVoiceRequiredFreeBytes,
      wifiOnly: settings.wifiOnlyDownloads,
    );
    if (blockReason != null) {
      if (mounted) setState(() => _error = blockReason);
      return;
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
            child: _error != null ? _errorView(colors) : _progressView(colors),
          ),
        ),
      ),
    );
  }

  Widget _progressView(CaptionColors colors) {
    final event = _event;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_download, color: colors.primaryText, size: 64),
        const SizedBox(height: 24),
        DownloadProgressBar(
          label: _phaseLabel(event?.phase),
          receivedBytes: event?.receivedBytes ?? 0,
          totalBytes: event?.totalBytes,
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

  String _phaseLabel(ModelDownloadPhase? phase) => switch (phase) {
    null || ModelDownloadPhase.downloadingAsr => '下载语音识别模型中…',
    ModelDownloadPhase.extracting => '解压模型中…',
    ModelDownloadPhase.downloadingVad => '下载降噪模型中…',
  };
}

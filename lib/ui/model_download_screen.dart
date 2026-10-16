import 'dart:async';

import 'package:flutter/material.dart';

import '../speech/sense_voice_model_download.dart';
import 'download_progress_bar.dart';

/// Blocking first-launch gate: downloads the SenseVoice ASR + Silero VAD
/// models before any of the rest of the app (which assumes they're already
/// on disk) is constructed. See `main.dart`'s `_modelReady` gate.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key, required this.onReady, this.downloadModel});

  /// Called once the download stream completes successfully.
  final VoidCallback onReady;

  /// Defaults to [downloadSenseVoiceModel]; overridable so tests can inject
  /// a fake stream without touching the network.
  final Stream<ModelDownloadEvent> Function()? downloadModel;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  ModelDownloadEvent? _event;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    setState(() => _error = null);
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101114),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null ? _errorView() : _progressView(),
        ),
      ),
    ),
  );

  Widget _progressView() {
    final event = _event;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_download, color: Colors.white, size: 64),
        const SizedBox(height: 24),
        DownloadProgressBar(
          label: _phaseLabel(event?.phase),
          receivedBytes: event?.receivedBytes ?? 0,
          totalBytes: event?.totalBytes,
        ),
      ],
    );
  }

  Widget _errorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFFFC5C0), size: 64),
        const SizedBox(height: 20),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFFC5C0), fontSize: 16),
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

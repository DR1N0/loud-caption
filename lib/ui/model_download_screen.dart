import 'dart:async';

import 'package:flutter/material.dart';

import '../downloads/download_preflight.dart';
import '../l10n/l10n.dart';
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
      final l10n = L10n.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.mobileDownloadTitle),
          content: Text(l10n.mobileDownloadNotice),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.continueDownload),
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
        if (mounted) {
          setState(
            () => _error = L10n.current.modelDownloadFailed('$error'),
          );
        }
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
    final l10n = L10n.of(context);
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
          detail: extracting ? l10n.extractingDetail : null,
        ),
      ],
    );
  }

  Widget _cancelledView(CaptionColors colors) {
    final l10n = L10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_off, color: colors.dimText, size: 64),
        const SizedBox(height: 20),
        Text(
          l10n.downloadCancelled,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.primaryText, fontSize: 20),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.downloadCancelledBody,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.dimText, fontSize: 15),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _start,
          child: Text(l10n.retry, style: const TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  Widget _errorView(CaptionColors colors) {
    final l10n = L10n.of(context);
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
          child: Text(l10n.retry, style: const TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  // Includes the active mirror's host so a user stuck on a slow or failing
  // download can tell which source is actually being used without digging
  // through logs — real-device testing found the same download can succeed
  // via one mirror and hang on another depending on the network.
  String _phaseLabel(ModelDownloadEvent? event) {
    final l10n = L10n.current;
    final base = switch (event?.phase) {
      null || ModelDownloadPhase.downloadingAsr => l10n.downloadingAsr,
      ModelDownloadPhase.extracting => l10n.extractingModel,
      ModelDownloadPhase.downloadingVad => l10n.downloadingVad,
    };
    final source = event?.source;
    return source == null ? base : '$base\n${l10n.sourceLabel(source)}';
  }
}

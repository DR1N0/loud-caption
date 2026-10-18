import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../captions/caption_controller.dart';
import '../downloads/model_downloader.dart';
import '../lifecycle/caption_lifecycle_coordinator.dart';
import '../permissions/microphone_access.dart';
import '../settings/app_settings.dart';
import 'caption_theme.dart';
import 'download_progress_bar.dart';

/// Full-screen captions; recording policy belongs to the app coordinator.
class CaptionScreen extends StatefulWidget {
  const CaptionScreen({
    super.key,
    required this.controller,
    required this.coordinator,
    required this.onOpenSettings,
  });

  final CaptionController controller;
  final CaptionLifecycleCoordinator coordinator;
  final VoidCallback onOpenSettings;

  @override
  State<CaptionScreen> createState() => _CaptionScreenState();
}

class _CaptionScreenState extends State<CaptionScreen> {
  String? _actionError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.coordinator.addListener(_onChanged);
    _setSystemUiMode(SystemUiMode.immersiveSticky);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _setSystemUiMode(SystemUiMode mode) {
    unawaited(_setSystemUiModeSafely(mode));
  }

  Future<void> _setSystemUiModeSafely(SystemUiMode mode) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(mode);
    } catch (error) {
      debugPrint('Could not update system UI mode: $error');
    }
  }

  void _runAction(Future<void> Function() action) {
    unawaited(
      action()
          .then((_) {
            if (mounted && _actionError != null) {
              setState(() => _actionError = null);
            }
          })
          .catchError((Object error) {
            if (mounted) setState(() => _actionError = '操作失败: $error');
          }),
    );
  }

  Future<void> _onCycleModePressed() async {
    try {
      await widget.coordinator.cycleMode();
    } catch (error) {
      if (mounted) setState(() => _actionError = '操作失败: $error');
      return;
    }
    if (mounted && _actionError != null) setState(() => _actionError = null);
    if (!mounted) return;

    final engine = widget.controller.translationEngine;
    final mode = widget.controller.settings.captionMode;
    if (mode == CaptionMode.captions || engine == null || engine.isLoaded) {
      return;
    }

    // `isLoaded` resets to false every process start, but the downloaded
    // model file itself persists — only ask to confirm a (re-)download when
    // one would actually happen, not on every relaunch.
    final alreadyDownloaded = await engine.isModelDownloaded();
    if (!mounted) return;

    if (!alreadyDownloaded) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('下载翻译模型'),
          content: const Text(
            '首次使用翻译需要下载约 1.08 GB 的翻译模型，确定现在下载吗？\n\n'
            '下载过程中请保持本 App 在前台，切到后台可能被系统限制网络导致中断'
            '（中断后重新进入会从断点继续，无需重新下载）。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('下载'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        _runAction(() => widget.coordinator.setCaptionMode(CaptionMode.captions));
        return;
      }
    }

    final progress = ValueNotifier<DownloadProgress?>(null);
    Object? loadError;
    unawaited(
      () async {
        try {
          await for (final event in engine.ensureLoaded()) {
            progress.value = event;
          }
        } catch (error) {
          loadError = error;
        } finally {
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        }
      }(),
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        // `barrierDismissible: false` alone doesn't block the Android back
        // button — only tap-outside. Without this, back pops the dialog
        // route while the download keeps running in the background; when it
        // later finishes, the unconditional Navigator.pop() below pops the
        // next route up (the caption screen itself) instead, leaving a
        // black screen.
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<DownloadProgress?>(
            valueListenable: progress,
            builder: (context, value, _) => DownloadProgressBar(
              label: alreadyDownloaded ? '正在加载翻译模型…' : '正在下载翻译模型…',
              receivedBytes: value?.receivedBytes ?? 0,
              totalBytes: value?.totalBytes,
            ),
          ),
        ),
      ),
    );
    progress.dispose();
    if (!mounted) return;
    if (loadError != null) {
      setState(() => _actionError = '翻译模型下载失败: $loadError');
      await widget.coordinator.setCaptionMode(CaptionMode.captions);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.coordinator.removeListener(_onChanged);
    super.dispose();
  }

  CaptionColors _colors(BuildContext context) =>
      Theme.of(context).extension<CaptionColors>()!;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _colors(context).background,
    body: SafeArea(
      child: widget.coordinator.access == MicAccessState.granted
          ? _captionView()
          : _permissionView(),
    ),
  );

  Widget _permissionView() {
    final colors = _colors(context);
    final permanentlyDenied =
        widget.coordinator.access == MicAccessState.permanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none, color: colors.primaryText, size: 64),
            const SizedBox(height: 20),
            Text(
              '开启麦克风权限后即可显示实时字幕',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.primaryText, fontSize: 24),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed:
                    widget.coordinator.access == null ||
                        widget.coordinator.permissionRequestInFlight
                    ? null
                    : permanentlyDenied
                    ? () => _runAction(() async {
                        final opened = await widget.coordinator
                            .openPermissionSettings();
                        if (!opened) throw StateError('无法打开系统设置');
                      })
                    : () => _runAction(
                        widget.coordinator.requestMicrophonePermission,
                      ),
                child: Text(
                  permanentlyDenied ? '去设置开启权限' : '开始',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captionView() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final body = Expanded(child: _captionBody(widget.controller));
    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [body, _controls(vertical: true)],
      );
    }
    return Column(children: [body, _controls(vertical: false)]);
  }

  Widget _captionBody(CaptionController controller) {
    final colors = _colors(context);
    return Column(
      children: [
        _status(controller),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Semantics(
              liveRegion: true,
              label: '实时字幕',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final line in controller.committedLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          _captionText(
                            line.original,
                            controller.settings.fontSize,
                            colors.primaryText,
                          ),
                          if (line.translation != null)
                            _captionText(
                              line.translation!,
                              controller.settings.fontSize,
                              colors.dimText,
                            ),
                        ],
                      ),
                    ),
                  if (controller.partialText.isNotEmpty)
                    _captionText(
                      controller.partialText,
                      controller.settings.fontSize,
                      colors.dimText,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _captionText(String text, double fontSize, Color color) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(color: color, fontSize: fontSize, height: 1.2),
  );

  Widget _status(CaptionController controller) {
    final colors = _colors(context);
    final status = switch (controller.status) {
      CaptionStatus.listening => '正在聆听',
      CaptionStatus.switching => '切换中…',
      CaptionStatus.starting => '正在启动…',
      CaptionStatus.retrying => '正在重试…',
      CaptionStatus.failed => controller.message ?? '识别引擎初始化失败',
      CaptionStatus.idle => '已停止',
    };
    final error = _actionError ?? widget.coordinator.lifecycleMessage;
    final message = error ?? status;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    error != null || controller.status == CaptionStatus.failed
                    ? colors.errorText
                    : colors.statusText,
                fontSize: 16,
              ),
            ),
          ),
          if (error != null || controller.status == CaptionStatus.failed)
            TextButton(
              onPressed: () => _runAction(widget.coordinator.retryCapture),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  String _modeLabel(CaptionMode mode) => switch (mode) {
    CaptionMode.captions => '字幕',
    CaptionMode.translateAll => '翻译',
    CaptionMode.translateCustom => '自定义',
  };

  /// In the landscape side rail, the bar is rotated in place rather than
  /// re-laid-out: the end nearest the edge that becomes the top (方向) ends
  /// up on top, so the vertical order is the horizontal order reversed.
  ///
  /// Portrait keeps all six buttons in a single shrunk row rather than
  /// wrapping into a grid — a deliberate tradeoff against this app's usual
  /// large-touch-target bias, accepted for this control bar specifically.
  Widget _controls({required bool vertical}) {
    final settings = widget.controller.settings;
    final buttons = [
      _controlButton(
        semanticLabel: '增大字幕字号',
        icon: Icons.text_increase,
        text: 'A+',
        onPressed: () => _runAction(widget.coordinator.increaseFont),
      ),
      _controlButton(
        semanticLabel: '减小字幕字号',
        icon: Icons.text_decrease,
        text: 'A-',
        onPressed: () => _runAction(widget.coordinator.decreaseFont),
      ),
      _controlButton(
        semanticLabel: '切换屏幕方向',
        icon: Icons.screen_rotation,
        text: '方向',
        onPressed: widget.coordinator.orientationChangeInFlight
            ? null
            : () => _runAction(widget.coordinator.toggleOrientation),
      ),
      _controlButton(
        semanticLabel: '切换模式',
        icon: Icons.translate,
        text: _modeLabel(settings.captionMode),
        onPressed: () => unawaited(_onCycleModePressed()),
      ),
      _controlButton(
        semanticLabel: '打开设置',
        icon: Icons.settings,
        text: '设置',
        onPressed: widget.onOpenSettings,
      ),
      _controlButton(
        semanticLabel: '切换昼夜模式',
        icon: settings.themeMode == AppThemeMode.dark
            ? Icons.light_mode
            : Icons.dark_mode,
        text: '昼夜',
        onPressed: () => _runAction(widget.coordinator.toggleTheme),
      ),
    ];
    final ordered = vertical ? buttons.reversed.toList() : buttons;
    final slots = [
      for (final button in ordered) Expanded(child: Center(child: button)),
    ];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: vertical
          ? SizedBox(width: 56, child: Column(children: slots))
          : Row(children: slots),
    );
  }

  Widget _controlButton({
    required String semanticLabel,
    required IconData icon,
    required String text,
    required VoidCallback? onPressed,
  }) => Semantics(
    label: semanticLabel,
    button: true,
    child: IconButton(
      tooltip: semanticLabel,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
      icon: _controlBody(icon, text),
    ),
  );

  Widget _controlBody(IconData icon, String text) {
    final colors = _colors(context);
    return SizedBox(
      width: 48,
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: colors.primaryText, size: 20),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.primaryText, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

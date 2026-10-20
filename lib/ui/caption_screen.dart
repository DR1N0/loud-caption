import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../captions/caption_controller.dart';
import '../downloads/download_preflight.dart';
import '../downloads/model_downloader.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../lifecycle/caption_lifecycle_coordinator.dart';
import '../permissions/microphone_access.dart';
import '../settings/app_settings.dart';
import '../translation/hy_mt2_model_download.dart';
import 'caption_theme.dart';
import 'download_progress_bar.dart';

/// Full-screen captions; recording policy belongs to the app coordinator.
class CaptionScreen extends StatefulWidget {
  const CaptionScreen({
    super.key,
    required this.controller,
    required this.coordinator,
    required this.onOpenSettings,
    this.preflightCheck = checkDownloadPreflight,
  });

  final CaptionController controller;
  final CaptionLifecycleCoordinator coordinator;
  final VoidCallback onOpenSettings;

  /// Defaults to [checkDownloadPreflight]; overridable so tests can simulate
  /// a blocked download or a non-Wi-Fi connection without touching the real
  /// platform channel.
  final DownloadPreflightCheck preflightCheck;

  @override
  State<CaptionScreen> createState() => _CaptionScreenState();
}

class _CaptionScreenState extends State<CaptionScreen> {
  String? _actionError;
  final _scrollController = ScrollController();

  /// Whether the caption view should auto-scroll new content into view.
  /// Paused while the user has manually scrolled away from the bottom (e.g.
  /// to re-read an older line), resumed once they scroll back near it — see
  /// the `NotificationListener` in [_captionBody].
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.coordinator.addListener(_onChanged);
    _setSystemUiMode(SystemUiMode.immersiveSticky);
    // The persisted caption mode survives an app restart, but the
    // translation engine's `isLoaded` does not — without this, reopening the
    // app already in 翻译/互译 mode would silently never load the
    // model (and so never translate) until the user manually cycled the
    // mode. `showDialog` below needs a BuildContext attached to a built
    // Navigator, hence the post-frame callback.
    if (widget.controller.settings.captionMode != CaptionMode.captions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureTranslationEngineLoaded());
      });
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stickToBottom && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
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
            if (mounted) {
              setState(
                () => _actionError = L10n.current.actionFailed('$error'),
              );
            }
          }),
    );
  }

  Future<void> _onCycleModePressed() async {
    try {
      await widget.coordinator.cycleMode();
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = L10n.current.actionFailed('$error'));
      }
      return;
    }
    if (mounted && _actionError != null) setState(() => _actionError = null);
    if (!mounted) return;
    await _ensureTranslationEngineLoaded();
  }

  /// Confirms (if needed) and drives loading the translation engine for
  /// whichever translation mode is currently active — called both right
  /// after the user cycles into a translation mode, and on app startup if
  /// a translation mode was already active from a previous session.
  Future<void> _ensureTranslationEngineLoaded() async {
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
    final l10n = L10n.of(context);

    if (!alreadyDownloaded) {
      final preflight = await widget.preflightCheck(
        requiredBytes: hyMt2RequiredFreeBytes,
      );
      if (!mounted) return;
      final blockReason = preflight.blockReason;
      if (blockReason != null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.cannotDownloadTranslationModel),
            content: Text(blockReason),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
        if (!mounted) return;
        _runAction(() => widget.coordinator.setCaptionMode(CaptionMode.captions));
        return;
      }

      final networkNotice = preflight.isWifi
          ? ''
          : l10n.translationMobileNotice;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            preflight.isWifi
                ? l10n.translationDownloadTitle
                : l10n.translationMobileTitle,
          ),
          content: Text('$networkNotice${l10n.translationDownloadBody}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                preflight.isWifi ? l10n.download : l10n.continueDownload,
              ),
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
            // The source suffix helps a user stuck on a slow/failing
            // download tell which mirror is actually in use — see
            // ModelDownloadScreen's matching label for the ASR download.
            builder: (context, value, _) => DownloadProgressBar(
              label: [
                alreadyDownloaded
                    ? l10n.loadingTranslationModel
                    : l10n.downloadingTranslationModel,
                if (value?.source != null)
                  l10n.sourceLabel(value!.source!),
              ].join('\n'),
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
      setState(
        () => _actionError = L10n.current.translationDownloadFailed('$loadError'),
      );
      await widget.coordinator.setCaptionMode(CaptionMode.captions);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.coordinator.removeListener(_onChanged);
    _scrollController.dispose();
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
    final l10n = L10n.of(context);
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
              l10n.microphonePermissionPrompt,
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
                        if (!opened) {
                          throw StateError(l10n.openSystemSettingsFailed);
                        }
                      })
                    : () => _runAction(
                        widget.coordinator.requestMicrophonePermission,
                      ),
                child: Text(
                  permanentlyDenied
                      ? l10n.openSettingsForPermission
                      : l10n.start,
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

  static const _captionBodyVerticalPadding = 16.0;

  Widget _captionBody(CaptionController controller) {
    final colors = _colors(context);
    return Column(
      children: [
        _status(controller),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => NotificationListener<ScrollNotification>(
              // Only a real user drag (or the fling it ends with) should
              // pause/resume sticky-bottom auto-scroll — our own
              // programmatic jumpTo() in _onChanged also emits scroll
              // notifications, but those carry no dragDetails.
              onNotification: (notification) {
                final isUserDriven =
                    (notification is ScrollUpdateNotification &&
                        notification.dragDetails != null) ||
                    notification is ScrollEndNotification;
                if (isUserDriven) {
                  final metrics = notification.metrics;
                  _stickToBottom =
                      metrics.maxScrollExtent - metrics.pixels <= 24.0;
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: _captionBodyVerticalPadding,
                ),
                child: ConstrainedBox(
                  // Pushes short content to the bottom of the viewport
                  // instead of floating centered with wasted space all
                  // around, while still letting longer content grow past
                  // the viewport height and scroll normally.
                  constraints: BoxConstraints(
                    minHeight:
                        constraints.maxHeight -
                        2 * _captionBodyVerticalPadding,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    label: L10n.of(context).liveCaptionsLabel,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.end,
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
    final l10n = L10n.of(context);
    final status = switch (controller.status) {
      CaptionStatus.listening => l10n.statusListening,
      CaptionStatus.switching => l10n.statusSwitching,
      CaptionStatus.starting => l10n.statusStarting,
      CaptionStatus.retrying => l10n.statusRetrying,
      CaptionStatus.failed => controller.message ?? l10n.statusFailed,
      CaptionStatus.idle => l10n.statusIdle,
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
              child: Text(l10n.retry),
            ),
        ],
      ),
    );
  }

  String _modeLabel(CaptionMode mode, AppLocalizations l10n) => switch (mode) {
    CaptionMode.captions => l10n.modeCaptions,
    CaptionMode.translateAll => l10n.modeTranslateAll,
    CaptionMode.translateCustom => l10n.modeTranslateCustom,
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
    final l10n = L10n.of(context);
    final buttons = [
      _controlButton(
        semanticLabel: l10n.increaseFontSize,
        icon: Icons.text_increase,
        text: 'A+',
        onPressed: () => _runAction(widget.coordinator.increaseFont),
      ),
      _controlButton(
        semanticLabel: l10n.decreaseFontSize,
        icon: Icons.text_decrease,
        text: 'A-',
        onPressed: () => _runAction(widget.coordinator.decreaseFont),
      ),
      _controlButton(
        semanticLabel: l10n.toggleOrientation,
        icon: Icons.screen_rotation,
        text: l10n.orientationLabel,
        onPressed: widget.coordinator.orientationChangeInFlight
            ? null
            : () => _runAction(widget.coordinator.toggleOrientation),
      ),
      _controlButton(
        semanticLabel: l10n.toggleMode,
        icon: Icons.translate,
        text: _modeLabel(settings.captionMode, l10n),
        onPressed: () => unawaited(_onCycleModePressed()),
      ),
      _controlButton(
        semanticLabel: l10n.openSettings,
        icon: Icons.settings,
        text: l10n.settingsTitle,
        onPressed: widget.onOpenSettings,
      ),
      _controlButton(
        semanticLabel: l10n.themeToggleLabel,
        icon: settings.themeMode == AppThemeMode.dark
            ? Icons.light_mode
            : Icons.dark_mode,
        text: l10n.themeLabel,
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

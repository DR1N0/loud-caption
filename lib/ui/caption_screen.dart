import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../captions/caption_controller.dart';
import '../lifecycle/caption_lifecycle_coordinator.dart';
import '../permissions/microphone_access.dart';
import '../settings/app_settings.dart';

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
  final Future<void> Function() onOpenSettings;

  @override
  State<CaptionScreen> createState() => _CaptionScreenState();
}

class _CaptionScreenState extends State<CaptionScreen> {
  bool _openingSettings = false;
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

  Future<void> _openSettings() async {
    if (_openingSettings) return;
    setState(() {
      _openingSettings = true;
      _actionError = null;
    });
    _setSystemUiMode(SystemUiMode.edgeToEdge);
    try {
      await widget.onOpenSettings();
    } catch (error) {
      if (mounted) setState(() => _actionError = '无法打开设置: $error');
    } finally {
      if (mounted) {
        _setSystemUiMode(SystemUiMode.immersiveSticky);
        setState(() => _openingSettings = false);
      }
    }
  }

  Future<void> _toggleLanguage() async {
    final enabled = widget.controller.settings.enabledLanguages;
    if (enabled.length != 2) return;
    final current = widget.controller.settings.languageCode;
    await widget.coordinator.selectLanguage(
      enabled.firstWhere((language) => language != current),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.coordinator.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101114),
    body: SafeArea(
      child: widget.coordinator.access == MicAccessState.granted
          ? _captionView()
          : _permissionView(),
    ),
  );

  Widget _permissionView() {
    final permanentlyDenied =
        widget.coordinator.access == MicAccessState.permanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_none, color: Colors.white, size: 64),
            const SizedBox(height: 20),
            const Text(
              '开启麦克风权限后即可显示实时字幕',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 24),
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
    final controller = widget.controller;
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
                      child: Text(
                        line,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: controller.settings.fontSize,
                          height: 1.2,
                        ),
                      ),
                    ),
                  if (controller.partialText.isNotEmpty)
                    Text(
                      controller.partialText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFCACDD3),
                        fontSize: controller.settings.fontSize,
                        height: 1.2,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _controls(controller.settings),
      ],
    );
  }

  Widget _status(CaptionController controller) {
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
                    ? const Color(0xFFFFC5C0)
                    : const Color(0xFFE1E3E8),
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

  Widget _controls(CaptionSettings settings) => Padding(
    padding: const EdgeInsets.all(12),
    child: Wrap(
      alignment: WrapAlignment.spaceEvenly,
      runSpacing: 8,
      spacing: 8,
      children: [
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
        _languageControl(settings),
        _controlButton(
          semanticLabel: '切换屏幕方向',
          icon: Icons.screen_rotation,
          text: '方向',
          onPressed: widget.coordinator.orientationChangeInFlight
              ? null
              : () => _runAction(widget.coordinator.toggleOrientation),
        ),
        _controlButton(
          semanticLabel: '打开设置',
          icon: Icons.settings,
          text: '设置',
          onPressed: _openingSettings ? null : () => unawaited(_openSettings()),
        ),
      ],
    ),
  );

  Widget _languageControl(CaptionSettings settings) {
    final enabled = settings.enabledLanguages;
    final name = settings.catalog
        .firstWhere((language) => language.code == settings.languageCode)
        .displayName;
    if (enabled.length >= 3) {
      return Semantics(
        label: '切换语言',
        button: true,
        child: PopupMenuButton<String>(
          tooltip: '切换语言',
          offset: Offset(0, -56.0 * enabled.length),
          onSelected: (languageCode) =>
              _runAction(() => widget.coordinator.selectLanguage(languageCode)),
          itemBuilder: (context) => [
            for (final language in settings.catalog)
              if (enabled.contains(language.code))
                PopupMenuItem(
                  value: language.code,
                  child: Text(language.displayName),
                ),
          ],
          child: _controlBody(Icons.language, name),
        ),
      );
    }
    return _controlButton(
      semanticLabel: '切换语言',
      icon: Icons.language,
      text: name,
      onPressed: enabled.length == 2 ? () => _runAction(_toggleLanguage) : null,
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
      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      icon: _controlBody(icon, text),
    ),
  );

  Widget _controlBody(IconData icon, String text) => SizedBox(
    width: 72,
    height: 56,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}

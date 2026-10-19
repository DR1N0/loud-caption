import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../captions/caption_controller.dart';
import '../diagnostics/crash_log.dart' as crash_log;
import '../settings/app_settings.dart';

/// Lets the user force a recognition language (instead of SenseVoice's own
/// "auto" detection, which can misfire on strong accents), configure where
/// translated captions go: one fixed target for 翻译 mode, and a
/// per-source-language routing table for 互译.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.readCrashLog = crash_log.readCrashLog,
    this.clearCrashLog = crash_log.clearCrashLog,
  });

  final CaptionController controller;

  /// Defaults to the real [crash_log.readCrashLog]/[crash_log.clearCrashLog];
  /// overridable so tests can inject plain in-memory fakes instead of real
  /// file I/O, which `testWidgets()`'s zone doesn't let resolve on its own.
  final Future<String> Function() readCrashLog;
  final Future<void> Function() clearCrashLog;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _apply(Future<void> Function() change) async {
    if (_changing) return;
    setState(() => _changing = true);
    var failed = false;
    try {
      await change();
    } catch (_) {
      failed = true;
    } finally {
      if (mounted) setState(() => _changing = false);
    }
    if (mounted && failed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置保存失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    return Scaffold(
      appBar: AppBar(
        leading: Semantics(
          label: '返回',
          button: true,
          child: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '字幕模式识别语言',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _languagePicker(
            semanticLabel: '字幕模式识别语言',
            languages: recognitionLanguages,
            value: settings.recognitionLanguage,
            onChanged: (language) => _apply(
              () => widget.controller.setRecognitionLanguage(language),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '翻译模式目标语言',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _languagePicker(
            semanticLabel: '翻译模式目标语言',
            languages: translationTargetLanguages,
            value: settings.translateAllTarget,
            onChanged: (language) =>
                _apply(() => widget.controller.setTranslateAllTarget(language)),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '互译：按来源语言设置目标',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final language in translationLanguages)
            _routingTile(settings, language),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('下载', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text('仅限 Wi-Fi 下载模型'),
            subtitle: const Text('关闭时，下载前仍会检查存储空间是否足够'),
            value: settings.wifiOnlyDownloads,
            onChanged: _changing
                ? null
                : (value) =>
                      _apply(() => widget.controller.setWifiOnlyDownloads(value)),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('诊断', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            title: const Text('查看崩溃日志'),
            subtitle: const Text('仅保存在本机，不会上传'),
            onTap: _showCrashLogDialog,
          ),
        ],
      ),
    );
  }

  Future<void> _showCrashLogDialog() async {
    final log = await widget.readCrashLog();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('崩溃日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(log)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.clearCrashLog();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('清除'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
              }
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _languagePicker({
    required String semanticLabel,
    required List<String> languages,
    required String value,
    required ValueChanged<String> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Semantics(
      label: semanticLabel,
      child: DropdownButton<String>(
        isExpanded: true,
        value: value,
        items: [
          for (final language in languages)
            DropdownMenuItem(
              value: language,
              child: Text(languageNames[language] ?? language),
            ),
        ],
        onChanged: _changing
            ? null
            : (language) {
                if (language != null) onChanged(language);
              },
      ),
    ),
  );

  Widget _routingTile(CaptionSettings settings, String source) {
    final target = settings.routingTargetFor(source);
    final sourceName = languageNames[source] ?? source;
    return ListTile(
      title: Text(sourceName),
      trailing: Semantics(
        label: '$sourceName的翻译目标',
        child: DropdownButton<String>(
          value: target,
          items: [
            for (final language in translationTargetLanguages)
              DropdownMenuItem(
                value: language,
                child: Text(
                  language == source
                      ? '${languageNames[language] ?? language}（不翻译）'
                      : languageNames[language] ?? language,
                ),
              ),
          ],
          onChanged: _changing
              ? null
              : (language) {
                  if (language != null) {
                    _apply(
                      () => widget.controller.setRoutingTarget(
                        source,
                        language,
                      ),
                    );
                  }
                },
        ),
      ),
    );
  }
}

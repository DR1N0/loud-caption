import 'package:flutter/material.dart';

import '../captions/caption_controller.dart';
import '../settings/app_settings.dart';

/// Lets the user force a recognition language (instead of SenseVoice's own
/// "auto" detection, which can misfire on strong accents), configure where
/// translated captions go: one fixed target for 翻译 mode, and a
/// per-source-language routing table for 互译.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final CaptionController controller;

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

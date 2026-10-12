import 'package:flutter/material.dart';

import '../captions/caption_controller.dart';
import '../settings/app_settings.dart';

/// Lets the user enable the installed speech languages for the caption screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onLanguageEnabled,
  });

  final CaptionController controller;
  final Future<void> Function(String languageCode, bool enabled)
  onLanguageEnabled;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _changingLanguage = false;

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

  Future<void> _setLanguageEnabled(
    InstalledLanguage language,
    bool enabled,
  ) async {
    if (_changingLanguage) return;
    final wasEnabled = widget.controller.settings.enabledLanguages.contains(
      language.code,
    );
    setState(() => _changingLanguage = true);
    var failed = false;
    try {
      await widget.onLanguageEnabled(language.code, enabled);
      if (!mounted) return;
      final isEnabled = widget.controller.settings.enabledLanguages.contains(
        language.code,
      );
      failed = isEnabled == wasEnabled;
    } catch (_) {
      failed = true;
    } finally {
      if (mounted) setState(() => _changingLanguage = false);
    }
    if (mounted && failed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('切换失败')));
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
          for (final language in settings.catalog)
            _languageTile(settings, language),
        ],
      ),
    );
  }

  Widget _languageTile(CaptionSettings settings, InstalledLanguage language) {
    final enabled = settings.enabledLanguages.contains(language.code);
    final isSoleEnabled = enabled && settings.enabledLanguages.length == 1;
    return CheckboxListTile(
      title: Text(language.displayName),
      value: enabled,
      onChanged: _changingLanguage || isSoleEnabled
          ? null
          : (value) => _setLanguageEnabled(language, value ?? false),
    );
  }
}

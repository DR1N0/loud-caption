import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../captions/caption_controller.dart';
import '../diagnostics/crash_log.dart' as crash_log;
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../settings/app_settings.dart';
import '../settings/language_display_names.dart';

/// Configures where translated captions go: one fixed target for 翻译 mode,
/// and a per-source-language routing table for 互译.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).settingsSaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    final l10n = L10n.of(context);
    final english = l10n.localeName.startsWith('en');
    return Scaffold(
      appBar: AppBar(
        leading: Semantics(
          label: l10n.back,
          button: true,
          child: IconButton(
            tooltip: l10n.back,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              l10n.languageSectionTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _appLanguagePicker(settings),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.translationTargetSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _languagePicker(
            semanticLabel: l10n.translationTargetSection,
            languages: translationTargetLanguages,
            value: settings.translateAllTarget,
            english: english,
            onChanged: (language) =>
                _apply(() => widget.controller.setTranslateAllTarget(language)),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.routingSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final language in translationLanguages)
            _routingTile(settings, language, l10n: l10n, english: english),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.diagnosticsSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: Text(l10n.viewCrashLog),
            subtitle: Text(l10n.crashLogSubtitle),
            onTap: _showCrashLogDialog,
          ),
        ],
      ),
    );
  }

  Widget _appLanguagePicker(CaptionSettings settings) {
    final l10n = L10n.of(context);
    String labelFor(AppLanguage language) => switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.zh => l10n.languageChinese,
      AppLanguage.en => l10n.languageEnglish,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: l10n.languageSectionTitle,
        child: DropdownButton<AppLanguage>(
          isExpanded: true,
          value: settings.appLanguage,
          items: [
            for (final language in AppLanguage.values)
              DropdownMenuItem(
                value: language,
                child: Text(labelFor(language)),
              ),
          ],
          onChanged: _changing
              ? null
              : (language) {
                  if (language != null) {
                    _apply(
                      () => widget.controller.setAppLanguage(language),
                    );
                  }
                },
        ),
      ),
    );
  }

  Future<void> _showCrashLogDialog() async {
    final log = await widget.readCrashLog();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l10n = L10n.of(ctx);
        return AlertDialog(
          title: Text(l10n.crashLogTitle),
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
              child: Text(l10n.clear),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: log));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(l10n.copiedToClipboard)),
                  );
                }
              },
              child: Text(l10n.copy),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }

  Widget _languagePicker({
    required String semanticLabel,
    required List<String> languages,
    required String value,
    required bool english,
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
              child: Text(
                displayLanguageName(language, english: english),
              ),
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

  Widget _routingTile(
    CaptionSettings settings,
    String source, {
    required AppLocalizations l10n,
    required bool english,
  }) {
    final target = settings.routingTargetFor(source);
    final sourceName = displayLanguageName(source, english: english);
    return ListTile(
      title: Text(sourceName),
      trailing: SizedBox(
        width: 160,
        child: Semantics(
          label: l10n.routingTargetLabel(sourceName),
          child: DropdownButton<String>(
            isExpanded: true,
            value: target,
            items: [
              for (final language in translationTargetLanguages)
                DropdownMenuItem(
                  value: language,
                  child: Text(
                    language == source
                        ? '${displayLanguageName(language, english: english)}'
                              '${l10n.noTranslationSuffix}'
                        : displayLanguageName(language, english: english),
                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Loud Caption';

  @override
  String get languageSectionTitle => 'App language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get back => 'Back';

  @override
  String get translationTargetSection => 'Translation target';

  @override
  String get routingSection => 'Two-way translation: target by source language';

  @override
  String get diagnosticsSection => 'Diagnostics';

  @override
  String get viewCrashLog => 'View crash log';

  @override
  String get crashLogSubtitle => 'Stored only on this device; never uploaded';

  @override
  String get crashLogTitle => 'Crash log';

  @override
  String get noCrashLog => 'No crash log recorded';

  @override
  String get clear => 'Clear';

  @override
  String get copy => 'Copy';

  @override
  String get close => 'Close';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get settingsSaveFailed => 'Could not save settings';

  @override
  String routingTargetLabel(String sourceName) {
    return '$sourceName translation target';
  }

  @override
  String get noTranslationSuffix => ' (no translation)';

  @override
  String get start => 'Start';

  @override
  String get openSettingsForPermission => 'Open settings';

  @override
  String get microphonePermissionPrompt =>
      'Allow microphone access to show live captions';

  @override
  String get liveCaptionsLabel => 'Live captions';

  @override
  String get statusListening => 'Listening';

  @override
  String get statusSwitching => 'Switching…';

  @override
  String get statusStarting => 'Starting…';

  @override
  String get statusRetrying => 'Retrying…';

  @override
  String get statusIdle => 'Stopped';

  @override
  String get statusFailed => 'Could not start recognition';

  @override
  String get retry => 'Retry';

  @override
  String get modeCaptions => 'Captions';

  @override
  String get modeTranslateAll => 'Translate';

  @override
  String get modeTranslateCustom => 'Two-way';

  @override
  String get increaseFontSize => 'Increase caption font size';

  @override
  String get decreaseFontSize => 'Decrease caption font size';

  @override
  String get toggleOrientation => 'Toggle screen orientation';

  @override
  String get orientationLabel => 'Layout';

  @override
  String get toggleMode => 'Change mode';

  @override
  String get openSettings => 'Open settings';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeToggleLabel => 'Toggle day/night mode';

  @override
  String actionFailed(String error) {
    return 'Action failed: $error';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get download => 'Download';

  @override
  String get continueDownload => 'Continue download';

  @override
  String get ok => 'OK';

  @override
  String get cannotDownloadTranslationModel =>
      'Could not download the translation model';

  @override
  String get translationDownloadTitle => 'Download translation model';

  @override
  String get translationMobileTitle =>
      'Download the translation model on mobile data?';

  @override
  String get translationMobileNotice =>
      'You are not on Wi-Fi, so this download will use mobile data. Connect to Wi-Fi to avoid data charges.\n\n';

  @override
  String get translationDownloadBody =>
      'Translation needs a one-time download of about 1.08 GB. Download it now?\n\nKeep this app in the foreground during the download; Android may restrict background networking and interrupt it. If interrupted, re-open the app and the download resumes from where it stopped.';

  @override
  String get loadingTranslationModel => 'Loading the translation model…';

  @override
  String get downloadingTranslationModel =>
      'Downloading the translation model…';

  @override
  String sourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String translationDownloadFailed(String error) {
    return 'Could not download the translation model: $error';
  }

  @override
  String get mobileDownloadTitle => 'Download the model on mobile data?';

  @override
  String get mobileDownloadNotice =>
      'The first run needs about 240 MB of speech-recognition models.\n\nYou are not on Wi-Fi, so the download will use mobile data. Connect to Wi-Fi to avoid data charges.';

  @override
  String modelDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get extractingDetail =>
      'Extracting about 240 MB of model files. This usually takes a few seconds; keep the app in the foreground.';

  @override
  String get downloadCancelled => 'Download cancelled';

  @override
  String get downloadCancelledBody =>
      'The first run needs about 240 MB of speech-recognition models.\nConnect to Wi-Fi and try again to avoid mobile data charges.';

  @override
  String get downloadingAsr => 'Downloading the speech-recognition model…';

  @override
  String get extractingModel => 'Extracting the model…';

  @override
  String get downloadingVad => 'Downloading the noise-reduction model…';

  @override
  String get settingsLoadFailed => 'Could not load settings';

  @override
  String get stopFirst => 'Stop recognition first';

  @override
  String get stopping => 'Stopping recognition…';

  @override
  String get stopFailed => 'Could not stop recognition';

  @override
  String get engineInitFailed => 'Could not initialize the recognition engine';

  @override
  String initializationFailed(String error) {
    return 'Could not initialize captions: $error';
  }

  @override
  String orientationSetFailed(String error) {
    return 'Could not set screen orientation: $error';
  }

  @override
  String orientationToggleFailed(String error) {
    return 'Could not change screen orientation: $error';
  }

  @override
  String recognitionLifecycleFailed(String error) {
    return 'Recognition lifecycle failed: $error';
  }

  @override
  String cannotConfirmRecognitionState(String error) {
    return 'Could not confirm recognition state: $error';
  }

  @override
  String cannotKeepScreenAwake(String error) {
    return 'Could not keep the screen awake: $error';
  }

  @override
  String cannotDisableScreenAwake(String error) {
    return 'Could not turn off keep-awake: $error';
  }

  @override
  String insufficientSpace(String required, String available) {
    return 'Not enough storage: about $required is needed, but only $available is available. Free up space and try again.';
  }

  @override
  String get openSystemSettingsFailed => 'Could not open system settings';

  @override
  String get translationDownloadCancelled =>
      'Translation model download cancelled';
}

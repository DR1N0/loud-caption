import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Loud Caption'**
  String get appTitle;

  /// No description provided for @languageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageSectionTitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageSystem;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @translationTargetSection.
  ///
  /// In en, this message translates to:
  /// **'Translation target'**
  String get translationTargetSection;

  /// No description provided for @routingSection.
  ///
  /// In en, this message translates to:
  /// **'Two-way translation: target by source language'**
  String get routingSection;

  /// No description provided for @diagnosticsSection.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsSection;

  /// No description provided for @viewCrashLog.
  ///
  /// In en, this message translates to:
  /// **'View crash log'**
  String get viewCrashLog;

  /// No description provided for @crashLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stored only on this device; never uploaded'**
  String get crashLogSubtitle;

  /// No description provided for @crashLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Crash log'**
  String get crashLogTitle;

  /// No description provided for @noCrashLog.
  ///
  /// In en, this message translates to:
  /// **'No crash log recorded'**
  String get noCrashLog;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save settings'**
  String get settingsSaveFailed;

  /// No description provided for @routingTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'{sourceName} translation target'**
  String routingTargetLabel(String sourceName);

  /// No description provided for @noTranslationSuffix.
  ///
  /// In en, this message translates to:
  /// **' (no translation)'**
  String get noTranslationSuffix;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @openSettingsForPermission.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettingsForPermission;

  /// No description provided for @microphonePermissionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Allow microphone access to show live captions'**
  String get microphonePermissionPrompt;

  /// No description provided for @liveCaptionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Live captions'**
  String get liveCaptionsLabel;

  /// No description provided for @statusListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get statusListening;

  /// No description provided for @statusSwitching.
  ///
  /// In en, this message translates to:
  /// **'Switching…'**
  String get statusSwitching;

  /// No description provided for @statusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get statusStarting;

  /// No description provided for @statusRetrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying…'**
  String get statusRetrying;

  /// No description provided for @statusIdle.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get statusIdle;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start recognition'**
  String get statusFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @modeCaptions.
  ///
  /// In en, this message translates to:
  /// **'Captions'**
  String get modeCaptions;

  /// No description provided for @modeTranslateAll.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get modeTranslateAll;

  /// No description provided for @modeTranslateCustom.
  ///
  /// In en, this message translates to:
  /// **'Two-way'**
  String get modeTranslateCustom;

  /// No description provided for @increaseFontSize.
  ///
  /// In en, this message translates to:
  /// **'Increase caption font size'**
  String get increaseFontSize;

  /// No description provided for @decreaseFontSize.
  ///
  /// In en, this message translates to:
  /// **'Decrease caption font size'**
  String get decreaseFontSize;

  /// No description provided for @toggleOrientation.
  ///
  /// In en, this message translates to:
  /// **'Toggle screen orientation'**
  String get toggleOrientation;

  /// No description provided for @orientationLabel.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get orientationLabel;

  /// No description provided for @toggleMode.
  ///
  /// In en, this message translates to:
  /// **'Change mode'**
  String get toggleMode;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @themeToggleLabel.
  ///
  /// In en, this message translates to:
  /// **'Toggle day/night mode'**
  String get themeToggleLabel;

  /// No description provided for @actionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed: {error}'**
  String actionFailed(String error);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @continueDownload.
  ///
  /// In en, this message translates to:
  /// **'Continue download'**
  String get continueDownload;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cannotDownloadTranslationModel.
  ///
  /// In en, this message translates to:
  /// **'Could not download the translation model'**
  String get cannotDownloadTranslationModel;

  /// No description provided for @translationDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download translation model'**
  String get translationDownloadTitle;

  /// No description provided for @translationMobileTitle.
  ///
  /// In en, this message translates to:
  /// **'Download the translation model on mobile data?'**
  String get translationMobileTitle;

  /// No description provided for @translationMobileNotice.
  ///
  /// In en, this message translates to:
  /// **'You are not on Wi-Fi, so this download will use mobile data. Connect to Wi-Fi to avoid data charges.\n\n'**
  String get translationMobileNotice;

  /// No description provided for @translationDownloadBody.
  ///
  /// In en, this message translates to:
  /// **'Translation needs a one-time download of about 1.08 GB. Download it now?\n\nKeep this app in the foreground during the download; Android may restrict background networking and interrupt it. If interrupted, re-open the app and the download resumes from where it stopped.'**
  String get translationDownloadBody;

  /// No description provided for @loadingTranslationModel.
  ///
  /// In en, this message translates to:
  /// **'Loading the translation model…'**
  String get loadingTranslationModel;

  /// No description provided for @downloadingTranslationModel.
  ///
  /// In en, this message translates to:
  /// **'Downloading the translation model…'**
  String get downloadingTranslationModel;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String sourceLabel(String source);

  /// No description provided for @translationDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not download the translation model: {error}'**
  String translationDownloadFailed(String error);

  /// No description provided for @mobileDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download the model on mobile data?'**
  String get mobileDownloadTitle;

  /// No description provided for @mobileDownloadNotice.
  ///
  /// In en, this message translates to:
  /// **'The first run needs about 240 MB of speech-recognition models.\n\nYou are not on Wi-Fi, so the download will use mobile data. Connect to Wi-Fi to avoid data charges.'**
  String get mobileDownloadNotice;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String modelDownloadFailed(String error);

  /// No description provided for @extractingDetail.
  ///
  /// In en, this message translates to:
  /// **'Extracting about 240 MB of model files. This usually takes a few seconds; keep the app in the foreground.'**
  String get extractingDetail;

  /// No description provided for @downloadCancelled.
  ///
  /// In en, this message translates to:
  /// **'Download cancelled'**
  String get downloadCancelled;

  /// No description provided for @downloadCancelledBody.
  ///
  /// In en, this message translates to:
  /// **'The first run needs about 240 MB of speech-recognition models.\nConnect to Wi-Fi and try again to avoid mobile data charges.'**
  String get downloadCancelledBody;

  /// No description provided for @downloadingAsr.
  ///
  /// In en, this message translates to:
  /// **'Downloading the speech-recognition model…'**
  String get downloadingAsr;

  /// No description provided for @extractingModel.
  ///
  /// In en, this message translates to:
  /// **'Extracting the model…'**
  String get extractingModel;

  /// No description provided for @downloadingVad.
  ///
  /// In en, this message translates to:
  /// **'Downloading the noise-reduction model…'**
  String get downloadingVad;

  /// No description provided for @settingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load settings'**
  String get settingsLoadFailed;

  /// No description provided for @stopFirst.
  ///
  /// In en, this message translates to:
  /// **'Stop recognition first'**
  String get stopFirst;

  /// No description provided for @stopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping recognition…'**
  String get stopping;

  /// No description provided for @stopFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not stop recognition'**
  String get stopFailed;

  /// No description provided for @engineInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not initialize the recognition engine'**
  String get engineInitFailed;

  /// No description provided for @initializationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not initialize captions: {error}'**
  String initializationFailed(String error);

  /// No description provided for @orientationSetFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not set screen orientation: {error}'**
  String orientationSetFailed(String error);

  /// No description provided for @orientationToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change screen orientation: {error}'**
  String orientationToggleFailed(String error);

  /// No description provided for @recognitionLifecycleFailed.
  ///
  /// In en, this message translates to:
  /// **'Recognition lifecycle failed: {error}'**
  String recognitionLifecycleFailed(String error);

  /// No description provided for @cannotConfirmRecognitionState.
  ///
  /// In en, this message translates to:
  /// **'Could not confirm recognition state: {error}'**
  String cannotConfirmRecognitionState(String error);

  /// No description provided for @cannotKeepScreenAwake.
  ///
  /// In en, this message translates to:
  /// **'Could not keep the screen awake: {error}'**
  String cannotKeepScreenAwake(String error);

  /// No description provided for @cannotDisableScreenAwake.
  ///
  /// In en, this message translates to:
  /// **'Could not turn off keep-awake: {error}'**
  String cannotDisableScreenAwake(String error);

  /// No description provided for @insufficientSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage: about {required} is needed, but only {available} is available. Free up space and try again.'**
  String insufficientSpace(String required, String available);

  /// No description provided for @openSystemSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open system settings'**
  String get openSystemSettingsFailed;

  /// No description provided for @translationDownloadCancelled.
  ///
  /// In en, this message translates to:
  /// **'Translation model download cancelled'**
  String get translationDownloadCancelled;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

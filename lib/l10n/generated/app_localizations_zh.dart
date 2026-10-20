// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '大字幕';

  @override
  String get languageSectionTitle => '应用语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsTitle => '设置';

  @override
  String get back => '返回';

  @override
  String get translationTargetSection => '翻译模式目标语言';

  @override
  String get routingSection => '互译：按来源语言设置目标';

  @override
  String get diagnosticsSection => '诊断';

  @override
  String get viewCrashLog => '查看崩溃日志';

  @override
  String get crashLogSubtitle => '仅保存在本机，不会上传';

  @override
  String get crashLogTitle => '崩溃日志';

  @override
  String get clear => '清除';

  @override
  String get copy => '复制';

  @override
  String get close => '关闭';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get settingsSaveFailed => '设置保存失败';

  @override
  String routingTargetLabel(String sourceName) {
    return '$sourceName的翻译目标';
  }

  @override
  String get noTranslationSuffix => '（不翻译）';

  @override
  String get start => '开始';

  @override
  String get openSettingsForPermission => '去设置开启权限';

  @override
  String get microphonePermissionPrompt => '开启麦克风权限后即可显示实时字幕';

  @override
  String get liveCaptionsLabel => '实时字幕';

  @override
  String get statusListening => '正在聆听';

  @override
  String get statusSwitching => '切换中…';

  @override
  String get statusStarting => '正在启动…';

  @override
  String get statusRetrying => '正在重试…';

  @override
  String get statusIdle => '已停止';

  @override
  String get statusFailed => '识别引擎初始化失败';

  @override
  String get retry => '重试';

  @override
  String get modeCaptions => '字幕';

  @override
  String get modeTranslateAll => '翻译';

  @override
  String get modeTranslateCustom => '互译';

  @override
  String get increaseFontSize => '增大字幕字号';

  @override
  String get decreaseFontSize => '减小字幕字号';

  @override
  String get toggleOrientation => '切换屏幕方向';

  @override
  String get orientationLabel => '方向';

  @override
  String get toggleMode => '切换模式';

  @override
  String get openSettings => '打开设置';

  @override
  String get themeLabel => '昼夜';

  @override
  String get themeToggleLabel => '切换昼夜模式';

  @override
  String actionFailed(String error) {
    return '操作失败: $error';
  }

  @override
  String get cancel => '取消';

  @override
  String get download => '下载';

  @override
  String get continueDownload => '继续下载';

  @override
  String get ok => '好';

  @override
  String get cannotDownloadTranslationModel => '无法下载翻译模型';

  @override
  String get translationDownloadTitle => '下载翻译模型';

  @override
  String get translationMobileTitle => '使用移动数据下载翻译模型？';

  @override
  String get translationMobileNotice =>
      '当前未连接 Wi-Fi，将使用移动数据下载。连接 Wi-Fi 可避免消耗流量。\n\n';

  @override
  String get translationDownloadBody =>
      '首次使用翻译需要下载约 1.08 GB 的翻译模型，确定现在下载吗？\n\n下载过程中请保持本 App 在前台，切到后台可能被系统限制网络导致中断（中断后重新进入会从断点继续，无需重新下载）。';

  @override
  String get loadingTranslationModel => '正在加载翻译模型…';

  @override
  String get downloadingTranslationModel => '正在下载翻译模型…';

  @override
  String sourceLabel(String source) {
    return '来源: $source';
  }

  @override
  String translationDownloadFailed(String error) {
    return '翻译模型下载失败: $error';
  }

  @override
  String get mobileDownloadTitle => '使用移动数据下载模型？';

  @override
  String get mobileDownloadNotice =>
      '首次使用需要下载约 240 MB 的语音识别模型。\n\n当前未连接 Wi-Fi，将继续使用移动数据下载。连接 Wi-Fi 可避免消耗流量。';

  @override
  String modelDownloadFailed(String error) {
    return '下载失败: $error';
  }

  @override
  String get extractingDetail => '正在解压约 240 MB 的模型文件，通常需要几十秒，请保持应用在前台。';

  @override
  String get downloadCancelled => '已取消下载';

  @override
  String get downloadCancelledBody =>
      '首次使用需要下载约 240 MB 的语音识别模型。\n连接 Wi-Fi 后重试可避免消耗移动数据。';

  @override
  String get downloadingAsr => '下载语音识别模型中…';

  @override
  String get extractingModel => '解压模型中…';

  @override
  String get downloadingVad => '下载降噪模型中…';

  @override
  String get settingsLoadFailed => '设置加载失败';

  @override
  String get stopFirst => '请先停止识别';

  @override
  String get stopping => '正在停止识别';

  @override
  String get stopFailed => '停止识别失败';

  @override
  String get engineInitFailed => '识别引擎初始化失败';

  @override
  String initializationFailed(String error) {
    return '无法初始化字幕: $error';
  }

  @override
  String orientationSetFailed(String error) {
    return '屏幕方向设置失败: $error';
  }

  @override
  String orientationToggleFailed(String error) {
    return '屏幕方向切换失败: $error';
  }

  @override
  String recognitionLifecycleFailed(String error) {
    return '识别生命周期失败: $error';
  }

  @override
  String cannotConfirmRecognitionState(String error) {
    return '无法确认识别状态: $error';
  }

  @override
  String cannotKeepScreenAwake(String error) {
    return '无法保持屏幕常亮: $error';
  }

  @override
  String cannotDisableScreenAwake(String error) {
    return '无法关闭屏幕常亮: $error';
  }

  @override
  String insufficientSpace(String required, String available) {
    return '存储空间不足：需要约 $required，仅剩 $available。请清理空间后重试。';
  }

  @override
  String get openSystemSettingsFailed => '无法打开系统设置';

  @override
  String get translationDownloadCancelled => '已取消下载翻译模型';
}

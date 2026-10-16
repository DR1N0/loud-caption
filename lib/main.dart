import 'dart:async';

import 'package:flutter/material.dart';

import 'captions/caption_controller.dart';
import 'lifecycle/caption_lifecycle_coordinator.dart';
import 'lifecycle/screen_awake.dart';
import 'permissions/microphone_access.dart';
import 'settings/app_settings.dart';
import 'speech/mic_capture.dart';
import 'speech/sense_voice_model_download.dart';
import 'speech/sherpa_onnx_speech_engine.dart';
import 'speech/speech_engine.dart';
import 'speech/vad_chunked_sense_voice_strategy.dart';
import 'translation/noop_translation_engine.dart';
import 'translation/translation_engine.dart';
import 'ui/caption_screen.dart';
import 'ui/caption_theme.dart';
import 'ui/model_download_screen.dart';
import 'ui/orientation_manager.dart';
import 'ui/settings_screen.dart';

void main() {
  runApp(const CaptionApp());
}

/// Owns capture policy and the two routes without tying recognition to a page.
class CaptionApp extends StatefulWidget {
  const CaptionApp({
    super.key,
    this.engine,
    this.settingsStore,
    this.translationEngine,
    this.microphoneAccess,
    this.screenAwake,
    this.orientationManager,
    this.isModelReady,
    this.downloadModel,
  });

  final SpeechEngine? engine;
  final SettingsStore? settingsStore;
  final TranslationEngine? translationEngine;
  final MicrophoneAccess? microphoneAccess;
  final ScreenAwake? screenAwake;
  final OrientationManager? orientationManager;

  /// Defaults to [isSenseVoiceModelReady]; overridable so tests that aren't
  /// exercising the download flow itself can skip straight past it.
  final Future<bool> Function()? isModelReady;

  /// Defaults to [downloadSenseVoiceModel]; forwarded to [ModelDownloadScreen]
  /// unchanged.
  final Stream<ModelDownloadEvent> Function()? downloadModel;

  @override
  State<CaptionApp> createState() => _CaptionAppState();
}

class _CaptionAppState extends State<CaptionApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final SpeechEngine _engine;
  late final CaptionController _controller;
  late final CaptionLifecycleCoordinator _coordinator;
  late final OrientationManager _orientationManager;
  late AppThemeMode _themeMode;

  /// `null` while the initial (cheap, existence-only) check is in flight,
  /// `false` while `ModelDownloadScreen` is downloading, `true` once the
  /// model is confirmed present and `_initialize()` has been kicked off.
  bool? _modelReady;
  bool _ready = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ??
        SherpaOnnxSpeechEngine(
          mic: RecordPackageMicCapture(),
          strategy: VadChunkedSenseVoiceStrategy(),
        );
    _orientationManager = widget.orientationManager ?? OrientationManager();
    _controller = CaptionController(
      engine: _engine,
      settingsStore: widget.settingsStore ?? SharedPreferencesSettingsStore(),
      translationEngine: widget.translationEngine ?? NoopTranslationEngine(),
      mayStartCapture: () => _coordinator.mayStartCapture,
    );
    _themeMode = _controller.settings.themeMode;
    _controller.addListener(_onThemeMaybeChanged);
    _coordinator = CaptionLifecycleCoordinator(
      controller: _controller,
      engine: _engine,
      microphoneAccess:
          widget.microphoneAccess ?? const PermissionHandlerMicrophoneAccess(),
      screenAwake: widget.screenAwake ?? const WakelockScreenAwake(),
      orientationManager: _orientationManager,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkModelReady());
  }

  /// Only rebuilds `MaterialApp`'s theme on an actual day/night change, not
  /// on every partial-caption notification `CaptionController` emits.
  void _onThemeMaybeChanged() {
    if (!mounted || _controller.settings.themeMode == _themeMode) return;
    setState(() => _themeMode = _controller.settings.themeMode);
  }

  void _openSettings() {
    unawaited(
      _navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(controller: _controller),
        ),
      ),
    );
  }

  /// Existence-only check (no re-hashing — see `isSenseVoiceModelReady`'s
  /// doc comment) so a normal launch after the model is already downloaded
  /// never shows `ModelDownloadScreen`, even briefly.
  Future<void> _checkModelReady() async {
    final ready = await (widget.isModelReady ?? isSenseVoiceModelReady)();
    if (!mounted) return;
    setState(() => _modelReady = ready);
    if (ready) unawaited(_initialize());
  }

  void _onModelDownloaded() {
    if (!mounted) return;
    setState(() => _modelReady = true);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _coordinator.initialize();
    } catch (error) {
      _initializationError = '无法初始化字幕: $error';
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      _coordinator.onAppLifecycle(state).catchError((Object error) {
        debugPrint('Could not reconcile caption lifecycle: $error');
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onThemeMaybeChanged);
    unawaited(
      _coordinator.shutdown().catchError((Object error) {
        debugPrint('Could not safely dispose caption recognition: $error');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (_modelReady == null) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_modelReady == false) {
      home = ModelDownloadScreen(
        onReady: _onModelDownloaded,
        downloadModel: widget.downloadModel,
      );
    } else if (!_ready) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_initializationError != null) {
      home = Scaffold(body: Center(child: Text(_initializationError!)));
    } else {
      home = CaptionScreen(
        controller: _controller,
        coordinator: _coordinator,
        onOpenSettings: _openSettings,
      );
    }
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Loud Caption',
      theme: ThemeData.light(
        useMaterial3: true,
      ).copyWith(extensions: const [CaptionColors.light]),
      darkTheme: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(extensions: const [CaptionColors.dark]),
      themeMode: _themeMode == AppThemeMode.light
          ? ThemeMode.light
          : ThemeMode.dark,
      home: home,
    );
  }
}

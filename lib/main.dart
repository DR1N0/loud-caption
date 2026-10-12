import 'dart:async';

import 'package:flutter/material.dart';

import 'captions/caption_controller.dart';
import 'lifecycle/caption_lifecycle_coordinator.dart';
import 'lifecycle/screen_awake.dart';
import 'permissions/microphone_access.dart';
import 'settings/app_settings.dart';
import 'speech/android_vosk_engine.dart';
import 'speech/speech_engine.dart';
import 'ui/caption_screen.dart';
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
    this.microphoneAccess,
    this.screenAwake,
    this.orientationManager,
  });

  final SpeechEngine? engine;
  final SettingsStore? settingsStore;
  final MicrophoneAccess? microphoneAccess;
  final ScreenAwake? screenAwake;
  final OrientationManager? orientationManager;

  @override
  State<CaptionApp> createState() => _CaptionAppState();
}

class _CaptionAppState extends State<CaptionApp> with WidgetsBindingObserver {
  late final SpeechEngine _engine;
  late final CaptionController _controller;
  late final CaptionLifecycleCoordinator _coordinator;
  late final OrientationManager _orientationManager;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _ready = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? AndroidVoskEngine();
    _orientationManager = widget.orientationManager ?? OrientationManager();
    _controller = CaptionController(
      engine: _engine,
      settingsStore: widget.settingsStore ?? SharedPreferencesSettingsStore(),
      mayStartCapture: () => _coordinator.mayStartCapture,
    );
    _coordinator = CaptionLifecycleCoordinator(
      controller: _controller,
      engine: _engine,
      microphoneAccess:
          widget.microphoneAccess ?? const PermissionHandlerMicrophoneAccess(),
      screenAwake: widget.screenAwake ?? const WakelockScreenAwake(),
      orientationManager: _orientationManager,
    );
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _openSettings() async {
    _coordinator.onInAppSettingsOpened();
    try {
      await _navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            controller: _controller,
            onLanguageEnabled: _coordinator.setLanguageEnabled,
          ),
        ),
      );
    } finally {
      _coordinator.onInAppSettingsClosed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _coordinator.shutdown().catchError((Object error) {
        debugPrint('Could not safely dispose caption recognition: $error');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Loud Caption',
      theme: ThemeData.dark(useMaterial3: true),
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _initializationError != null
          ? Scaffold(body: Center(child: Text(_initializationError!)))
          : CaptionScreen(
              controller: _controller,
              coordinator: _coordinator,
              onOpenSettings: _openSettings,
            ),
    );
  }
}

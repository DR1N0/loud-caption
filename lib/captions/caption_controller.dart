import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/app_settings.dart';
import '../speech/speech_engine.dart';
import '../translation/translation_engine.dart';
import 'caption_line.dart';

/// The recognition lifecycle currently visible to the caption UI.
enum CaptionStatus { idle, starting, listening, switching, retrying, failed }

typedef RetryDelay = Future<void> Function(Duration duration);

/// Owns ephemeral caption state and serializes recognition lifecycle changes.
///
/// The controller deliberately does not persist caption text. Its owner must
/// await [stop] before calling the synchronous [dispose].
class CaptionController extends ChangeNotifier {
  CaptionController({
    required SpeechEngine engine,
    required SettingsStore settingsStore,
    TranslationEngine? translationEngine,
    RetryDelay? retryDelay,
    bool Function()? mayStartCapture,
  }) : _engine = engine,
       _settingsStore = settingsStore,
       _translationEngine = translationEngine,
       _retryDelay = retryDelay ?? _defaultRetryDelay,
       _mayStartCapture = mayStartCapture ?? _alwaysAllowCapture;

  static const List<Duration> _retryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  static const int _maxCommittedLinesSafetyNet = 50;

  final SpeechEngine _engine;
  final SettingsStore _settingsStore;
  final TranslationEngine? _translationEngine;
  final RetryDelay _retryDelay;
  final bool Function() _mayStartCapture;
  final List<CaptionLine> _committedLines = [];

  CaptionSettings _settings = CaptionSettings();
  StreamSubscription<SpeechEvent>? _eventSubscription;
  Future<void>? _initialization;
  Future<void>? _lifecycleTask;
  Future<void> _engineOperations = Future<void>.value();
  int _generation = 0;
  int? _sessionId;
  bool _initialized = false;
  bool _wantsListening = false;
  bool _stopConfirmed = true;
  bool _disposed = false;
  String _partialText = '';
  String? _message;
  CaptionStatus _status = CaptionStatus.idle;

  CaptionSettings get settings => _settings;
  TranslationEngine? get translationEngine => _translationEngine;
  List<CaptionLine> get committedLines =>
      List<CaptionLine>.unmodifiable(_committedLines);
  String get partialText => _partialText;
  String get displayText => [
    ..._committedLines.map((line) => line.original),
    if (_partialText.isNotEmpty) _partialText,
  ].join('\n');
  CaptionStatus get status => _status;
  String? get message => _message;
  int? get currentSessionId => _sessionId;
  bool get isStopConfirmed => _stopConfirmed;

  /// Loads preferences and subscribes before any recognition can start.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_disposed) return;
    _eventSubscription = _engine.events.listen(_acceptEvent);
    try {
      _settings = await _settingsStore.load();
    } catch (_) {
      _message = '设置加载失败';
    }
    if (_disposed) return;
    _initialized = true;
    _notify();
  }

  /// Starts recognition, retrying a failed initial start at most three times.
  Future<void> start() async {
    await initialize();
    if (_disposed || _wantsListening) return;
    if (!_stopConfirmed) {
      _status = CaptionStatus.failed;
      _message = '请先停止识别';
      _notify();
      return;
    }

    final generation = ++_generation;
    _wantsListening = true;
    _stopConfirmed = false;
    _sessionId = null;
    _status = CaptionStatus.starting;
    _message = null;
    _notify();

    late final Future<void> task;
    task = _startWithRetries(generation);
    _lifecycleTask = task;
    try {
      await task;
    } finally {
      if (identical(_lifecycleTask, task)) _lifecycleTask = null;
    }
  }

  /// Invalidates delayed retries and reports idle only after native stop wins.
  Future<void> stop() async {
    if (_disposed) return;

    final needsStop =
        _wantsListening || _sessionId != null || _status != CaptionStatus.idle;
    ++_generation;
    _wantsListening = false;
    _sessionId = null;
    if (!needsStop) {
      _stopConfirmed = true;
      _status = CaptionStatus.idle;
      _message = null;
      _notify();
      return;
    }

    _stopConfirmed = false;
    _status = CaptionStatus.failed;
    _message = '正在停止识别';
    _notify();
    try {
      await _stopEngine();
    } catch (_) {
      if (!_disposed) {
        _status = CaptionStatus.failed;
        _message = '停止识别失败';
        _notify();
      }
      rethrow;
    }
    if (_disposed) return;

    _stopConfirmed = true;
    _status = CaptionStatus.idle;
    _message = null;
    _notify();
  }

  Future<void> increaseFont() => _changeFont(increase: true);

  Future<void> decreaseFont() => _changeFont(increase: false);

  Future<void> _changeFont({required bool increase}) async {
    await initialize();
    if (_disposed) return;

    final presets = CaptionSettings.fontSizePresets;
    final current = presets.indexOf(_settings.fontSize);
    final index = increase
        ? (current + 1).clamp(0, presets.length - 1)
        : (current - 1).clamp(0, presets.length - 1);
    await _saveAndApply(_settings.withFontSize(presets[index]));
  }

  Future<void> toggleOrientation() async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withLandscape(!_settings.landscape));
  }

  Future<void> cycleMode() async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withCaptionMode(_settings.captionMode.next));
  }

  Future<void> setCaptionMode(CaptionMode mode) async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withCaptionMode(mode));
  }

  Future<void> toggleTheme() async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withThemeMode(_settings.themeMode.other));
  }

  /// Applies next time recognition starts (not a live hot-swap of an
  /// already-running session) — a simpler, lower-risk design for a setting
  /// that's set once and rarely revisited, not toggled mid-sentence.
  Future<void> setRecognitionLanguage(String language) async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withRecognitionLanguage(language));
  }

  Future<void> setWifiOnlyDownloads(bool value) async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withWifiOnlyDownloads(value));
  }

  Future<void> setTranslateAllTarget(String language) async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withTranslateAllTarget(language));
  }

  Future<void> setRoutingTarget(String sourceLanguage, String target) async {
    await initialize();
    if (_disposed) return;
    await _saveAndApply(_settings.withRoutingTarget(sourceLanguage, target));
  }

  Future<void> _saveAndApply(CaptionSettings next) async {
    try {
      await _settingsStore.save(next);
    } catch (_) {
      if (_disposed) return;
      _message = '设置保存失败';
      _notify();
      return;
    }
    if (_disposed) return;

    _settings = next;
    _message = null;
    _notify();
  }

  Future<void> _startWithRetries(int generation) async {
    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      if (!_isCurrentListeningGeneration(generation)) return;
      if (attempt > 0) {
        _status = CaptionStatus.retrying;
        _notify();
        await _retryDelay(_retryDelays[attempt - 1]);
        if (!_isCurrentListeningGeneration(generation)) return;
      }

      final outcome = await _startOnce(generation);
      if (outcome == _StartOutcome.success) {
        if (_isCurrentListeningGeneration(generation)) {
          _status = CaptionStatus.listening;
          _notify();
        }
        return;
      }
      if (outcome == _StartOutcome.cancelled) return;
    }

    if (!_isCurrentListeningGeneration(generation)) return;
    _wantsListening = false;
    _status = CaptionStatus.failed;
    _message ??= '识别引擎初始化失败';
    _notify();
  }

  Future<_StartOutcome> _startOnce(int generation) async {
    try {
      final session = await _serializeEngine(() async {
        if (!_mayStartCapture()) {
          _settleCaptureGateClosed(generation);
          return null;
        }

        final startedSession = await _engine.start(_settings.recognitionLanguage);
        if (!_isCurrentListeningGeneration(generation) || !_mayStartCapture()) {
          try {
            await _engine.stop();
          } catch (_) {
            if (_isCurrentListeningGeneration(generation)) {
              _wantsListening = false;
              _status = CaptionStatus.failed;
              _message = '停止识别失败';
              _notify();
            }
            return null;
          }
          _settleCaptureGateClosed(generation);
          return null;
        }
        return startedSession;
      });
      if (!_isCurrentListeningGeneration(generation) || session == null) {
        return _StartOutcome.cancelled;
      }
      _sessionId = session;
      return _StartOutcome.success;
    } catch (_) {
      return _isCurrentListeningGeneration(generation)
          ? _StartOutcome.failure
          : _StartOutcome.cancelled;
    }
  }

  void _settleCaptureGateClosed(int generation) {
    if (!_isCurrentListeningGeneration(generation)) return;

    ++_generation;
    _wantsListening = false;
    _sessionId = null;
    _stopConfirmed = true;
    _status = CaptionStatus.idle;
    _message = null;
    _notify();
  }

  Future<void> _stopEngine() => _serializeEngine(_engine.stop);

  Future<T> _serializeEngine<T>(Future<T> Function() operation) {
    final result = _engineOperations.then<T>((_) => operation());
    _engineOperations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _acceptEvent(SpeechEvent event) {
    if (_disposed || event.sessionId != _sessionId) return;

    switch (event.kind) {
      case SpeechEventKind.partial:
        if (_partialText == event.text) return;
        _partialText = event.text;
        _notify();
      case SpeechEventKind.finalText:
        _partialText = '';
        if (event.text.isNotEmpty) {
          final line = CaptionLine(event.text);
          _committedLines.add(line);
          // A safety net against unbounded memory growth over a long
          // session, not a visibility limit — how much history is actually
          // shown on screen is the UI's call (see CaptionScreen), based on
          // available space and font size.
          if (_committedLines.length > _maxCommittedLinesSafetyNet) {
            _committedLines.removeAt(0);
          }
          _notify();
          _startFinalTranslation(line, event.detectedLanguage);
        } else {
          _notify();
        }
      case SpeechEventKind.error:
        _message = event.text;
        _status = CaptionStatus.retrying;
        final generation = ++_generation;
        _sessionId = null;
        _notify();
        unawaited(_recoverFromError(generation));
    }
  }

  /// Cantonese (`yue`) transcribes to effectively the same written Chinese
  /// text as Mandarin — SenseVoice's own 5 recognized languages are
  /// zh/en/ja/ko/yue, and `yue` has no `translationLanguages` entry of its
  /// own — so it's routed exactly like `zh` for translation purposes rather
  /// than being permanently skipped. This only affects routing; the
  /// originally recognized text is still displayed unchanged.
  String? _translationRoutingLanguage(String? detectedLanguage) =>
      detectedLanguage == 'yue' ? 'zh' : detectedLanguage;

  /// Resolves the target language [detectedLanguage] should be translated
  /// into under the current mode, or `null` if it shouldn't be translated at
  /// all — translation is off, the engine isn't ready, the language is
  /// unrecognized, or it already maps to itself.
  String? _resolveTranslationTarget(String? detectedLanguage) {
    final engine = _translationEngine;
    if (engine == null || !engine.isLoaded) return null;
    if (_settings.captionMode == CaptionMode.captions) return null;
    final routingLanguage = _translationRoutingLanguage(detectedLanguage);
    if (routingLanguage == null ||
        !translationLanguages.contains(routingLanguage)) {
      return null;
    }
    final target = _settings.captionMode == CaptionMode.translateAll
        ? _settings.translateAllTarget
        : _settings.routingTargetFor(routingLanguage);
    return target == routingLanguage ? null : target;
  }

  /// Translates a freshly committed line. Partial (uncommitted) text is
  /// deliberately never translated — on-device inference latency can't keep
  /// up with live speech, so an earlier speculative partial-translation
  /// trigger was removed after real-device testing confirmed it fell behind.
  /// Writes each growing token back into the line's current list slot by
  /// identity, so a (rare) scroll of this line off the two-line window
  /// before translation finishes just silently stops applying further
  /// updates.
  void _startFinalTranslation(CaptionLine originalLine, String? detectedLanguage) {
    final target = _resolveTranslationTarget(detectedLanguage);
    if (target == null) return;

    final request = _translationEngine!.translate(
      text: originalLine.original,
      sourceLang: _translationRoutingLanguage(detectedLanguage)!,
      targetLang: target,
    );
    var currentLine = originalLine;
    var buffer = '';
    request.output.listen(
      (token) {
        buffer += token;
        final index = _committedLines.indexWhere(
          (line) => identical(line, currentLine),
        );
        if (index == -1) return;
        currentLine = currentLine.withTranslation(buffer);
        _committedLines[index] = currentLine;
        _notify();
      },
      onError: (Object _) {},
    );
  }

  Future<void> _recoverFromError(int generation) async {
    if (!_isCurrentListeningGeneration(generation)) return;
    try {
      await _stopEngine();
    } catch (_) {
      if (_isCurrentListeningGeneration(generation)) {
        _wantsListening = false;
        _stopConfirmed = false;
        _status = CaptionStatus.failed;
        _message = '停止识别失败';
        _notify();
      }
      return;
    }
    if (!_isCurrentListeningGeneration(generation)) return;

    // The stream failure is already one failed active session, so each bounded
    // recovery attempt waits before starting again.
    for (var attempt = 1; attempt <= _retryDelays.length; attempt++) {
      await _retryDelay(_retryDelays[attempt - 1]);
      if (!_isCurrentListeningGeneration(generation)) return;

      final outcome = await _startOnce(generation);
      if (outcome == _StartOutcome.success) {
        if (_isCurrentListeningGeneration(generation)) {
          _status = CaptionStatus.listening;
          _notify();
        }
        return;
      }
      if (outcome == _StartOutcome.cancelled) return;
    }

    if (!_isCurrentListeningGeneration(generation)) return;
    _wantsListening = false;
    _status = CaptionStatus.failed;
    _notify();
  }

  bool _isCurrentListeningGeneration(int generation) =>
      !_disposed && _wantsListening && _generation == generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (!_stopConfirmed || _wantsListening || _status != CaptionStatus.idle) {
      throw StateError(
        'CaptionController.dispose requires a successful awaited stop().',
      );
    }
    _disposed = true;
    ++_generation;
    _sessionId = null;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  static bool _alwaysAllowCapture() => true;

  static Future<void> _defaultRetryDelay(Duration duration) =>
      Future<void>.delayed(duration);
}

enum _StartOutcome { success, failure, cancelled }

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/mic_capture.dart';
import 'package:loud_caption/speech/recognition_strategy.dart';
import 'package:loud_caption/speech/sherpa_onnx_speech_engine.dart';
import 'package:loud_caption/speech/speech_engine.dart';

/// Richer, test-local fake of [MicCapture] than
/// `test/speech/mic_capture_test.dart`'s `FakeMicCapture`: [start] can be
/// gated with a [Completer] to simulate slow permission/hardware setup, and
/// [stop]/[dispose] can be made to fail on demand.
class _FakeMicCapture implements MicCapture {
  final List<String> calls = [];
  final _controller = StreamController<Uint8List>.broadcast();
  bool granted = true;
  Object? stopError;
  Object? disposeError;
  Completer<Stream<Uint8List>>? _gate;

  /// Makes the next [start] call wait on the returned completer instead of
  /// resolving immediately.
  Completer<Stream<Uint8List>> gateStart() {
    final gate = Completer<Stream<Uint8List>>();
    _gate = gate;
    return gate;
  }

  @override
  Future<bool> hasPermission() async {
    calls.add('hasPermission');
    return granted;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    calls.add('start');
    final gate = _gate;
    if (gate != null) return gate.future;
    return _controller.stream;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _controller.close();
    if (disposeError != null) throw disposeError!;
  }

  void emit(Uint8List bytes) => _controller.add(bytes);
  void emitError(Object error) => _controller.addError(error);
}

/// Richer, test-local fake of [RecognitionStrategy] than
/// `test/speech/recognition_strategy_test.dart`'s `FakeRecognitionStrategy`:
/// [start] can be gated with a [Completer] to simulate a slow first-run
/// model/isolate spawn, and [stop]/[dispose] can be made to fail on demand.
class _FakeRecognitionStrategy implements RecognitionStrategy {
  final List<String> calls = [];
  final _controller = StreamController<RecognitionOutput>.broadcast();
  var _config = {'language': 'auto'};
  Object? stopError;
  Object? disposeError;
  Completer<void>? _gate;

  Completer<void> gateStart() {
    final gate = Completer<void>();
    _gate = gate;
    return gate;
  }

  @override
  Stream<RecognitionOutput> get output => _controller.stream;

  @override
  List<SpeechEngineConfigOption> get configOptions => const [
    SpeechEngineConfigOption(
      key: 'language',
      allowedValues: ['auto', 'zh', 'en'],
      defaultValue: 'auto',
    ),
  ];

  @override
  Map<String, String> get currentConfig => _config;

  @override
  void applyConfig(Map<String, String> values) {
    calls.add('applyConfig:$values');
    _config = {..._config, ...values};
  }

  @override
  Future<void> start(String languageCode) async {
    calls.add('start:$languageCode');
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  @override
  void acceptAudio(Float32List samples, int sampleRate) {
    calls.add('acceptAudio:${samples.length}@$sampleRate');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _controller.close();
    if (disposeError != null) throw disposeError!;
  }

  void emit(RecognitionOutput value) => _controller.add(value);
  void emitError(Object error) => _controller.addError(error);
}

void main() {
  late _FakeMicCapture mic;
  late _FakeRecognitionStrategy strategy;
  late SherpaOnnxSpeechEngine engine;

  setUp(() {
    mic = _FakeMicCapture();
    strategy = _FakeRecognitionStrategy();
    engine = SherpaOnnxSpeechEngine(mic: mic, strategy: strategy);
  });

  test('start() throws StateError if already active or pending', () async {
    await engine.start('en');
    await expectLater(engine.start('en'), throwsA(isA<StateError>()));

    await engine.stop();
    final gate = mic.gateStart();
    final pendingStart = engine.start('en');
    await expectLater(engine.start('en'), throwsA(isA<StateError>()));

    gate.complete(const Stream.empty());
    await expectLater(pendingStart, completes);
    await engine.dispose();
  });

  test('session IDs increase monotonically and are returned from start()', () async {
    final first = await engine.start('en');
    await engine.stop();
    final second = await engine.start('en');
    await engine.stop();
    final third = await engine.start('en');

    expect(second, greaterThan(first));
    expect(third, greaterThan(second));
    await engine.dispose();
  });

  group('isSessionActive', () {
    test('false immediately for a non-current id without touching mic/strategy', () async {
      final active = await engine.start('en');
      mic.calls.clear();
      strategy.calls.clear();

      expect(await engine.isSessionActive(active + 999), isFalse);
      expect(mic.calls, isEmpty);
      expect(strategy.calls, isEmpty);

      await engine.dispose();
    });

    test('true for the current id', () async {
      final active = await engine.start('en');
      expect(await engine.isSessionActive(active), isTrue);
      await engine.dispose();
    });

    test('flips to false after an error event for that session', () async {
      final active = await engine.start('en');
      expect(await engine.isSessionActive(active), isTrue);

      strategy.emitError('boom');
      await Future<void>.delayed(Duration.zero);

      expect(await engine.isSessionActive(active), isFalse);
      await engine.dispose();
    });
  });

  test(
    'stop() while start() awaits a slow mic cancels the pending start without '
    'starting the strategy or forwarding audio',
    () async {
      final gate = mic.gateStart();
      final received = <SpeechEvent>[];
      final subscription = engine.events.listen(received.add);

      final start = engine.start('en');
      await Future<void>.delayed(Duration.zero);
      await engine.stop();
      gate.complete(mic._controller.stream);

      await expectLater(start, throwsA(isA<StateError>()));
      // The strategy's expensive isolate/model spawn is never touched; its
      // `stop` may still fire as part of `stop()`'s unconditional best-effort
      // cleanup of both collaborators.
      expect(strategy.calls, isNot(contains('start:en')));
      expect(mic.calls, containsAllInOrder(['hasPermission', 'start', 'stop']));

      mic.emit(Uint8List.fromList([1, 2]));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      await subscription.cancel();
      await engine.dispose();
    },
  );

  test(
    'stop() while start() awaits a slow strategy cancels the pending start and '
    'stops both mic and strategy',
    () async {
      final gate = strategy.gateStart();
      final received = <SpeechEvent>[];
      final subscription = engine.events.listen(received.add);

      final start = engine.start('en');
      await Future<void>.delayed(Duration.zero);
      await engine.stop();
      gate.complete();

      await expectLater(start, throwsA(isA<StateError>()));
      expect(mic.calls.where((call) => call == 'stop').length, greaterThanOrEqualTo(1));
      expect(strategy.calls.where((call) => call == 'stop').length, greaterThanOrEqualTo(1));

      strategy.emit(const RecognitionOutput(text: 'late', isFinal: true));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      await subscription.cancel();
      await engine.dispose();
    },
  );

  group('dispose', () {
    test('is idempotent, stops any active session, and cleans up exactly once', () async {
      await engine.start('en');
      await engine.dispose();
      await engine.dispose();

      expect(mic.calls.where((call) => call == 'dispose').length, 1);
      expect(strategy.calls.where((call) => call == 'dispose').length, 1);
    });

    test('closes events and throws StateError for calls after', () async {
      final done = Completer<void>();
      engine.events.listen(null, onDone: done.complete);

      await engine.dispose();
      await done.future;

      await expectLater(engine.start('en'), throwsA(isA<StateError>()));
    });

    test(
      'surfaces a failed stop but still finishes closing events',
      () async {
        await engine.start('en');
        mic.stopError = StateError('stop failed');
        final done = Completer<void>();
        engine.events.listen(null, onDone: done.complete);

        await expectLater(engine.dispose(), throwsA(isA<StateError>()));
        await done.future;

        expect(mic.calls.where((call) => call == 'dispose').length, 1);
        expect(strategy.calls.where((call) => call == 'dispose').length, 1);
      },
    );

    test('stops a pending start and compensates the eventual mic readiness', () async {
      final gate = mic.gateStart();
      final start = engine.start('en');
      await Future<void>.delayed(Duration.zero);

      await engine.dispose();
      gate.complete(mic._controller.stream);

      await expectLater(start, throwsA(isA<StateError>()));
      expect(mic.calls.where((call) => call == 'stop').length, greaterThanOrEqualTo(1));
    });
  });

  test(
    'a final RecognitionOutput becomes a finalText SpeechEvent tagged with the '
    'current session id; a stray output after invalidation is dropped',
    () async {
      final received = <SpeechEvent>[];
      final subscription = engine.events.listen(received.add);

      final sessionId = await engine.start('en');
      strategy.emit(const RecognitionOutput(text: '你好', isFinal: true));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.kind, SpeechEventKind.finalText);
      expect(received.single.text, '你好');
      expect(received.single.sessionId, sessionId);

      // Invalidate the session (without disposing, which would close the
      // strategy's own output stream and make emitting a stray event moot).
      await engine.stop();
      strategy.emit(const RecognitionOutput(text: 'stray', isFinal: true));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      await subscription.cancel();
      await engine.dispose();
    },
  );

  test(
    'a mic-stream or strategy-stream error for the active session becomes an '
    'error SpeechEvent; a stray error for an invalidated session is dropped',
    () async {
      final received = <SpeechEvent>[];
      final subscription = engine.events.listen(received.add);

      final sessionId = await engine.start('en');
      mic.emitError('mic broke');
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.kind, SpeechEventKind.error);
      expect(received.single.sessionId, sessionId);

      await engine.stop();
      final secondSessionId = await engine.start('en');
      strategy.emitError('strategy broke');
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received.last.kind, SpeechEventKind.error);
      expect(received.last.sessionId, secondSessionId);

      await subscription.cancel();
      await engine.dispose();
    },
  );

  test('applyConfig/configOptions/currentConfig pass through to the strategy', () async {
    expect(engine.configOptions, strategy.configOptions);
    expect(engine.currentConfig, strategy.currentConfig);

    await engine.applyConfig({'language': 'zh'});

    expect(strategy.calls, contains('applyConfig:{language: zh}'));
    expect(engine.currentConfig['language'], 'zh');

    await engine.dispose();
  });
}

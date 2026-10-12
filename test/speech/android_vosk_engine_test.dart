import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/android_vosk_engine.dart';
import 'package:loud_caption/speech/speech_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only current nonempty partial and final text become speech events', () {
    expect(
      parseNativeEvent({
        'sessionId': 3,
        'kind': 'partial',
        'raw': '{"partial":"你好"}',
      }, 3)?.text,
      '你好',
    );
    expect(
      parseNativeEvent({
        'sessionId': 3,
        'kind': 'final',
        'raw': '{"text":"hello"}',
      }, 3)?.kind,
      SpeechEventKind.finalText,
    );
    expect(
      parseNativeEvent({
        'sessionId': 3,
        'kind': 'partial',
        'raw': '{"partial":" "}',
      }, 3),
      isNull,
    );
    expect(
      parseNativeEvent({
        'sessionId': 2,
        'kind': 'final',
        'raw': '{"text":"old"}',
      }, 3),
      isNull,
    );
    expect(
      parseNativeEvent({
        'sessionId': 3,
        'kind': 'error',
        'raw': 'mic busy',
      }, 3)?.kind,
      SpeechEventKind.error,
    );
  });

  test('malformed JSON becomes an error and invalid events are rejected', () {
    final malformed = parseNativeEvent({
      'sessionId': 3,
      'kind': 'partial',
      'raw': '{not json',
    }, 3);

    expect(malformed?.kind, SpeechEventKind.error);
    expect(malformed?.sessionId, 3);
    expect(parseNativeEvent(null, 3), isNull);
    expect(
      parseNativeEvent({
        'sessionId': '3',
        'kind': 'partial',
        'raw': '{"partial":"text"}',
      }, 3),
      isNull,
    );
    expect(
      parseNativeEvent({
        'sessionId': 3,
        'kind': 'unknown',
        'raw': 'ignored',
      }, 3),
      isNull,
    );
  });

  test(
    'subscribes before start, forwards language, and filters early stale events',
    () async {
      final channels = _TestChannels('forwards-language');
      final received = <SpeechEvent>[];
      Map<String, Object?>? startArguments;

      channels.installMethodHandler((call) async {
        if (call.method == 'start') {
          startArguments = Map<String, Object?>.from(call.arguments as Map);
          await channels.sendEvent({
            'sessionId': 10,
            'kind': 'partial',
            'raw': '{"partial":"stale"}',
          });
          await channels.sendEvent({
            'sessionId': 11,
            'kind': 'partial',
            'raw': '{"partial":"early"}',
          });
          return 11;
        }
        expect(call.method, 'stop');
        return null;
      });
      addTearDown(channels.dispose);

      final engine = channels.createEngine();
      final subscription = engine.events.listen(received.add);
      addTearDown(subscription.cancel);

      expect(await engine.start('en'), 11);
      await Future<void>.delayed(Duration.zero);
      expect(startArguments, {'language': 'en'});
      expect(received.map((event) => event.text), ['early']);

      await engine.stop();
      await engine.dispose();
    },
  );

  test(
    'keeps only the latest 16 early events while start is pending',
    () async {
      final channels = _TestChannels('bounded-early-events');
      final received = <SpeechEvent>[];
      channels.installMethodHandler((call) async {
        if (call.method == 'start') {
          for (var index = 0; index < 17; index++) {
            await channels.sendEvent({
              'sessionId': 12,
              'kind': 'partial',
              'raw': '{"partial":"$index"}',
            });
          }
          return 12;
        }
        return null;
      });
      addTearDown(channels.dispose);

      final engine = channels.createEngine();
      final subscription = engine.events.listen(received.add);
      addTearDown(subscription.cancel);

      await engine.start('en');
      await Future<void>.delayed(Duration.zero);

      expect(
        received.map((event) => event.text),
        List.generate(16, (index) => '${index + 1}'),
      );

      await engine.stop();
      await engine.dispose();
    },
  );

  test(
    'reports native session health only for the Dart-active session',
    () async {
      final channels = _TestChannels('session-health');
      final healthArguments = <Object?>[];
      var healthReply = true;
      channels.installMethodHandler((call) async {
        if (call.method == 'start') return 41;
        if (call.method == 'isSessionActive') {
          healthArguments.add(call.arguments);
          return healthReply;
        }
        return null;
      });
      addTearDown(channels.dispose);

      final engine = channels.createEngine();
      expect(await engine.start('en'), 41);
      expect(await engine.isSessionActive(41), isTrue);
      healthReply = false;
      expect(await engine.isSessionActive(41), isFalse);
      await engine.stop();
      expect(await engine.isSessionActive(41), isFalse);
      expect(await engine.isSessionActive(40), isFalse);

      expect(healthArguments, [
        {'sessionId': 41},
        {'sessionId': 41},
      ]);
      await engine.dispose();
    },
  );

  test('late health reply cannot resurrect a stopped session', () async {
    final channels = _TestChannels('late-health');
    final healthReply = Completer<bool>();
    channels.installMethodHandler((call) async {
      if (call.method == 'start') return 41;
      if (call.method == 'stop') return null;
      expect(call.method, 'isSessionActive');
      expect(call.arguments, {'sessionId': 41});
      return healthReply.future;
    });
    addTearDown(channels.dispose);

    final engine = channels.createEngine();
    expect(await engine.start('zh'), 41);
    final check = engine.isSessionActive(41);
    await engine.stop();
    healthReply.complete(true);
    expect(await check, isFalse);
    await engine.dispose();
  });

  test('rejects malformed native session-health replies', () async {
    final channels = _TestChannels('malformed-session-health');
    channels.installMethodHandler((call) async {
      if (call.method == 'start') return 45;
      if (call.method == 'isSessionActive') return null;
      return null;
    });
    addTearDown(channels.dispose);

    final engine = channels.createEngine();
    await engine.start('en');

    await expectLater(engine.isSessionActive(45), throwsA(isA<StateError>()));
    await engine.stop();
    await engine.dispose();
  });

  test('surfaces a platform stream error for the active session', () async {
    final channels = _TestChannels('stream-error');
    final received = <SpeechEvent>[];
    channels.installMethodHandler(
      (call) async => call.method == 'start' ? 19 : null,
    );
    addTearDown(channels.dispose);

    final engine = channels.createEngine();
    final subscription = engine.events.listen(received.add);
    addTearDown(subscription.cancel);

    await engine.start('en');
    await channels.sendStreamError('platform failure');
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.kind, SpeechEventKind.error);
    expect(received.single.text, '语音通道错误');
    expect(received.single.sessionId, 19);

    await engine.stop();
    await engine.dispose();
  });

  test(
    'stops a late native session after stop while start is pending',
    () async {
      final channels = _TestChannels('stop-while-starting');
      final startReply = Completer<int>();
      final startCalled = Completer<void>();
      final received = <SpeechEvent>[];
      var stopCalls = 0;
      channels.installMethodHandler((call) {
        if (call.method == 'start') {
          startCalled.complete();
          return startReply.future;
        }
        stopCalls++;
        return Future<void>.value();
      });
      addTearDown(channels.dispose);

      final engine = channels.createEngine();
      final subscription = engine.events.listen(received.add);
      addTearDown(subscription.cancel);

      final start = engine.start('en');
      await startCalled.future;
      await engine.stop();
      startReply.complete(23);

      await expectLater(start, throwsA(isA<StateError>()));
      await channels.sendEvent({
        'sessionId': 23,
        'kind': 'partial',
        'raw': '{"partial":"late"}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(stopCalls, 2);
      expect(received, isEmpty);
      await engine.dispose();
    },
  );

  test('keeps the start fence when compensating late stop fails', () async {
    final channels = _TestChannels('failed-late-stop');
    final firstStartReply = Completer<int>();
    final firstStartCalled = Completer<void>();
    final received = <SpeechEvent>[];
    var startCalls = 0;
    var stopCalls = 0;
    channels.installMethodHandler((call) {
      if (call.method == 'start') {
        startCalls++;
        if (startCalls == 1) {
          firstStartCalled.complete();
          return firstStartReply.future;
        }
        return Future<int>.value(32);
      }
      stopCalls++;
      if (stopCalls == 2) {
        return Future<Object?>.error(
          PlatformException(code: 'stop_failed', message: 'retry required'),
        );
      }
      return Future<void>.value();
    });
    addTearDown(channels.dispose);

    final engine = channels.createEngine();
    final subscription = engine.events.listen(received.add);
    addTearDown(subscription.cancel);

    final firstStart = engine.start('en');
    await firstStartCalled.future;
    await engine.stop();
    firstStartReply.complete(31);

    await expectLater(firstStart, throwsA(isA<PlatformException>()));
    await expectLater(engine.start('en'), throwsA(isA<StateError>()));
    expect(startCalls, 1);

    await engine.stop();
    expect(stopCalls, 3);
    expect(await engine.start('en'), 32);
    await channels.sendEvent({
      'sessionId': 31,
      'kind': 'partial',
      'raw': '{"partial":"stale"}',
    });
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await engine.stop();
    await engine.dispose();
  });

  test(
    'dispose exposes its failed stop and compensates a late native start',
    () async {
      final channels = _TestChannels('dispose-stop-failure');
      final startReply = Completer<int>();
      final startCalled = Completer<void>();
      final done = Completer<void>();
      final received = <SpeechEvent>[];
      var stopCalls = 0;
      channels.installMethodHandler((call) {
        if (call.method == 'start') {
          startCalled.complete();
          return startReply.future;
        }
        stopCalls++;
        if (stopCalls == 1) {
          return Future<Object?>.error(
            PlatformException(code: 'stop_failed', message: 'retry required'),
          );
        }
        return Future<void>.value();
      });
      addTearDown(channels.dispose);

      final engine = channels.createEngine();
      final subscription = engine.events.listen(
        received.add,
        onDone: done.complete,
      );

      final start = engine.start('en');
      await startCalled.future;
      await expectLater(engine.dispose(), throwsA(isA<PlatformException>()));
      await done.future;

      startReply.complete(41);
      await expectLater(start, throwsA(isA<StateError>()));
      await channels.sendEvent({
        'sessionId': 41,
        'kind': 'partial',
        'raw': '{"partial":"late"}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(stopCalls, 2);
      expect(received, isEmpty);
      await subscription.cancel();
    },
  );

  test(
    'stops a late native session after dispose without adding events',
    () async {
      final channels = _TestChannels('dispose-while-starting');
      final startReply = Completer<int>();
      final startCalled = Completer<void>();
      final done = Completer<void>();
      final received = <SpeechEvent>[];
      var stopCalls = 0;
      channels.installMethodHandler((call) {
        if (call.method == 'start') {
          startCalled.complete();
          return startReply.future;
        }
        stopCalls++;
        return Future<void>.value();
      });
      addTearDown(channels.dispose);

      final engine = channels.createEngine();
      final subscription = engine.events.listen(
        received.add,
        onDone: done.complete,
      );

      final start = engine.start('en');
      await startCalled.future;
      await engine.dispose();
      await done.future;

      startReply.complete(29);
      await expectLater(start, throwsA(isA<StateError>()));
      await channels.sendEvent({
        'sessionId': 29,
        'kind': 'partial',
        'raw': '{"partial":"late"}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(stopCalls, 2);
      expect(received, isEmpty);
      await subscription.cancel();
    },
  );
}

class _TestChannels {
  _TestChannels(String suffix)
    : methods = MethodChannel('test.loudcaption/$suffix/methods'),
      eventChannel = EventChannel('test.loudcaption/$suffix/events'),
      eventMethods = MethodChannel('test.loudcaption/$suffix/events');

  final MethodChannel methods;
  final EventChannel eventChannel;
  final MethodChannel eventMethods;
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final _codec = const StandardMethodCodec();

  AndroidVoskEngine createEngine() =>
      AndroidVoskEngine(methodChannel: methods, eventChannel: eventChannel);

  void installMethodHandler(Future<Object?> Function(MethodCall call) handler) {
    _messenger.setMockMethodCallHandler(methods, handler);
    _messenger.setMockMethodCallHandler(eventMethods, (call) async {
      expect(call.method, anyOf('listen', 'cancel'));
      return null;
    });
  }

  Future<void> sendEvent(Map<String, Object?> event) =>
      _sendEnvelope(_codec.encodeSuccessEnvelope(event));

  Future<void> sendStreamError(String message) => _sendEnvelope(
    _codec.encodeErrorEnvelope(code: 'error', message: message),
  );

  Future<void> _sendEnvelope(ByteData envelope) async {
    final complete = Completer<void>();
    await _messenger.handlePlatformMessage(
      eventChannel.name,
      envelope,
      (_) => complete.complete(),
    );
    await complete.future;
  }

  void dispose() {
    _messenger.setMockMethodCallHandler(methods, null);
    _messenger.setMockMethodCallHandler(eventMethods, null);
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/mic_capture.dart';

/// Hand-written fake for tests that exercise code depending on [MicCapture]
/// without touching a real microphone or `package:record`. Copied into
/// Task 6's tests rather than shared via a `test/fakes/` directory, per this
/// repo's convention of per-test-file fakes.
class FakeMicCapture implements MicCapture {
  final _controller = StreamController<Uint8List>.broadcast();
  final List<String> calls = [];
  bool granted = true;

  @override
  Future<bool> hasPermission() async {
    calls.add('hasPermission');
    return granted;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    calls.add('start');
    return _controller.stream;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _controller.close();
  }

  void emit(Uint8List bytes) => _controller.add(bytes);
}

void main() {
  test('fake MicCapture drives audio bytes through the real interface shape', () async {
    final mic = FakeMicCapture();
    expect(await mic.hasPermission(), isTrue);

    final stream = await mic.start();
    final received = stream.first;
    mic.emit(Uint8List.fromList([1, 2, 3]));
    expect(await received, [1, 2, 3]);

    await mic.stop();
    await mic.dispose();
    expect(mic.calls, ['hasPermission', 'start', 'stop', 'dispose']);
  });
}

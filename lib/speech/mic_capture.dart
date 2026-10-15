import 'dart:typed_data';

import 'package:record/record.dart';

/// A thin abstraction over `package:record` so engine tests never touch a
/// real microphone.
///
/// The real [RecordPackageMicCapture] implementation is written in Task 6
/// alongside the engine that uses it, since it has no independent logic
/// worth isolating here.
abstract interface class MicCapture {
  Future<bool> hasPermission();

  Future<Stream<Uint8List>> start();

  Future<void> stop();

  Future<void> dispose();
}

/// The real [MicCapture], backed by `package:record`'s [AudioRecorder].
///
/// Always captures raw 16-bit PCM mono audio at 16 kHz — the sample format
/// both the VAD and SenseVoice models require — so callers never need to
/// transcode.
class RecordPackageMicCapture implements MicCapture {
  RecordPackageMicCapture({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
  );

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(_config);

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

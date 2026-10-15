import 'dart:typed_data';

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

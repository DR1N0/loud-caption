import 'package:wakelock_plus/wakelock_plus.dart';

/// Platform boundary that keeps the display awake while captions are listening.
abstract interface class ScreenAwake {
  Future<void> enable();
  Future<void> disable();
}

/// Production wakelock implementation.
class WakelockScreenAwake implements ScreenAwake {
  const WakelockScreenAwake();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

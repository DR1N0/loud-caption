import 'package:flutter/services.dart';

const _channel = MethodChannel('loud_caption/device_status');

/// Whether the device's currently active network connection is Wi-Fi.
/// Backed by `MainActivity.kt`'s own tiny platform channel rather than a
/// third-party connectivity plugin — see that file's doc comment for why.
Future<bool> isWifiConnected() async =>
    (await _channel.invokeMethod<bool>('isWifiConnected')) ?? false;

/// Free space, in bytes, on the same storage partition model downloads
/// actually write to (app-private internal storage).
Future<int> availableDiskSpaceBytes() async =>
    (await _channel.invokeMethod<int>('availableDiskSpaceBytes')) ?? 0;

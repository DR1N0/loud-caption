import 'package:permission_handler/permission_handler.dart';

/// The microphone states the caption screen must distinguish.
enum MicAccessState { granted, denied, permanentlyDenied }

/// Platform boundary for checking and requesting microphone access.
abstract interface class MicrophoneAccess {
  Future<MicAccessState> status();
  Future<MicAccessState> request();
  Future<bool> openSettings();
}

/// Maps permission_handler status values to the smaller UI state model.
MicAccessState mapPermission(PermissionStatus value) {
  if (value.isGranted) return MicAccessState.granted;
  if (value.isPermanentlyDenied) return MicAccessState.permanentlyDenied;
  return MicAccessState.denied;
}

/// Production microphone-permission implementation for Android.
class PermissionHandlerMicrophoneAccess implements MicrophoneAccess {
  const PermissionHandlerMicrophoneAccess();

  @override
  Future<MicAccessState> status() async =>
      mapPermission(await Permission.microphone.status);

  @override
  Future<MicAccessState> request() async =>
      mapPermission(await Permission.microphone.request());

  @override
  Future<bool> openSettings() => openAppSettings();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/permissions/microphone_access.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('mapPermission', () {
    test('maps granted permission', () {
      expect(mapPermission(PermissionStatus.granted), MicAccessState.granted);
    });

    test('maps permanently denied permission to settings-only state', () {
      expect(
        mapPermission(PermissionStatus.permanentlyDenied),
        MicAccessState.permanentlyDenied,
      );
    });

    test('maps restricted and denied permissions to denied', () {
      expect(mapPermission(PermissionStatus.denied), MicAccessState.denied);
      expect(mapPermission(PermissionStatus.restricted), MicAccessState.denied);
    });
  });
}

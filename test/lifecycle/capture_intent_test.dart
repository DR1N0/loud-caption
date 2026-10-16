import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/lifecycle/capture_intent.dart';
import 'package:loud_caption/permissions/microphone_access.dart';

void main() {
  test('temporary inactivity does not withdraw capture', () {
    final active = CaptureIntent(
      presence: CapturePresence.foreground,
      access: MicAccessState.granted,
      permissionFresh: true,
    );

    expect(active.captureDesired, isTrue);
    expect(active.mayStartCapture, isTrue);

    final unfocused = active.copyWith(
      presence: CapturePresence.temporarilyInactive,
    );
    expect(unfocused.captureDesired, isTrue);
    expect(unfocused.mayStartCapture, isFalse);
    expect(active.copyWith(permissionFresh: false).captureDesired, isTrue);
    expect(active.copyWith(permissionFresh: false).mayStartCapture, isFalse);
    expect(
      active.copyWith(presence: CapturePresence.background).captureDesired,
      isFalse,
    );
    expect(active.copyWith(stopFailed: true).mayStartCapture, isFalse);
  });

  test('copyWith preserves omitted intent fields', () {
    final intent = CaptureIntent(
      presence: CapturePresence.temporarilyInactive,
      access: MicAccessState.permanentlyDenied,
      permissionFresh: false,
      terminal: true,
      stopFailed: true,
    );

    final changed = intent.copyWith(stopFailed: false);

    expect(changed.presence, intent.presence);
    expect(changed.access, intent.access);
    expect(changed.permissionFresh, intent.permissionFresh);
    expect(changed.terminal, intent.terminal);
    expect(changed.stopFailed, isFalse);
  });
}

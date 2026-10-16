import '../permissions/microphone_access.dart';

/// Whether the app can keep an existing native capture session alive.
enum CapturePresence { foreground, temporarilyInactive, background }

/// Immutable, synchronous statement of the capture lifecycle's desired state.
class CaptureIntent {
  const CaptureIntent({
    required this.presence,
    required this.access,
    required this.permissionFresh,
    this.terminal = false,
    this.stopFailed = false,
  });

  final CapturePresence presence;
  final MicAccessState? access;
  final bool permissionFresh;
  final bool terminal;
  final bool stopFailed;

  /// An already-running session may continue unless capture is truly withdrawn.
  bool get captureDesired =>
      presence != CapturePresence.background &&
      access == MicAccessState.granted &&
      !terminal &&
      !stopFailed;

  /// A new native start additionally requires foreground and a fresh grant.
  bool get mayStartCapture =>
      captureDesired &&
      presence == CapturePresence.foreground &&
      permissionFresh;

  CaptureIntent copyWith({
    CapturePresence? presence,
    MicAccessState? access,
    bool? permissionFresh,
    bool? terminal,
    bool? stopFailed,
  }) => CaptureIntent(
    presence: presence ?? this.presence,
    access: access ?? this.access,
    permissionFresh: permissionFresh ?? this.permissionFresh,
    terminal: terminal ?? this.terminal,
    stopFailed: stopFailed ?? this.stopFailed,
  );
}

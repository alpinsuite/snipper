/// What kind of capture was asked for.
enum CaptureMode {
  /// Freeze the desktop and drag out a rectangle.
  region,

  /// Take a whole screen with no selection step.
  fullScreen,
}

/// One request to capture, as the interface expresses it.
class CaptureRequest {
  const CaptureRequest({
    required this.mode,
    this.delay = Duration.zero,
    this.displayId,
  });

  final CaptureMode mode;

  /// How long to wait before taking the shot, so a menu can be opened first.
  final Duration delay;

  /// Which monitor [CaptureMode.fullScreen] means, or null for the one the
  /// pointer is on. Ignored for [CaptureMode.region], which spans everything.
  final String? displayId;

  @override
  String toString() =>
      'CaptureRequest(${mode.name}, ${delay.inSeconds}s'
      '${displayId == null ? '' : ', $displayId'})';
}

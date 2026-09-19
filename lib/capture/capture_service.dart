import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import '../model/display.dart';
import '../model/raster_frame.dart';
import 'linux_capture.dart';
import 'windows_capture.dart';

/// The platform failed to hand over a screenshot.
///
/// Carries a sentence the interface can show. Everything that can go wrong here
/// is environmental — a portal that is not installed, a display server that
/// refused, a monitor unplugged between enumerating and capturing — so the
/// application says what happened and stays open rather than crashing.
class CaptureException implements Exception {
  const CaptureException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'CaptureException: $message${cause == null ? '' : ' ($cause)'}';
}

/// The user backed out of a selection the desktop was running.
///
/// Only the portal path can raise it: there the region is chosen in the
/// desktop's own interface, and closing that is a cancel, not a failure. The
/// controller ends the capture quietly instead of reporting an error.
class CaptureCancelled implements Exception {
  const CaptureCancelled();

  @override
  String toString() => 'CaptureCancelled';
}

/// Taking pixels off the screen.
///
/// Two implementations, chosen by platform and never by feature detection at
/// the call site — the controller drives this interface and knows nothing about
/// either.
abstract class CaptureService {
  /// The implementation for the platform this is running on.
  factory CaptureService.forPlatform() {
    if (Platform.isWindows) return WindowsCaptureService();
    if (Platform.isLinux) return LinuxCaptureService();
    throw CaptureException(
      'Screen capture is not implemented on ${Platform.operatingSystem}.',
    );
  }

  /// Every monitor and the rectangle enclosing them, in physical pixels.
  Future<VirtualDesktop> enumerateDisplays();

  /// The whole virtual desktop as one image.
  ///
  /// Returns the frame together with the physical rectangle it covers, because
  /// the two are useless apart: the rectangle's origin is what turns a screen
  /// coordinate into an index into these pixels, and it is routinely negative.
  Future<CaptureResult> captureVirtualDesktop();

  /// Whether this platform lets the application put its own window over the
  /// desktop to run the selection.
  ///
  /// False under Wayland, where a client cannot position itself and the
  /// compositor has to be asked to do the selection instead.
  bool get canDrawOwnOverlay;

  /// Hands the whole selection to the desktop and returns what the user chose.
  ///
  /// The counterpart of [canDrawOwnOverlay] being false, and called only then.
  /// The frame that comes back is already the region, so there is nothing left
  /// to crop. Throws [CaptureCancelled] when the user closes the desktop's
  /// interface without choosing.
  Future<CaptureResult> captureSelectedByDesktop();

  void dispose() {}
}

/// A captured frame and where on the desktop it came from.
class CaptureResult {
  const CaptureResult({
    required this.frame,
    required this.bounds,
    required this.desktop,
  });

  /// The pixels. Owned by whoever receives this — dispose it.
  final ui.Image frame;

  /// The physical rectangle [frame] covers. `bounds.size` is the frame's size
  /// in pixels; `bounds.topLeft` is where it sits on the desktop and may be
  /// negative.
  final ui.Rect bounds;

  final VirtualDesktop desktop;
}

/// Turns a normalised raster into a `ui.Image`.
///
/// Shared by both backends so the decode happens once, in one place, with the
/// packing rules [RasterFrame] enforces already applied.
Future<ui.Image> decodeFrame(RasterFrame frame) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    frame.toPackedBgra8888(),
    frame.width,
    frame.height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return completer.future;
}

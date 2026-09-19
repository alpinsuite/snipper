import 'dart:io';
import 'dart:ui' as ui;

import 'overlay_window_linux.dart';
import 'overlay_window_windows.dart';

/// Turning the application's own window into a fullscreen overlay, and turning
/// it back.
///
/// The region selection is drawn on a frozen picture of the desktop inside this
/// window rather than on a transparent window over a live one — Flutter's
/// desktop transparency support is thin and inconsistent, and a frozen frame is
/// what makes the selection exact anyway, because the pixels are already in
/// hand before the pointer moves.
///
/// [leave] is the highest-stakes call in the application. A window left
/// frameless, topmost and the size of the desktop cannot be recovered from
/// inside the application, so every path out of a capture — success, cancel and
/// failure alike — has to reach it.
abstract class OverlayWindow {
  factory OverlayWindow.forPlatform() {
    if (Platform.isWindows) return WindowsOverlayWindow();
    return LinuxOverlayWindow();
  }

  /// Places the window over [physicalBounds], borderless and above everything.
  Future<void> enter(ui.Rect physicalBounds);

  /// Puts back the frame, the placement and the z-order [enter] changed.
  Future<void> leave();

  /// Keeps this window out of the screenshot it is about to take.
  ///
  /// Windows can do this without hiding anything, which removes the flicker and
  /// the settle delay entirely. Elsewhere it means hiding the window and
  /// waiting, so callers must await it and not assume it is instant.
  Future<void> hideFromCapture();

  /// Undoes [hideFromCapture].
  Future<void> showAfterCapture();
}

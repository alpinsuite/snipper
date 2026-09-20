import 'dart:ui' as ui;

import 'package:window_manager/window_manager.dart';

import 'overlay_window.dart';

/// The Linux overlay, through GTK.
///
/// Two things about this that are not obvious from the `window_manager` API:
///
/// - **`setFullScreen` cannot be used.** It is `gtk_window_fullscreen`, which
///   fullscreens onto one monitor and will never span a multi-monitor desktop.
///   Frameless plus explicit bounds plus keep-above is the only arrangement
///   that covers everything.
/// - **`setBounds` is in GTK coordinates on Linux, not physical pixels.** The
///   plugin passes the values straight to `gtk_window_move` and
///   `gtk_window_resize` with no scaling, where the Windows implementation
///   multiplies by the device pixel ratio first. So a physical rectangle has to
///   be divided here and not there. That asymmetry works perfectly at 1x and
///   breaks on a HiDPI laptop, which is why it is written down.
///
/// Under Wayland none of this applies: a client cannot position itself at all,
/// and the compositor is asked to run the selection instead. That path does not
/// come through here.
class LinuxOverlayWindow implements OverlayWindow {
  ui.Rect? _savedBounds;
  bool _hidden = false;

  @override
  Future<void> enter(ui.Rect physicalBounds) async {
    _savedBounds ??= await windowManager.getBounds();

    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlwaysOnTop(true);
    // Fullscreen, rather than setting the bounds to [physicalBounds]. Resizing
    // the window by hand moves it out from under the engine, which then waits
    // for a frame at the new size, never gets one, and hands the next click to
    // a view with nothing behind it — a segfault, reproducibly, on the only
    // flow this application is for. Asking the window manager to fullscreen
    // the window goes through the path GTK and the engine agree about.
    //
    // The cost is that fullscreen covers the monitor the window is on, so a
    // selection cannot cross onto a second screen. Windows, which can place
    // its own overlay, still spans the whole desktop.
    await windowManager.setFullScreen(true);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> leave() async {
    await windowManager.setFullScreen(false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    // The application draws its own title bar, so `hidden` is the ordinary
    // state to go back to rather than `normal`.
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    final saved = _savedBounds;
    if (saved != null) {
      await windowManager.setBounds(saved);
      _savedBounds = null;
    }
  }

  @override
  Future<void> hideFromCapture() async {
    _hidden = true;
    await windowManager.hide();
    // Long enough for the compositor to have finished repainting what was
    // behind the window. Shorter than this and the application appears, as a
    // ghost, in its own screenshot.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  @override
  Future<void> showAfterCapture() async {
    if (!_hidden) return;
    _hidden = false;
    await windowManager.show();
    await windowManager.focus();
  }
}

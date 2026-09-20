import 'dart:ui' as ui;

import 'package:window_manager/window_manager.dart';

import 'overlay_window.dart';

/// The Linux overlay, through GTK.
///
/// Two things about this that are not obvious from the `window_manager` API:
///
/// - **The overlay covers one monitor, not the whole desktop.** Frameless plus
///   explicit bounds would cover everything, and is what this did first, but
///   `setBounds` moves the window out from under the engine: it then waits a
///   second for a frame at the new size, never gets one, and the overlay is a
///   screen-sized rectangle of nothing that segfaults on the first click into
///   it. That happened on every run, from the hotkey and from `--region`
///   alike. `setFullScreen` is `gtk_window_fullscreen`, which the engine
///   follows, and the price is that it fullscreens onto the monitor the window
///   is on. A selection cannot cross onto a second screen here; on Windows,
///   which places its own overlay, it still can.
/// - **The window has to be on screen before it is resized**, for the same
///   reason: `hideFromCapture` has just hidden it, and a hidden window
///   produces no frames to grow from. Both halves are needed — showing it
///   first with `setBounds` still crashes, and `setFullScreen` on a hidden
///   window still renders nothing.
/// - **`setBounds` is in GTK coordinates on Linux, not physical pixels.** It
///   is still used to put the window back in [leave]. The plugin passes the
///   values straight to `gtk_window_move` and `gtk_window_resize` with no
///   scaling, where the Windows implementation multiplies by the device pixel
///   ratio first, so a physical rectangle has to be divided here and not
///   there. That asymmetry works perfectly at 1x and breaks on a HiDPI laptop.
///
/// `tools/smoke_linux.sh` drives all of this on a real X server and is what
/// found it; none of it is visible to a widget test.
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

    // On screen and drawing before the size changes, and fullscreen rather
    // than [physicalBounds]. Both halves matter, and the class comment above
    // says why; the short version is that either one on its own leaves an
    // overlay with nothing in it that crashes on the first click.
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await windowManager.setFullScreen(true);
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

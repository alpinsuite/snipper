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
/// - **The window has to be on screen before it is resized.** See [enter].
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

    // Straight from dart:ui rather than through WidgetsBinding: this layer
    // talks to the platform and has no business importing the widget tree.
    final ratio = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final gtkBounds = ui.Rect.fromLTWH(
      physicalBounds.left / ratio,
      physicalBounds.top / ratio,
      physicalBounds.width / ratio,
      physicalBounds.height / ratio,
    );

    await windowManager.setAsFrameless();
    await windowManager.setSkipTaskbar(true);

    // **On screen and drawing before it is resized.** `hideFromCapture` hid
    // this window a moment ago so that it would not be in its own screenshot,
    // and the engine does not render for a window that is not on screen.
    // Resized while hidden, it never produces a frame at the new size: the
    // embedder waits a second for one, gives up, and the overlay is a
    // screen-sized rectangle of nothing that segfaults on the first click into
    // it. That happened on every run, both from the hotkey and from --region,
    // and it is what `tools/smoke_linux.sh` exists to catch.
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    await windowManager.setBounds(gtkBounds);
    await windowManager.setAlwaysOnTop(true);
  }

  @override
  Future<void> leave() async {
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

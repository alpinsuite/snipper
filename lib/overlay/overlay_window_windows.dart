import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'overlay_window.dart';

/// The Windows overlay, driven by `windows/runner/overlay_channel.cc`.
///
/// The placement is native rather than done through `window_manager` for a
/// reason that is not about units: moving a window across monitors of different
/// scales raises `WM_DPICHANGED`, and the stock Flutter runner answers it by
/// resizing the window to whatever Windows suggests — undoing the placement and
/// changing `devicePixelRatio` while the overlay is being drawn. Swallowing
/// that message needs a window procedure, which Dart does not have.
class WindowsOverlayWindow implements OverlayWindow {
  static const MethodChannel _channel = MethodChannel(
    'com.alpinsuite.snipper/overlay',
  );

  /// True when the native call to exclude this window from capture worked, so
  /// [showAfterCapture] knows whether there is a hidden window to bring back.
  bool _hidden = false;

  @override
  Future<void> enter(ui.Rect physicalBounds) async {
    await _channel.invokeMethod<bool>('enterOverlay', <String, int>{
      'x': physicalBounds.left.round(),
      'y': physicalBounds.top.round(),
      'width': physicalBounds.width.round(),
      'height': physicalBounds.height.round(),
    });
  }

  @override
  Future<void> leave() async {
    await _channel.invokeMethod<bool>('leaveOverlay');
  }

  @override
  Future<void> hideFromCapture() async {
    final excluded =
        await _channel.invokeMethod<bool>('excludeFromCapture', <String, int>{
          'exclude': 1,
        }) ??
        false;
    if (excluded) return;

    // WDA_EXCLUDEFROMCAPTURE wants Windows 10 2004 or later. Below that, the
    // old dance: hide, let the compositor catch up, then capture.
    _hidden = true;
    await windowManager.hide();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  @override
  Future<void> showAfterCapture() async {
    await _channel.invokeMethod<bool>('excludeFromCapture', <String, int>{
      'exclude': 0,
    });
    if (!_hidden) return;
    _hidden = false;
    await windowManager.show();
    await windowManager.focus();
  }
}

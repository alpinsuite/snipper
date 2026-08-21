import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The frozen desktop, dimmed, with the selection cut back out of the dimming.
///
/// Everything here is in logical coordinates, which is what the pointer speaks.
/// The painter does no mapping at all: the frame is stretched to fill whatever
/// it is given, and the only place physical pixels appear is the size readout,
/// which asks OverlayGeometry for them. Keeping the arithmetic out of the
/// painter is deliberate — a selection one pixel out looks exactly like one
/// that is right, so the maths lives somewhere it can be tested.
class OverlayPainter extends CustomPainter {
  const OverlayPainter({
    required this.frame,
    required this.selection,
    required this.pointer,
    required this.accent,
  });

  final ui.Image frame;

  /// The rectangle being dragged, in logical coordinates, or null before the
  /// first drag.
  final ui.Rect? selection;

  /// Where the pointer is, for the crosshair shown before a drag starts.
  final ui.Offset? pointer;

  final Color accent;

  /// How dark the untouched desktop goes.
  ///
  /// Dark enough that the selection reads as the bright part, light enough that
  /// what is *outside* it stays legible — the thing being framed is usually
  /// identified by what is next to it.
  static const double _scrimOpacity = 0.45;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final whole = ui.Offset.zero & size;

    // One physical pixel of bitmap per physical pixel of window, so the frozen
    // desktop is indistinguishable from the real one underneath it. Anything
    // other than `none` would resample text that was crisp a moment ago and
    // give the freeze away.
    canvas.drawImageRect(
      frame,
      ui.Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
      whole,
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );

    final scrim = ui.Paint()
      ..color = const Color(0xFF000000).withValues(alpha: _scrimOpacity);
    final region = selection;

    if (region == null || region.isEmpty) {
      canvas.drawRect(whole, scrim);
      if (pointer != null) _paintCrosshair(canvas, size, pointer!);
      return;
    }

    // The scrim as four bands rather than an even-odd path over the whole
    // window: a `saveLayer` for one rectangle-shaped hole costs a full-screen
    // offscreen buffer every frame of the drag.
    canvas
      ..drawRect(ui.Rect.fromLTRB(0, 0, size.width, region.top), scrim)
      ..drawRect(
        ui.Rect.fromLTRB(0, region.bottom, size.width, size.height),
        scrim,
      )
      ..drawRect(
        ui.Rect.fromLTRB(0, region.top, region.left, region.bottom),
        scrim,
      )
      ..drawRect(
        ui.Rect.fromLTRB(region.right, region.top, size.width, region.bottom),
        scrim,
      )
      ..drawRect(
        region,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent,
      );

    _paintHandles(canvas, region);
  }

  /// Full-height and full-width guides through the pointer.
  ///
  /// Before a drag there is nothing on screen to say the desktop is frozen or
  /// where the pointer is against a busy background, and a crosshair answers
  /// both.
  void _paintCrosshair(ui.Canvas canvas, ui.Size size, ui.Offset at) {
    final paint = ui.Paint()
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.7);
    canvas
      ..drawLine(ui.Offset(at.dx, 0), ui.Offset(at.dx, size.height), paint)
      ..drawLine(ui.Offset(0, at.dy), ui.Offset(size.width, at.dy), paint);
  }

  /// Small squares at the corners: the thing that makes a rectangle read as a
  /// selection rather than as a box somebody drew.
  void _paintHandles(ui.Canvas canvas, ui.Rect region) {
    const extent = 3.0;
    final paint = ui.Paint()..color = accent;
    for (final corner in <ui.Offset>[
      region.topLeft,
      region.topRight,
      region.bottomLeft,
      region.bottomRight,
    ]) {
      canvas.drawRect(
        ui.Rect.fromCenter(
          center: corner,
          width: extent * 2,
          height: extent * 2,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.selection != selection ||
      oldDelegate.pointer != pointer ||
      oldDelegate.accent != accent;
}

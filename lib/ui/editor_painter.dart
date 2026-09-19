import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/annotation.dart';

/// The snip, the marks on it, and the chrome around whichever one is selected.
///
/// The canvas is scaled into image coordinates once, at the top, so everything
/// below works in the snip's own pixels — which is also the space the marks are
/// stored in and the space they are exported in. There is exactly one transform
/// in the editor and this is it.
class EditorPainter extends CustomPainter {
  const EditorPainter({
    required this.image,
    required this.annotations,
    required this.draft,
    required this.selected,
    required this.scale,
    required this.accent,
  });

  final ui.Image image;
  final List<Annotation> annotations;

  /// The mark being drawn right now, drawn on top of the committed ones.
  final Annotation? draft;

  final Annotation? selected;

  /// View pixels per image pixel.
  final double scale;

  final Color accent;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas
      ..save()
      ..scale(scale);

    canvas.drawImage(
      image,
      ui.Offset.zero,
      ui.Paint()
        // Screenshots are shown below 1:1 more often than not, and a linear
        // filter is what keeps small text from breaking up into speckle.
        ..filterQuality = scale < 1
            ? ui.FilterQuality.medium
            : ui.FilterQuality.none,
    );

    final context = AnnotationContext(base: image, scale: scale);
    for (final annotation in annotations) {
      annotation.paint(canvas, context);
    }
    draft?.paint(canvas, context);

    final chosen = selected;
    if (chosen != null && draft == null) _paintSelection(canvas, chosen);

    canvas.restore();
  }

  /// A hairline box with corner handles around the selected mark.
  ///
  /// Everything here is divided by [scale], so the chrome is a constant
  /// thickness on screen no matter how far the image is zoomed out. A one-pixel
  /// outline in image space would be invisible at 40%, which is where a
  /// full-screen snip is usually being looked at.
  void _paintSelection(ui.Canvas canvas, Annotation annotation) {
    final box = annotation.bounds.inflate(3 / scale);
    canvas.drawRect(
      box,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1 / scale
        ..color = accent,
    );

    final extent = 3 / scale;
    final fill = ui.Paint()..color = accent;
    for (final corner in <ui.Offset>[
      box.topLeft,
      box.topRight,
      box.bottomLeft,
      box.bottomRight,
    ]) {
      canvas.drawRect(
        ui.Rect.fromCenter(
          center: corner,
          width: extent * 2,
          height: extent * 2,
        ),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(EditorPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.annotations != annotations ||
      oldDelegate.draft != draft ||
      oldDelegate.selected != selected ||
      oldDelegate.scale != scale ||
      oldDelegate.accent != accent;
}

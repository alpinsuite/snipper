import 'dart:ui' as ui;

import '../model/annotation.dart';
import '../model/snip.dart';

/// Burns the marks into the picture.
///
/// This is the one place a snip stops being editable, and it happens on the way
/// out — to a file, or to the clipboard. Until then the base image is untouched
/// and every mark is still an object, which is what makes a redaction something
/// you can move rather than something you have to get right first time.
///
/// The corollary is worth stating plainly: **anything that leaves this
/// application has been through here.** A redaction that has not been flattened
/// has not been shared either, because the only routes out are save and copy
/// and both call this.
abstract final class Flatten {
  static Future<ui.Image> render(
    Snip snip,
    List<Annotation> annotations,
  ) async {
    if (annotations.isEmpty) {
      // Nothing to draw over it, so hand back the image itself rather than a
      // pixel-identical copy. Callers must not dispose what they get from here
      // while the shot is still open.
      return snip.image;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(snip.image, ui.Offset.zero, ui.Paint());

    // Scale 1: the marks are stored in image pixels, and this canvas is in
    // image pixels, so there is no transform at all on the export path. The
    // editor's zoom exists only on screen.
    final context = AnnotationContext(base: snip.image, scale: 1);
    for (final annotation in annotations) {
      annotation.paint(canvas, context);
    }

    return recorder.endRecording().toImage(snip.width, snip.height);
  }

  /// True when [render] returns the snip's own image rather than a new one, so
  /// a caller knows whether it owns what it was handed.
  static bool isPassthrough(List<Annotation> annotations) =>
      annotations.isEmpty;
}

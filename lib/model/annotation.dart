import 'dart:math' as math;
import 'dart:ui' as ui;

/// What a mark is made of.
///
/// One style type for every kind of annotation rather than one per kind: the
/// options bar shows the fields the active tool uses and hides the rest, and a
/// mark keeps the colour it was drawn with when the tool changes under it.
class AnnotationStyle {
  const AnnotationStyle({
    required this.color,
    this.strokeWidth = 4,
    this.filled = false,
    this.redaction = RedactionKind.blur,
    this.fontSize = 24,
  });

  final ui.Color color;

  /// In image pixels, so a mark drawn at 50% zoom is the same weight on the
  /// saved file as one drawn at 100%.
  final double strokeWidth;

  /// Whether a shape is a solid block or an outline.
  final bool filled;

  final RedactionKind redaction;
  final double fontSize;

  AnnotationStyle copyWith({
    ui.Color? color,
    double? strokeWidth,
    bool? filled,
    RedactionKind? redaction,
    double? fontSize,
  }) => AnnotationStyle(
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    filled: filled ?? this.filled,
    redaction: redaction ?? this.redaction,
    fontSize: fontSize ?? this.fontSize,
  );
}

/// How a redaction hides what is under it.
enum RedactionKind {
  /// Soft. Reads as "deliberately removed" while leaving the shape of the page
  /// intact, which is usually what a screenshot wants.
  blur,

  /// Blocks. Harder to argue with, and the convention for anything that has to
  /// look properly gone.
  pixelate,

  /// Flat colour. The only one of the three that is unambiguously irreversible
  /// to look at.
  solid,
}

/// Everything a mark needs in order to draw itself.
///
/// The canvas is already in image coordinates when a mark is painted, so the
/// only things that cannot be derived are the picture underneath — which the
/// redactions sample — and the current zoom, which the selection chrome uses to
/// stay a constant thickness on screen.
class AnnotationContext {
  const AnnotationContext({required this.base, required this.scale});

  /// The snip itself. Redactions draw *this*, filtered.
  final ui.Image base;

  /// View pixels per image pixel.
  final double scale;
}

/// One mark on a snip.
///
/// Immutable, and identified by [id] rather than by identity, so the history
/// can hold whole lists of them cheaply: an undo step is a list of pointers,
/// not a copy of the image.
///
/// Marks stay marks until the file is written. That is the difference between
/// this and `paint`, which commits every stroke to the bitmap because it is an
/// image editor and that is what undo means there. Here an arrow can be moved,
/// recoloured or deleted an hour after it was drawn, and the pixels underneath
/// a redaction are still in the base image until export flattens it.
sealed class Annotation {
  const Annotation({required this.id, required this.style});

  final int id;
  final AnnotationStyle style;

  /// Everything [paint] touches, in image pixels. Used for hit testing and for
  /// deciding what needs repainting, so it must not be tighter than what is
  /// actually drawn — stroke width included.
  ui.Rect get bounds;

  /// Whether [point] is close enough to count as clicking this mark.
  ///
  /// [tolerance] is in image pixels and comes from the view: at 25% zoom a
  /// four-pixel line is one pixel on screen, and nobody can click that.
  bool hitTest(ui.Offset point, {double tolerance = 0});

  void paint(ui.Canvas canvas, AnnotationContext context);

  /// The same mark, moved. Every kind supports this; it is what makes the whole
  /// editor worth having.
  Annotation translated(ui.Offset delta);

  /// The same mark, restyled.
  Annotation restyled(AnnotationStyle style);
}

/// A mark defined by dragging between two points.
///
/// Lines, arrows, rectangles, ellipses and redactions are all this shape, and
/// sharing the base means resizing them later has one implementation rather
/// than five.
sealed class DraggedAnnotation extends Annotation {
  const DraggedAnnotation({
    required super.id,
    required super.style,
    required this.start,
    required this.end,
  });

  final ui.Offset start;
  final ui.Offset end;

  /// The normalised rectangle between the two points.
  ui.Rect get rect => ui.Rect.fromPoints(start, end);
}

// ---------------------------------------------------------------------------
// Freehand
// ---------------------------------------------------------------------------

/// A freehand line.
class PenStroke extends Annotation {
  const PenStroke({
    required super.id,
    required super.style,
    required this.points,
  });

  final List<ui.Offset> points;

  @override
  ui.Rect get bounds => _boundsOf(points).inflate(style.strokeWidth);

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) {
    final reach = style.strokeWidth / 2 + tolerance;
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(point, points[i - 1], points[i]) <= reach) {
        return true;
      }
    }
    return points.length == 1 && (points.first - point).distance <= reach;
  }

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    canvas.drawPath(_path(points), _strokePaint(style));
  }

  @override
  PenStroke translated(ui.Offset delta) => PenStroke(
    id: id,
    style: style,
    points: <ui.Offset>[for (final point in points) point + delta],
  );

  @override
  PenStroke restyled(AnnotationStyle style) =>
      PenStroke(id: id, style: style, points: points);

  PenStroke extended(ui.Offset point) =>
      PenStroke(id: id, style: style, points: <ui.Offset>[...points, point]);
}

/// A freehand line drawn like a marker: thick, translucent and multiplied, so
/// what is under it still reads.
///
/// A separate kind rather than a flag on [PenStroke], because the blend mode is
/// the whole point and a highlighter that is only "a wide pen" looks like a
/// mistake over text.
class HighlighterStroke extends Annotation {
  const HighlighterStroke({
    required super.id,
    required super.style,
    required this.points,
  });

  final List<ui.Offset> points;

  /// Marker ink is wide. Expressed as a multiple of the stroke width so the
  /// one width control still does something useful for it.
  static const double widthFactor = 4;

  double get width => style.strokeWidth * widthFactor;

  @override
  ui.Rect get bounds => _boundsOf(points).inflate(width);

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) {
    final reach = width / 2 + tolerance;
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(point, points[i - 1], points[i]) <= reach) {
        return true;
      }
    }
    return points.length == 1 && (points.first - point).distance <= reach;
  }

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    canvas.drawPath(
      _path(points),
      ui.Paint()
        ..color = style.color
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = width
        // Butt rather than round: a highlighter has a flat nib, and a rounded
        // one bulges past the end of the word it was run over.
        ..strokeCap = ui.StrokeCap.butt
        ..strokeJoin = ui.StrokeJoin.round
        ..blendMode = ui.BlendMode.multiply
        ..isAntiAlias = true,
    );
  }

  @override
  HighlighterStroke translated(ui.Offset delta) => HighlighterStroke(
    id: id,
    style: style,
    points: <ui.Offset>[for (final point in points) point + delta],
  );

  @override
  HighlighterStroke restyled(AnnotationStyle style) =>
      HighlighterStroke(id: id, style: style, points: points);

  HighlighterStroke extended(ui.Offset point) => HighlighterStroke(
    id: id,
    style: style,
    points: <ui.Offset>[...points, point],
  );
}

// ---------------------------------------------------------------------------
// Shapes
// ---------------------------------------------------------------------------

class LineShape extends DraggedAnnotation {
  const LineShape({
    required super.id,
    required super.style,
    required super.start,
    required super.end,
  });

  @override
  ui.Rect get bounds => rect.inflate(style.strokeWidth);

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) =>
      _distanceToSegment(point, start, end) <=
      style.strokeWidth / 2 + tolerance;

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    canvas.drawLine(start, end, _strokePaint(style));
  }

  @override
  LineShape translated(ui.Offset delta) =>
      LineShape(id: id, style: style, start: start + delta, end: end + delta);

  @override
  LineShape restyled(AnnotationStyle style) =>
      LineShape(id: id, style: style, start: start, end: end);
}

/// A line with a head on it — the mark a screenshot is annotated with more
/// often than all the others put together.
class ArrowShape extends DraggedAnnotation {
  const ArrowShape({
    required super.id,
    required super.style,
    required super.start,
    required super.end,
  });

  /// How far back the barbs reach, as a multiple of the stroke width.
  ///
  /// Scaled with the stroke rather than fixed, so a thin arrow gets a small
  /// head and a thick one a proportionate one. A fixed head on a thick line
  /// looks like a pin.
  static const double headFactor = 4.5;

  double get headLength => style.strokeWidth * headFactor;

  @override
  ui.Rect get bounds => rect.inflate(headLength);

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) =>
      _distanceToSegment(point, start, end) <=
      style.strokeWidth / 2 + tolerance;

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    final delta = end - start;
    final length = delta.distance;
    final paint = _strokePaint(style);
    if (length < 0.01) {
      canvas.drawPoints(ui.PointMode.points, <ui.Offset>[start], paint);
      return;
    }

    // The shaft stops short of the tip, so the stroke's round cap does not
    // poke out through the head as a bump.
    final direction = delta / length;
    final head = math.min(headLength, length);
    final shaftEnd = end - direction * (head * 0.6);
    canvas.drawLine(start, shaftEnd, paint);

    const spread = 0.42; // radians either side of the shaft
    final angle = math.atan2(delta.dy, delta.dx);
    final left =
        end -
        ui.Offset(
          math.cos(angle - spread) * head,
          math.sin(angle - spread) * head,
        );
    final right =
        end -
        ui.Offset(
          math.cos(angle + spread) * head,
          math.sin(angle + spread) * head,
        );
    canvas.drawPath(
      ui.Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      ui.Paint()
        ..color = style.color
        ..isAntiAlias = true,
    );
  }

  @override
  ArrowShape translated(ui.Offset delta) =>
      ArrowShape(id: id, style: style, start: start + delta, end: end + delta);

  @override
  ArrowShape restyled(AnnotationStyle style) =>
      ArrowShape(id: id, style: style, start: start, end: end);
}

class RectShape extends DraggedAnnotation {
  const RectShape({
    required super.id,
    required super.style,
    required super.start,
    required super.end,
  });

  @override
  ui.Rect get bounds => rect.inflate(style.strokeWidth);

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) {
    final reach = style.strokeWidth / 2 + tolerance;
    if (style.filled) return rect.inflate(reach).contains(point);
    // An outline is hit on its edge, not in its middle: a box drawn around
    // something must not swallow clicks meant for the marks inside it.
    return rect.inflate(reach).contains(point) &&
        !rect.deflate(reach).contains(point);
  }

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    canvas.drawRect(rect, _shapePaint(style));
  }

  @override
  RectShape translated(ui.Offset delta) =>
      RectShape(id: id, style: style, start: start + delta, end: end + delta);

  @override
  RectShape restyled(AnnotationStyle style) =>
      RectShape(id: id, style: style, start: start, end: end);
}

class EllipseShape extends DraggedAnnotation {
  const EllipseShape({
    required super.id,
    required super.style,
    required super.start,
    required super.end,
  });

  @override
  ui.Rect get bounds => rect.inflate(style.strokeWidth);

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) {
    final reach = style.strokeWidth / 2 + tolerance;
    double normalised(ui.Rect box) {
      if (box.width <= 0 || box.height <= 0) return double.infinity;
      final dx = (point.dx - box.center.dx) / (box.width / 2);
      final dy = (point.dy - box.center.dy) / (box.height / 2);
      return dx * dx + dy * dy;
    }

    if (normalised(rect.inflate(reach)) > 1) return false;
    if (style.filled) return true;
    return normalised(rect.deflate(reach)) > 1;
  }

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    canvas.drawOval(rect, _shapePaint(style));
  }

  @override
  EllipseShape translated(ui.Offset delta) => EllipseShape(
    id: id,
    style: style,
    start: start + delta,
    end: end + delta,
  );

  @override
  EllipseShape restyled(AnnotationStyle style) =>
      EllipseShape(id: id, style: style, start: start, end: end);
}

// ---------------------------------------------------------------------------
// Redaction
// ---------------------------------------------------------------------------

/// A rectangle that hides what is under it.
///
/// The hiding is a *drawing* operation over the untouched base image, not a
/// change to the pixels — which is why a redaction can be moved or removed
/// after the fact, and why the real pixels are still in the file until the snip
/// is flattened for export. Anything that leaves this application has been
/// flattened; anything that has not, has not been shared.
class Redaction extends DraggedAnnotation {
  const Redaction({
    required super.id,
    required super.style,
    required super.start,
    required super.end,
  });

  /// Sigma of the blur, and the block size of the mosaic, both as a multiple of
  /// the stroke width — so the one width control governs how thoroughly a
  /// redaction hides things.
  static const double strengthFactor = 2.5;

  double get strength => math.max(2, style.strokeWidth * strengthFactor);

  @override
  ui.Rect get bounds => rect;

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) =>
      rect.inflate(tolerance).contains(point);

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    if (rect.isEmpty) return;

    if (style.redaction == RedactionKind.solid) {
      canvas.drawRect(
        rect,
        ui.Paint()
          ..color = style.color
          ..isAntiAlias = false,
      );
      return;
    }

    canvas
      ..save()
      ..clipRect(rect);
    if (style.redaction == RedactionKind.blur) {
      _paintBlur(canvas, context);
    } else {
      _paintMosaic(canvas, context);
    }
    canvas.restore();
  }

  void _paintBlur(ui.Canvas canvas, AnnotationContext context) {
    final whole = ui.Rect.fromLTWH(
      0,
      0,
      context.base.width.toDouble(),
      context.base.height.toDouble(),
    );
    canvas.drawImageRect(
      context.base,
      whole,
      whole,
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: strength,
          sigmaY: strength,
          // Clamp, not decal. With decal the filter samples transparency past
          // the edge of the image and a redaction against the edge of the snip
          // fades out there, which looks like a mistake rather than a redaction.
          tileMode: ui.TileMode.clamp,
        ),
    );
  }

  /// A mosaic, drawn one block at a time.
  ///
  /// The obvious implementation — an `ImageFilter.compose` of a scale down and
  /// a scale back up — does nothing at all: Skia collapses the two matrices
  /// into the identity before any pixels are touched, and the region comes out
  /// exactly as it went in. That is a silent failure of a *redaction*, which is
  /// the worst place in this application to have one, so it is done the honest
  /// way instead.
  ///
  /// Magnifying a one-pixel source rectangle to fill a block, with no
  /// filtering, is a nearest-neighbour downsample by definition. It costs one
  /// draw call per block, which is why [_blockFor] refuses to make them so
  /// small that a large redaction turns into tens of thousands of them.
  void _paintMosaic(ui.Canvas canvas, AnnotationContext context) {
    final block = _blockFor(rect);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false;
    final limit = ui.Rect.fromLTWH(
      0,
      0,
      context.base.width.toDouble(),
      context.base.height.toDouble(),
    );

    for (var y = rect.top; y < rect.bottom; y += block) {
      for (var x = rect.left; x < rect.right; x += block) {
        // The centre of the block, clamped inside the image: a redaction can
        // legitimately hang over the edge of the snip, and sampling outside it
        // draws nothing at all.
        final sampleX = (x + block / 2).clamp(limit.left, limit.right - 1);
        final sampleY = (y + block / 2).clamp(limit.top, limit.bottom - 1);
        canvas.drawImageRect(
          context.base,
          ui.Rect.fromLTWH(
            sampleX.floorToDouble(),
            sampleY.floorToDouble(),
            1,
            1,
          ),
          ui.Rect.fromLTWH(x, y, block, block),
          paint,
        );
      }
    }
  }

  /// Block size in image pixels.
  ///
  /// Smaller than the blur's sigma at the same setting, for a reason worth
  /// writing down: a point sample per block is a coarser downsample than a blur
  /// of the same radius, and blocks the size of a whole line of text mostly
  /// land on the white *between* the letters. The result destroys the writing
  /// but does not read as having been redacted — it reads as a few stray
  /// squares, which invites somebody to look harder rather than move on.
  ///
  /// Bounded from below as well: a mosaic over a full-screen snip at the finest
  /// setting would otherwise be a hundred thousand draw calls on every frame of
  /// a drag.
  double _blockFor(ui.Rect area) {
    const maxBlocks = 6000;
    final double wanted = math.max(4, style.strokeWidth * 1.4);
    final blocks = (area.width / wanted) * (area.height / wanted);
    if (blocks <= maxBlocks) return wanted;
    return wanted * math.sqrt(blocks / maxBlocks);
  }

  @override
  Redaction translated(ui.Offset delta) =>
      Redaction(id: id, style: style, start: start + delta, end: end + delta);

  @override
  Redaction restyled(AnnotationStyle style) =>
      Redaction(id: id, style: style, start: start, end: end);
}

// ---------------------------------------------------------------------------
// Numbered steps and text
// ---------------------------------------------------------------------------

/// A numbered disc, for walking somebody through an interface in order.
class StepBadge extends Annotation {
  const StepBadge({
    required super.id,
    required super.style,
    required this.centre,
    required this.number,
  });

  final ui.Offset centre;
  final int number;

  /// Sized off the stroke width, like everything else, so the one control
  /// governs how prominent marks are.
  double get radius => math.max(9, style.strokeWidth * 3.2);

  @override
  ui.Rect get bounds => ui.Rect.fromCircle(center: centre, radius: radius + 1);

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) =>
      (point - centre).distance <= radius + tolerance;

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    canvas.drawCircle(
      centre,
      radius,
      ui.Paint()
        ..color = style.color
        ..isAntiAlias = true,
    );

    // White, always, rather than a themed ink: the disc is whatever colour was
    // chosen, and the numeral has to stay legible on every one of them.
    final painter =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: ui.TextAlign.center,
              fontSize: radius * 1.25,
              fontWeight: ui.FontWeight.bold,
            ),
          )
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF)))
          ..addText('$number'); // i18n-exempt: a numeral
    final paragraph = painter.build()
      ..layout(ui.ParagraphConstraints(width: radius * 4));
    canvas.drawParagraph(
      paragraph,
      ui.Offset(centre.dx - radius * 2, centre.dy - paragraph.height / 2),
    );
  }

  @override
  StepBadge translated(ui.Offset delta) =>
      StepBadge(id: id, style: style, centre: centre + delta, number: number);

  @override
  StepBadge restyled(AnnotationStyle style) =>
      StepBadge(id: id, style: style, centre: centre, number: number);
}

/// A line of text placed on the snip.
class TextNote extends Annotation {
  const TextNote({
    required super.id,
    required super.style,
    required this.anchor,
    required this.text,
  });

  /// Top-left of the text.
  final ui.Offset anchor;

  final String text;

  /// The widest a note runs before it wraps, in image pixels.
  static const double maxWidth = 640;

  ui.Paragraph get _paragraph {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: style.fontSize,
              fontWeight: ui.FontWeight.w600,
            ),
          )
          ..pushStyle(ui.TextStyle(color: style.color))
          ..addText(text.isEmpty ? ' ' : text);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: maxWidth));
  }

  @override
  ui.Rect get bounds {
    final paragraph = _paragraph;
    return ui.Rect.fromLTWH(
      anchor.dx,
      anchor.dy,
      paragraph.longestLine + 2,
      paragraph.height,
    );
  }

  @override
  bool hitTest(ui.Offset point, {double tolerance = 0}) =>
      bounds.inflate(tolerance).contains(point);

  @override
  void paint(ui.Canvas canvas, AnnotationContext context) {
    canvas.drawParagraph(_paragraph, anchor);
  }

  @override
  TextNote translated(ui.Offset delta) =>
      TextNote(id: id, style: style, anchor: anchor + delta, text: text);

  @override
  TextNote restyled(AnnotationStyle style) =>
      TextNote(id: id, style: style, anchor: anchor, text: text);

  TextNote withText(String text) =>
      TextNote(id: id, style: style, anchor: anchor, text: text);
}

// ---------------------------------------------------------------------------
// Shared drawing and geometry
// ---------------------------------------------------------------------------

ui.Paint _strokePaint(AnnotationStyle style) => ui.Paint()
  ..color = style.color
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = style.strokeWidth
  ..strokeCap = ui.StrokeCap.round
  ..strokeJoin = ui.StrokeJoin.round
  ..isAntiAlias = true;

ui.Paint _shapePaint(AnnotationStyle style) => style.filled
    ? (ui.Paint()
        ..color = style.color
        ..isAntiAlias = true)
    : _strokePaint(style);

ui.Path _path(List<ui.Offset> points) {
  final path = ui.Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) {
    // A dot: a zero-length line with a round cap draws nothing, so it needs a
    // second point a hair away.
    path.lineTo(points.first.dx + 0.01, points.first.dy);
    return path;
  }
  // Quadratics through the midpoints, which is the cheapest way to get a
  // freehand line that does not look like a chain of straight segments.
  for (var i = 1; i < points.length - 1; i++) {
    final midpoint = (points[i] + points[i + 1]) / 2;
    path.quadraticBezierTo(
      points[i].dx,
      points[i].dy,
      midpoint.dx,
      midpoint.dy,
    );
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

ui.Rect _boundsOf(List<ui.Offset> points) {
  if (points.isEmpty) return ui.Rect.zero;
  var left = points.first.dx;
  var top = points.first.dy;
  var right = left;
  var bottom = top;
  for (final point in points) {
    left = math.min(left, point.dx);
    top = math.min(top, point.dy);
    right = math.max(right, point.dx);
    bottom = math.max(bottom, point.dy);
  }
  return ui.Rect.fromLTRB(left, top, right, bottom);
}

/// Distance from [point] to the segment [a]-[b].
double _distanceToSegment(ui.Offset point, ui.Offset a, ui.Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (point - a).distance;
  final ap = point - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
  return (point - (a + ab * t)).distance;
}

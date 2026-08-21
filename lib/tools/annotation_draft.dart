import 'dart:math' as math;
import 'dart:ui' as ui;

import '../model/annotation.dart';

/// The tools in the strip, in the order they appear.
enum ToolId {
  /// Picks and moves marks that are already there. Not a drawing tool, and
  /// first because it is where a gesture goes when nothing else is meant.
  select,
  pen,
  highlighter,
  arrow,
  line,
  rectangle,
  ellipse,
  redact,
  step,
  text,
}

/// Which style fields a tool actually uses.
///
/// The options bar shows exactly these and nothing else. A colour picker beside
/// a blur tool is a control that does nothing, and a control that does nothing
/// is worse than one that is missing.
extension ToolOptions on ToolId {
  bool get usesColour => switch (this) {
    ToolId.select => false,
    ToolId.redact => false,
    _ => true,
  };

  bool get usesWidth => this != ToolId.select && this != ToolId.text;

  bool get usesFill => this == ToolId.rectangle || this == ToolId.ellipse;

  bool get usesRedaction => this == ToolId.redact;

  bool get usesFontSize => this == ToolId.text;

  /// True for tools that place a mark on a single click rather than a drag.
  bool get isTap => this == ToolId.step || this == ToolId.text;
}

/// One mark being drawn.
///
/// A draft *is* the annotation while it is being made — there is no separate
/// preview representation, so what is on screen during the drag and what ends
/// up in the list are the same object built the same way. That is the rule
/// `paint` states as "preview and commit share one draw", arrived at from the
/// other direction: here there is only one thing, so they cannot disagree.
class AnnotationDraft {
  AnnotationDraft({
    required this.tool,
    required this.style,
    required this.id,
    required ui.Offset start,
    this.stepNumber = 1,
  }) : _start = start,
       _current = start,
       _points = <ui.Offset>[start];

  final ToolId tool;
  final AnnotationStyle style;
  final int id;
  final int stepNumber;

  final ui.Offset _start;
  ui.Offset _current;
  final List<ui.Offset> _points;

  bool _shift = false;

  /// The pointer moved. [shift] constrains the shape: lines and arrows to 45°
  /// increments, rectangles to squares and ellipses to circles — the same
  /// modifier every drawing program uses for the same thing.
  void extend(ui.Offset point, {bool shift = false}) {
    _shift = shift;
    _current = point;
    if (tool == ToolId.pen || tool == ToolId.highlighter) {
      // Points closer together than this add nothing but work: the smoothing
      // in the path already rounds the corners between them.
      if ((_points.last - point).distance >= 1.5) _points.add(point);
    }
  }

  /// The mark as it stands, or null when there is not enough of it yet.
  Annotation? get annotation {
    switch (tool) {
      case ToolId.select:
        return null;

      case ToolId.pen:
        return PenStroke(id: id, style: style, points: _points);

      case ToolId.highlighter:
        return HighlighterStroke(id: id, style: style, points: _points);

      case ToolId.line:
        return LineShape(
          id: id,
          style: style,
          start: _start,
          end: _constrained,
        );

      case ToolId.arrow:
        return ArrowShape(
          id: id,
          style: style,
          start: _start,
          end: _constrained,
        );

      case ToolId.rectangle:
        return RectShape(id: id, style: style, start: _start, end: _squared);

      case ToolId.ellipse:
        return EllipseShape(id: id, style: style, start: _start, end: _squared);

      case ToolId.redact:
        return Redaction(id: id, style: style, start: _start, end: _squared);

      case ToolId.step:
        return StepBadge(
          id: id,
          style: style,
          centre: _start,
          number: stepNumber,
        );

      case ToolId.text:
        // Text is placed by the widget layer, which owns the keyboard focus and
        // the IME. There is nothing to preview until something is typed.
        return null;
    }
  }

  /// Whether releasing here should keep the mark.
  ///
  /// A stray click while a drawing tool is selected should leave nothing
  /// behind, which is what stops a shape tool from littering the image with
  /// zero-sized rectangles nobody can see or select.
  bool get isCommittable {
    switch (tool) {
      case ToolId.select:
      case ToolId.text:
        return false;
      case ToolId.step:
        return true;
      case ToolId.pen:
      case ToolId.highlighter:
        return _points.length > 1 ||
            (_points.length == 1 && tool == ToolId.pen);
      case ToolId.line:
      case ToolId.arrow:
      case ToolId.rectangle:
      case ToolId.ellipse:
      case ToolId.redact:
        return (_current - _start).distance >= minimumDrag;
    }
  }

  /// In image pixels. Small enough that no deliberate mark is refused.
  static const double minimumDrag = 4;

  /// [_current] snapped to 45° around [_start] while Shift is held.
  ui.Offset get _constrained {
    if (!_shift) return _current;
    final delta = _current - _start;
    if (delta == ui.Offset.zero) return _current;
    const step = math.pi / 4;
    final angle =
        (math.atan2(delta.dy, delta.dx) / step).roundToDouble() * step;
    final length = delta.distance;
    return _start +
        ui.Offset(length * math.cos(angle), length * math.sin(angle));
  }

  /// [_current] pulled onto a square around [_start] while Shift is held.
  ui.Offset get _squared {
    if (!_shift) return _current;
    final delta = _current - _start;
    final side = math.max(delta.dx.abs(), delta.dy.abs());
    return ui.Offset(
      _start.dx + (delta.dx.isNegative ? -side : side),
      _start.dy + (delta.dy.isNegative ? -side : side),
    );
  }
}

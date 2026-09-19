import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../model/annotation.dart';
import '../tools/annotation_draft.dart';

/// Which tool is active and what it will draw with.
///
/// One style shared by every tool rather than one each. Picking red for an
/// arrow and then switching to the pen should give a red pen: the colour is a
/// decision about the annotation, not about the tool, and carrying it across is
/// what makes a set of marks look like one set of marks.
///
/// The exception is stroke width, which is remembered per tool — a highlighter
/// and a pen want genuinely different weights, and making one follow the other
/// means resetting it every time you switch.
class ToolController extends ChangeNotifier {
  ToolId _tool = ToolId.arrow;
  ToolId get tool => _tool;

  /// Red, because a screenshot is almost always a photograph of something
  /// somebody else's software drew, and red is the one colour interfaces
  /// reliably do not use for their own chrome.
  static const ui.Color defaultColour = ui.Color(0xFFE5484D);

  ui.Color _colour = defaultColour;
  ui.Color get colour => _colour;

  bool _filled = false;
  RedactionKind _redaction = RedactionKind.blur;
  double _fontSize = 24;

  /// Stroke width per tool, in image pixels.
  final Map<ToolId, double> _widths = <ToolId, double>{
    ToolId.pen: 4,
    ToolId.highlighter: 5,
    ToolId.arrow: 5,
    ToolId.line: 4,
    ToolId.rectangle: 4,
    ToolId.ellipse: 4,
    ToolId.redact: 6,
    ToolId.step: 6,
    ToolId.text: 4,
  };

  /// The last few colours, most recent first, for the picker to offer back.
  final List<ui.Color> _recents = <ui.Color>[];
  List<ui.Color> get recents => List<ui.Color>.unmodifiable(_recents);

  double get strokeWidth => _widths[_tool] ?? 4;
  bool get filled => _filled;
  RedactionKind get redaction => _redaction;
  double get fontSize => _fontSize;

  AnnotationStyle get style => AnnotationStyle(
    color: _colour,
    strokeWidth: strokeWidth,
    filled: _filled,
    redaction: _redaction,
    fontSize: _fontSize,
  );

  void setTool(ToolId tool) {
    if (_tool == tool) return;
    _tool = tool;
    notifyListeners();
  }

  void setColour(ui.Color colour) {
    if (_colour == colour) return;
    _colour = colour;
    _recents
      ..removeWhere((existing) => existing == colour)
      ..insert(0, colour);
    if (_recents.length > 8) _recents.removeLast();
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    if (_widths[_tool] == width) return;
    _widths[_tool] = width;
    notifyListeners();
  }

  void setFilled(bool filled) {
    if (_filled == filled) return;
    _filled = filled;
    notifyListeners();
  }

  void setRedaction(RedactionKind kind) {
    if (_redaction == kind) return;
    _redaction = kind;
    notifyListeners();
  }

  void setFontSize(double size) {
    if (_fontSize == size) return;
    _fontSize = size;
    notifyListeners();
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../controller/shot_controller.dart';
import '../controller/tool_controller.dart';
import '../core/theme.dart';
import '../model/annotation.dart';
import '../tools/annotation_draft.dart';
import 'editor_painter.dart';

/// The snip, and the marks being made on it.
///
/// The view shows the image at whatever fraction of its own size fits, and
/// never larger: a screenshot shown above 1:1 is a screenshot somebody will
/// misread. Everything the pointer does is converted into image pixels at the
/// edge, in [_toImage], and nothing below that line knows about the view at
/// all — which is what lets a mark drawn at 40% come out the right weight in
/// the file.
class EditorView extends StatefulWidget {
  const EditorView({super.key});

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  AnnotationDraft? _draft;

  /// Set while a selected mark is being dragged around.
  int? _movingId;
  ui.Offset? _lastMovePoint;
  bool _movedSinceDown = false;

  /// The note being typed, if any.
  TextNote? _editing;
  final TextEditingController _text = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final shot = context.watch<ShotController>();
    final tools = context.watch<ToolController>();
    final snip = shot.snip;
    if (snip == null) return const SizedBox.shrink();

    final (light, dark) = AppTheme.checkerboard(theme.palette);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = _scaleFor(constraints.biggest, snip.width, snip.height);
        final viewSize = ui.Size(snip.width * scale, snip.height * scale);

        return ColoredBox(
          color: theme.palette.isDark ? dark : light,
          child: Center(
            child: SizedBox(
              width: viewSize.width,
              height: viewSize.height,
              child: MouseRegion(
                cursor: tools.tool == ToolId.select
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.precise,
                child: Listener(
                  onPointerDown: (event) => _onDown(shot, tools, event, scale),
                  onPointerMove: (event) => _onMove(shot, tools, event, scale),
                  onPointerUp: (_) => _onUp(shot, tools),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: EditorPainter(
                            image: snip.image,
                            annotations: shot.annotations,
                            draft: shot.draft,
                            selected: shot.selected,
                            scale: scale,
                            accent: theme.palette.accent,
                          ),
                        ),
                      ),
                      if (_editing != null)
                        _TextEditor(
                          note: _editing!,
                          scale: scale,
                          controller: _text,
                          focusNode: _textFocus,
                          onDone: () => _finishText(shot),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The largest whole-image scale that fits, capped at 1.
  static double _scaleFor(ui.Size available, int width, int height) {
    if (width == 0 || height == 0) return 1;
    // A little breathing room, so the image is not flush against the panel
    // edges and the selection chrome around an edge mark stays visible.
    const margin = 24.0;
    final usable = ui.Size(
      math.max(1, available.width - margin),
      math.max(1, available.height - margin),
    );
    return math.min(1, math.min(usable.width / width, usable.height / height));
  }

  ui.Offset _toImage(ui.Offset local, double scale) =>
      ui.Offset(local.dx / scale, local.dy / scale);

  /// How close a click has to be to count, in image pixels.
  ///
  /// Scaled by the zoom: at 40% a four-pixel line is under two pixels on
  /// screen, and asking anyone to hit that exactly is asking them to fail.
  double _tolerance(double scale) => 6 / scale;

  void _onDown(
    ShotController shot,
    ToolController tools,
    PointerDownEvent event,
    double scale,
  ) {
    if (_editing != null) {
      _finishText(shot);
      return;
    }

    final point = _toImage(event.localPosition, scale);
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // A right-click deselects, wherever it lands. There is no context menu on
    // the canvas yet, and a right-click that does nothing at all reads as the
    // application having missed it.
    if (event.buttons & kSecondaryMouseButton != 0) {
      shot.select(null);
      return;
    }

    if (tools.tool == ToolId.select) {
      final hit = shot.hitTest(point, tolerance: _tolerance(scale));
      shot.select(hit?.id);
      if (hit != null) {
        _movingId = hit.id;
        _lastMovePoint = point;
        _movedSinceDown = false;
      }
      return;
    }

    if (tools.tool == ToolId.text) {
      _startText(shot, tools, point);
      return;
    }

    final draft = AnnotationDraft(
      tool: tools.tool,
      style: tools.style,
      id: shot.takeId(),
      start: point,
      stepNumber: shot.nextStepNumber,
    )..extend(point, shift: shift);
    _draft = draft;
    shot.showDraft(draft.annotation);
  }

  void _onMove(
    ShotController shot,
    ToolController tools,
    PointerMoveEvent event,
    double scale,
  ) {
    final point = _toImage(event.localPosition, scale);

    final movingId = _movingId;
    if (movingId != null) {
      final previous = _lastMovePoint ?? point;
      // Recorded on the first move only, so a whole drag is one undo step.
      shot.move(movingId, point - previous, record: !_movedSinceDown);
      _movedSinceDown = true;
      _lastMovePoint = point;
      return;
    }

    final draft = _draft;
    if (draft == null) return;
    draft.extend(point, shift: HardwareKeyboard.instance.isShiftPressed);
    shot.showDraft(draft.annotation);
  }

  void _onUp(ShotController shot, ToolController tools) {
    if (_movingId != null) {
      _movingId = null;
      _lastMovePoint = null;
      _movedSinceDown = false;
      return;
    }

    final draft = _draft;
    _draft = null;
    if (draft == null) return;

    final annotation = draft.annotation;
    if (annotation == null || !draft.isCommittable) {
      // A stray click with a shape tool leaves nothing behind, rather than an
      // invisible zero-sized mark nobody can select in order to delete.
      shot.discardDraft();
      return;
    }
    shot.commitDraft(annotation);
  }

  // -- text -----------------------------------------------------------------

  void _startText(ShotController shot, ToolController tools, ui.Offset point) {
    final note = TextNote(
      id: shot.takeId(),
      style: tools.style,
      anchor: point,
      text: '',
    );
    setState(() => _editing = note);
    _text.text = '';
    // The field is created by this rebuild, so focus has to wait for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocus.requestFocus();
    });
  }

  void _finishText(ShotController shot) {
    final note = _editing;
    if (note == null) return;
    setState(() => _editing = null);
    final typed = _text.text.trim();
    // An empty note is somebody changing their mind, not a mark. Committing it
    // would leave an invisible object on the image.
    if (typed.isEmpty) return;
    shot.commitDraft(note.withText(typed));
  }
}

/// The in-canvas field for a text note.
///
/// Text needs real keyboard focus and an IME, which a `CustomPaint` cannot
/// have — so it lives in the widget layer, positioned over the canvas, and only
/// becomes an annotation once it has been typed.
class _TextEditor extends StatelessWidget {
  const _TextEditor({
    required this.note,
    required this.scale,
    required this.controller,
    required this.focusNode,
    required this.onDone,
  });

  final TextNote note;
  final double scale;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;

    return Positioned(
      left: note.anchor.dx * scale,
      top: note.anchor.dy * scale,
      width: math.min(TextNote.maxWidth, 320) * scale,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            controller.clear();
            onDone();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          maxLines: null,
          onSubmitted: (_) => onDone(),
          onTapOutside: (_) => onDone(),
          cursorColor: note.style.color,
          // Sized and coloured to match what the mark will look like once it is
          // committed, so typing is a preview rather than a form to fill in.
          style: TextStyle(
            color: note.style.color,
            fontSize: note.style.fontSize * scale,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            filled: true,
            fillColor: theme.palette.background.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

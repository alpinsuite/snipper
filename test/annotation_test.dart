import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/model/annotation.dart';

const _style = AnnotationStyle(color: ui.Color(0xFFFF0000), strokeWidth: 4);

void main() {
  group('hit testing', () {
    test('a pen stroke is hit along its line and not beside it', () {
      const stroke = PenStroke(
        id: 1,
        style: _style,
        points: <ui.Offset>[ui.Offset(10, 10), ui.Offset(90, 10)],
      );
      expect(stroke.hitTest(const ui.Offset(50, 10)), isTrue);
      expect(stroke.hitTest(const ui.Offset(50, 11)), isTrue);
      expect(stroke.hitTest(const ui.Offset(50, 40)), isFalse);
      // Past the end of the segment, not merely off its infinite line.
      expect(stroke.hitTest(const ui.Offset(140, 10)), isFalse);
    });

    test('tolerance widens the reach without moving the mark', () {
      const stroke = PenStroke(
        id: 1,
        style: _style,
        points: <ui.Offset>[ui.Offset(10, 10), ui.Offset(90, 10)],
      );
      expect(stroke.hitTest(const ui.Offset(50, 20)), isFalse);
      // At 25% zoom a four-pixel line is one pixel on screen; without this,
      // selecting anything on a zoomed-out snip is a game of chance.
      expect(stroke.hitTest(const ui.Offset(50, 20), tolerance: 20), isTrue);
    });

    test('an outlined rectangle is hit on its edge, not in its middle', () {
      const shape = RectShape(
        id: 1,
        style: _style,
        start: ui.Offset(10, 10),
        end: ui.Offset(110, 60),
      );
      expect(shape.hitTest(const ui.Offset(10, 35)), isTrue);
      expect(shape.hitTest(const ui.Offset(60, 10)), isTrue);
      // The hole in the middle is what stops a box drawn *around* something
      // from swallowing every click meant for the marks inside it.
      expect(shape.hitTest(const ui.Offset(60, 35)), isFalse);
    });

    test('a filled rectangle is hit anywhere inside it', () {
      const shape = RectShape(
        id: 1,
        style: AnnotationStyle(
          color: ui.Color(0xFFFF0000),
          strokeWidth: 4,
          filled: true,
        ),
        start: ui.Offset(10, 10),
        end: ui.Offset(110, 60),
      );
      expect(shape.hitTest(const ui.Offset(60, 35)), isTrue);
      expect(shape.hitTest(const ui.Offset(200, 35)), isFalse);
    });

    test('an outlined ellipse is hit on its curve, not in its middle', () {
      const shape = EllipseShape(
        id: 1,
        style: _style,
        start: ui.Offset(0, 0),
        end: ui.Offset(200, 100),
      );
      expect(shape.hitTest(const ui.Offset(100, 0)), isTrue);
      expect(shape.hitTest(const ui.Offset(0, 50)), isTrue);
      expect(shape.hitTest(const ui.Offset(100, 50)), isFalse);
      // The corners of the bounding box are outside the ellipse itself.
      expect(shape.hitTest(const ui.Offset(2, 2)), isFalse);
    });

    test('a redaction is hit anywhere over it', () {
      const shape = Redaction(
        id: 1,
        style: _style,
        start: ui.Offset(10, 10),
        end: ui.Offset(60, 40),
      );
      expect(shape.hitTest(const ui.Offset(35, 25)), isTrue);
      expect(shape.hitTest(const ui.Offset(80, 25)), isFalse);
    });

    test('a drag in either direction gives the same rectangle', () {
      const forward = RectShape(
        id: 1,
        style: _style,
        start: ui.Offset(10, 10),
        end: ui.Offset(110, 60),
      );
      const backward = RectShape(
        id: 2,
        style: _style,
        start: ui.Offset(110, 60),
        end: ui.Offset(10, 10),
      );
      expect(backward.rect, forward.rect);
      expect(backward.hitTest(const ui.Offset(10, 35)), isTrue);
    });
  });

  group('bounds', () {
    test('cover the stroke, not just the path', () {
      const stroke = PenStroke(
        id: 1,
        style: AnnotationStyle(color: ui.Color(0xFFFF0000), strokeWidth: 20),
        points: <ui.Offset>[ui.Offset(50, 50), ui.Offset(60, 50)],
      );
      // A bound tighter than what is drawn leaves a smear behind when the mark
      // moves, and clips it on export.
      expect(stroke.bounds.left, lessThan(50));
      expect(stroke.bounds.right, greaterThan(60));
    });

    test("an arrow's bounds allow for its head", () {
      const arrow = ArrowShape(
        id: 1,
        style: _style,
        start: ui.Offset(0, 50),
        end: ui.Offset(100, 50),
      );
      // The barbs reach back and out from the tip, well past the line itself.
      expect(arrow.bounds.top, lessThan(50 - arrow.style.strokeWidth));
      expect(arrow.bounds.right, greaterThan(100));
    });
  });

  group('moving and restyling', () {
    test('a moved mark keeps its identity and its shape', () {
      const stroke = PenStroke(
        id: 7,
        style: _style,
        points: <ui.Offset>[ui.Offset(10, 10), ui.Offset(20, 20)],
      );
      final moved = stroke.translated(const ui.Offset(5, -5));

      expect(moved.id, 7);
      expect(moved.bounds.size, stroke.bounds.size);
      expect(moved.bounds.left, stroke.bounds.left + 5);
      expect(moved.bounds.top, stroke.bounds.top - 5);
      // Immutable: the original is untouched, which is what makes an undo step
      // a list of pointers rather than a copy.
      expect(stroke.points.first, const ui.Offset(10, 10));
    });

    test('every kind can be moved', () {
      final marks = <Annotation>[
        const PenStroke(
          id: 1,
          style: _style,
          points: <ui.Offset>[ui.Offset.zero],
        ),
        const HighlighterStroke(
          id: 2,
          style: _style,
          points: <ui.Offset>[ui.Offset.zero],
        ),
        const LineShape(
          id: 3,
          style: _style,
          start: ui.Offset.zero,
          end: ui.Offset(9, 9),
        ),
        const ArrowShape(
          id: 4,
          style: _style,
          start: ui.Offset.zero,
          end: ui.Offset(9, 9),
        ),
        const RectShape(
          id: 5,
          style: _style,
          start: ui.Offset.zero,
          end: ui.Offset(9, 9),
        ),
        const EllipseShape(
          id: 6,
          style: _style,
          start: ui.Offset.zero,
          end: ui.Offset(9, 9),
        ),
        const Redaction(
          id: 7,
          style: _style,
          start: ui.Offset.zero,
          end: ui.Offset(9, 9),
        ),
        const StepBadge(
          id: 8,
          style: _style,
          centre: ui.Offset(20, 20),
          number: 1,
        ),
        const TextNote(
          id: 9,
          style: _style,
          anchor: ui.Offset.zero,
          text: 'hi',
        ),
      ];

      for (final mark in marks) {
        final moved = mark.translated(const ui.Offset(11, 13));
        expect(moved.id, mark.id, reason: '${mark.runtimeType}');
        expect(
          moved.bounds.left,
          closeTo(mark.bounds.left + 11, 0.001),
          reason: '${mark.runtimeType}',
        );
      }
    });

    test('a restyled mark keeps its geometry', () {
      const shape = RectShape(
        id: 3,
        style: _style,
        start: ui.Offset(10, 10),
        end: ui.Offset(60, 40),
      );
      final blue = shape.restyled(
        _style.copyWith(color: const ui.Color(0xFF0000FF)),
      );
      expect(blue, isA<RectShape>());
      expect((blue as DraggedAnnotation).rect, shape.rect);
      expect(blue.style.color, const ui.Color(0xFF0000FF));
      // Picking a different colour with an arrow selected is how a drawn mark
      // gets fixed, so the width must not come along for the ride.
      expect(blue.style.strokeWidth, shape.style.strokeWidth);
    });
  });
}

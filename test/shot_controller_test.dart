import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/controller/shot_controller.dart';
import 'package:snipper/model/annotation.dart';
import 'package:snipper/model/snip.dart';
import 'package:snipper/tools/annotation_draft.dart';

const _style = AnnotationStyle(color: ui.Color(0xFFFF0000), strokeWidth: 4);

Future<Snip> _snip({int width = 40, int height = 30}) async {
  final pixels = Uint8List(width * height * 4)
    ..fillRange(0, width * height * 4, 0xFF);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return Snip(
    image: await completer.future,
    source: ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
}

RectShape _rect(int id, {ui.Offset at = ui.Offset.zero}) => RectShape(
  id: id,
  style: _style,
  start: at,
  end: at + const ui.Offset(20, 10),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShotController shot;

  setUp(() async {
    shot = ShotController()..open(await _snip());
  });

  tearDown(() => shot.dispose());

  test('a fresh snip has no marks and nothing to undo', () {
    expect(shot.annotations, isEmpty);
    expect(shot.canUndo, isFalse);
    expect(shot.canRedo, isFalse);
  });

  group('drawing', () {
    test('a draft is not part of the document', () {
      shot.showDraft(_rect(1));
      expect(shot.draft, isNotNull);
      expect(shot.annotations, isEmpty);
      // Nothing to undo yet: a drag in progress is not something undo should
      // be able to land in the middle of.
      expect(shot.canUndo, isFalse);
    });

    test('a discarded draft leaves nothing behind', () {
      shot
        ..showDraft(_rect(1))
        ..discardDraft();
      expect(shot.draft, isNull);
      expect(shot.annotations, isEmpty);
      expect(shot.canUndo, isFalse);
    });

    test('a committed mark is selected and undoable', () {
      shot.commitDraft(_rect(1));
      expect(shot.annotations, hasLength(1));
      expect(shot.selectedId, 1);
      expect(shot.canUndo, isTrue);
    });

    test('ids are not reused', () {
      expect(shot.takeId(), isNot(shot.takeId()));
    });
  });

  group('history', () {
    test('undo takes a mark back and redo puts it there again', () {
      shot
        ..commitDraft(_rect(1))
        ..commitDraft(_rect(2, at: const ui.Offset(40, 0)));
      expect(shot.annotations, hasLength(2));

      shot.undo();
      expect(shot.annotations, hasLength(1));
      expect(shot.canRedo, isTrue);

      shot.redo();
      expect(shot.annotations, hasLength(2));
    });

    test('drawing after an undo discards the redo', () {
      shot
        ..commitDraft(_rect(1))
        ..undo();
      expect(shot.canRedo, isTrue);

      shot.commitDraft(_rect(2));
      expect(shot.canRedo, isFalse);
    });

    test('a move is one step, however many pointer events it took', () {
      shot.commitDraft(_rect(1));
      final before = _rect(1).bounds.left;

      // The first move of a drag records; the rest do not.
      shot
        ..move(1, const ui.Offset(5, 0), record: true)
        ..move(1, const ui.Offset(5, 0))
        ..move(1, const ui.Offset(5, 0));
      expect(shot.annotations.single.bounds.left, before + 15);

      shot.undo();
      expect(shot.annotations.single.bounds.left, before);
    });

    test('deleting is undoable', () {
      shot
        ..commitDraft(_rect(1))
        ..select(1)
        ..deleteSelected();
      expect(shot.annotations, isEmpty);
      expect(shot.selectedId, isNull);

      shot.undo();
      expect(shot.annotations, hasLength(1));
    });

    test('opening a new snip clears the history with the marks', () async {
      shot
        ..commitDraft(_rect(1))
        ..open(await _snip(width: 10, height: 10));
      expect(shot.annotations, isEmpty);
      expect(shot.canUndo, isFalse);
      expect(shot.canRedo, isFalse);
    });
  });

  group('selection', () {
    test('the topmost mark wins a click', () {
      shot
        ..commitDraft(_rect(1))
        ..commitDraft(_rect(2));
      // Both are in the same place; the later one is the one on top, and the
      // one being looked at.
      expect(shot.hitTest(const ui.Offset(0, 0))?.id, 2);
    });

    test('a click on nothing finds nothing', () {
      shot.commitDraft(_rect(1));
      expect(shot.hitTest(const ui.Offset(300, 300)), isNull);
    });
  });

  group('step numbering', () {
    test('counts up as badges are added', () {
      expect(shot.nextStepNumber, 1);
      shot.commitDraft(
        const StepBadge(
          id: 1,
          style: _style,
          centre: ui.Offset(5, 5),
          number: 1,
        ),
      );
      expect(shot.nextStepNumber, 2);
    });

    test('reuses a number after the badge that had it is deleted', () {
      for (var i = 1; i <= 3; i++) {
        shot.commitDraft(
          StepBadge(
            id: i,
            style: _style,
            centre: ui.Offset(i * 10, 5),
            number: i,
          ),
        );
      }
      expect(shot.nextStepNumber, 4);

      shot
        ..select(3)
        ..deleteSelected();
      // Counted from what is on the image rather than kept as a running total,
      // so deleting the last step and drawing another gives 3 again — not 4.
      expect(shot.nextStepNumber, 3);
    });
  });

  group('a draft', () {
    test('a shape needs a real drag before it counts', () {
      final draft = AnnotationDraft(
        tool: ToolId.rectangle,
        style: _style,
        id: 1,
        start: ui.Offset.zero,
      )..extend(const ui.Offset(1, 1));
      expect(draft.isCommittable, isFalse);

      draft.extend(const ui.Offset(40, 30));
      expect(draft.isCommittable, isTrue);
    });

    test('shift squares a rectangle', () {
      final draft = AnnotationDraft(
        tool: ToolId.rectangle,
        style: _style,
        id: 1,
        start: ui.Offset.zero,
      )..extend(const ui.Offset(100, 30), shift: true);
      final rect = (draft.annotation! as RectShape).rect;
      expect(rect.width, rect.height);
    });

    test('shift snaps a line to 45 degrees', () {
      final draft = AnnotationDraft(
        tool: ToolId.line,
        style: _style,
        id: 1,
        start: ui.Offset.zero,
      )..extend(const ui.Offset(100, 8), shift: true);
      final line = draft.annotation! as LineShape;
      // Nearly horizontal, so it snaps to exactly horizontal.
      expect(line.end.dy, closeTo(0, 0.001));
      expect(line.end.dx, closeTo(100, 0.5));
    });

    test('a step badge is placed by a click, with no drag needed', () {
      final draft = AnnotationDraft(
        tool: ToolId.step,
        style: _style,
        id: 1,
        start: const ui.Offset(30, 30),
        stepNumber: 4,
      );
      expect(draft.isCommittable, isTrue);
      expect((draft.annotation! as StepBadge).number, 4);
    });

    test('the select tool never produces a mark', () {
      final draft = AnnotationDraft(
        tool: ToolId.select,
        style: _style,
        id: 1,
        start: ui.Offset.zero,
      )..extend(const ui.Offset(90, 90));
      expect(draft.annotation, isNull);
      expect(draft.isCommittable, isFalse);
    });
  });
}

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/model/display.dart';

Display _display(String id, ui.Rect bounds, {bool primary = false}) =>
    Display(id: id, bounds: bounds, scaleFactor: 1, isPrimary: primary);

void main() {
  // A laptop with an external monitor placed to its left: the arrangement that
  // produces a negative origin, and the one worth testing against.
  final left = _display('left', const ui.Rect.fromLTWH(-1920, 0, 1920, 1080));
  final main = _display(
    'main',
    const ui.Rect.fromLTWH(0, 0, 2560, 1440),
    primary: true,
  );
  final desktop = VirtualDesktop(
    bounds: const ui.Rect.fromLTRB(-1920, 0, 2560, 1440),
    displays: <Display>[left, main],
  );

  test('the primary display is the one flagged', () {
    expect(desktop.primary, main);
  });

  test('a point on each monitor finds that monitor', () {
    expect(desktop.displayAt(const ui.Offset(-1000, 500))?.id, 'left');
    expect(desktop.displayAt(const ui.Offset(1000, 500))?.id, 'main');
  });

  test('the dead space of an L-shaped layout belongs to nobody', () {
    // The left monitor is 1080 tall and the main one 1440, so the strip below
    // the left monitor is inside the virtual desktop and on no display at all.
    expect(desktop.bounds.contains(const ui.Offset(-1000, 1300)), isTrue);
    expect(desktop.displayAt(const ui.Offset(-1000, 1300)), isNull);
  });

  test('a mirrored pair returns one of them rather than asserting', () {
    final mirrored = VirtualDesktop(
      bounds: const ui.Rect.fromLTWH(0, 0, 1920, 1080),
      displays: <Display>[
        _display('a', const ui.Rect.fromLTWH(0, 0, 1920, 1080), primary: true),
        _display('b', const ui.Rect.fromLTWH(0, 0, 1920, 1080)),
      ],
    );
    expect(mirrored.displayAt(const ui.Offset(10, 10))?.id, 'b');
  });

  test('with nothing flagged primary the first display stands in', () {
    final none = VirtualDesktop(
      bounds: const ui.Rect.fromLTWH(0, 0, 800, 600),
      displays: <Display>[
        _display('only', const ui.Rect.fromLTWH(0, 0, 800, 600)),
      ],
    );
    expect(none.primary?.id, 'only');
  });

  test('an empty enumeration has no primary rather than throwing', () {
    const empty = VirtualDesktop(bounds: ui.Rect.zero, displays: <Display>[]);
    expect(empty.primary, isNull);
  });
}

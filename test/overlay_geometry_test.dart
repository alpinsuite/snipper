import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/ops/overlay_geometry.dart';

/// The geometry for a desktop shown at [scale] physical pixels per logical one,
/// which is what the overlay produces once the window is where it was put.
OverlayGeometry at(ui.Rect bounds, double scale) => OverlayGeometry(
  bounds: bounds,
  logicalSize: ui.Size(bounds.width / scale, bounds.height / scale),
);

void main() {
  group('a single 1920x1080 display at 1x', () {
    final geometry = at(const ui.Rect.fromLTWH(0, 0, 1920, 1080), 1);

    test('logical size matches the desktop', () {
      expect(geometry.logicalSize, const ui.Size(1920, 1080));
      expect(geometry.scaleX, 1);
      expect(geometry.scaleY, 1);
    });

    test('a drag maps straight through', () {
      final rect = geometry.dragRect(
        const ui.Offset(100, 200),
        const ui.Offset(300, 500),
      );
      expect(
        geometry.toFrameRect(rect),
        const ui.Rect.fromLTRB(100, 200, 300, 500),
      );
    });

    test('a drag up and to the left gives the same rectangle', () {
      final forward = geometry.dragRect(
        const ui.Offset(100, 200),
        const ui.Offset(300, 500),
      );
      final backward = geometry.dragRect(
        const ui.Offset(300, 500),
        const ui.Offset(100, 200),
      );
      expect(backward, forward);
    });

    test('a drag past the edge is clamped rather than followed', () {
      final rect = geometry.dragRect(
        const ui.Offset(-500, -500),
        const ui.Offset(4000, 4000),
      );
      expect(rect, const ui.Rect.fromLTRB(0, 0, 1920, 1080));
    });

    test('a click without a drag is not a selection', () {
      final rect = geometry.dragRect(
        const ui.Offset(640, 400),
        const ui.Offset(641, 401),
      );
      expect(geometry.isSelectable(rect), isFalse);
    });

    test('a small but deliberate drag is a selection', () {
      final rect = geometry.dragRect(
        const ui.Offset(640, 400),
        const ui.Offset(660, 420),
      );
      expect(geometry.isSelectable(rect), isTrue);
    });
  });

  group('a secondary display to the left, so the origin is negative', () {
    // The layout that breaks every screenshot tool at least once: a 1920x1080
    // monitor placed left of the primary one, putting the virtual desktop's
    // left edge at -1920.
    final geometry = at(const ui.Rect.fromLTRB(-1920, 0, 1920, 1080), 1);

    test('the frame is the full width of both monitors', () {
      expect(geometry.logicalSize, const ui.Size(3840, 1080));
    });

    test('the desktop origin is the bitmap origin', () {
      expect(
        geometry.physicalToFrame(const ui.Rect.fromLTRB(-1920, 0, -1820, 100)),
        const ui.Rect.fromLTRB(0, 0, 100, 100),
      );
    });

    test('a point on the primary monitor lands past the secondary', () {
      expect(
        geometry.physicalToFrame(const ui.Rect.fromLTRB(0, 0, 100, 100)),
        const ui.Rect.fromLTRB(1920, 0, 2020, 100),
      );
    });

    test('a logical selection is already relative to the overlay corner', () {
      // No second subtraction: logical (0,0) is the overlay's own top-left,
      // which is the bitmap's top-left, whatever the desktop calls it.
      final rect = geometry.dragRect(ui.Offset.zero, const ui.Offset(50, 50));
      expect(geometry.toFrameRect(rect), const ui.Rect.fromLTRB(0, 0, 50, 50));
    });

    test('logical and physical round-trip', () {
      const physical = ui.Offset(-1500, 250);
      expect(geometry.toPhysical(geometry.toLogical(physical)), physical);
    });
  });

  group('fractional scales', () {
    for (final scale in <double>[1.25, 1.5, 1.75, 2]) {
      final geometry = at(const ui.Rect.fromLTWH(0, 0, 2560, 1440), scale);

      test('at ${scale}x the origin floors and the far edge ceils', () {
        // Deliberately a position that lands between pixels at 1.25 and 1.75.
        final frame = geometry.toFrameRect(
          const ui.Rect.fromLTRB(10.4, 20.6, 100.3, 200.9),
        );
        expect(frame.left, (10.4 * scale).floorToDouble());
        expect(frame.top, (20.6 * scale).floorToDouble());
        expect(frame.right, (100.3 * scale).ceilToDouble());
        expect(frame.bottom, (200.9 * scale).ceilToDouble());
      });

      test('at ${scale}x a selection never loses a pixel it enclosed', () {
        const logical = ui.Rect.fromLTRB(10.4, 20.6, 100.3, 200.9);
        final frame = geometry.toFrameRect(logical);
        expect(frame.width, greaterThanOrEqualTo(logical.width * scale));
        expect(frame.height, greaterThanOrEqualTo(logical.height * scale));
      });

      test('at ${scale}x the far edge never runs past the bitmap', () {
        final whole = geometry.dragRect(
          ui.Offset.zero,
          ui.Offset(geometry.logicalSize.width, geometry.logicalSize.height),
        );
        expect(
          geometry.toFrameRect(whole),
          const ui.Rect.fromLTRB(0, 0, 2560, 1440),
        );
      });
    }
  });

  group('mixed scales', () {
    // A 1920x1080 laptop at 150% beside a 2560x1440 monitor at 100%. Windows
    // gives the overlay window one ratio; the mapping has to stay 1:1 anyway,
    // which is the whole reason the frozen bitmap is in physical pixels.
    final geometry = at(const ui.Rect.fromLTRB(0, 0, 4480, 1440), 1.5);

    test('the far corner of the second monitor is reachable', () {
      final size = geometry.logicalSize;
      final frame = geometry.toFrameRect(
        ui.Rect.fromLTRB(
          size.width - 10,
          size.height - 10,
          size.width,
          size.height,
        ),
      );
      expect(frame.right, 4480);
      expect(frame.bottom, 1440);
    });

    test('a physical rect on the second monitor maps without scaling', () {
      expect(
        geometry.physicalToFrame(const ui.Rect.fromLTRB(1920, 0, 4480, 1440)),
        const ui.Rect.fromLTRB(1920, 0, 4480, 1440),
      );
    });
  });

  group('while the window is still catching up', () {
    // The case that produced a black screen: the overlay is laid out at the
    // ordinary window size for a frame or two before the platform finishes
    // resizing it to the desktop. Drawing something slightly wrong for one
    // frame is fine; refusing to draw was not.
    test('the scale comes from the size the frame is painted into', () {
      const geometry = OverlayGeometry(
        bounds: ui.Rect.fromLTWH(0, 0, 1920, 1080),
        logicalSize: ui.Size(864, 576),
      );
      // Selecting the whole of what is on screen selects the whole bitmap, at
      // whatever size that happens to be.
      final whole = geometry.dragRect(
        ui.Offset.zero,
        const ui.Offset(864, 576),
      );
      expect(
        geometry.toFrameRect(whole),
        const ui.Rect.fromLTRB(0, 0, 1920, 1080),
      );
    });

    test('the two axes are allowed to disagree mid-resize', () {
      const geometry = OverlayGeometry(
        bounds: ui.Rect.fromLTWH(0, 0, 1920, 1080),
        logicalSize: ui.Size(960, 1080),
      );
      expect(geometry.scaleX, 2);
      expect(geometry.scaleY, 1);
    });
  });
}

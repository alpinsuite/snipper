import 'dart:ui' as ui;

/// One monitor, in physical pixels.
///
/// Physical rather than logical throughout, because a screenshot is physical
/// pixels and nothing else. The [scaleFactor] is carried so the interface can
/// say "3840x2160 at 150%" when it lists monitors, not so anything divides by
/// it — the moment a coordinate here is scaled it stops matching the bitmap.
class Display {
  const Display({
    required this.id,
    required this.bounds,
    required this.scaleFactor,
    required this.isPrimary,
  });

  /// Opaque, platform-assigned, and stable only within one enumeration. It
  /// identifies a monitor inside a [VirtualDesktop]; it is not persisted.
  final String id;

  /// Position and size in the virtual desktop's physical coordinate space.
  /// The origin is not necessarily positive — see [VirtualDesktop].
  final ui.Rect bounds;

  /// 1.0 at 96 DPI, 1.5 at 150%, and so on.
  final double scaleFactor;

  final bool isPrimary;

  @override
  String toString() =>
      'Display($id, ${bounds.width.toInt()}x${bounds.height.toInt()} '
      '@ ${bounds.left.toInt()},${bounds.top.toInt()}, '
      'x$scaleFactor${isPrimary ? ', primary' : ''})';
}

/// Every monitor, and the rectangle that encloses them all.
///
/// **The origin is routinely negative.** A monitor placed to the left of the
/// primary one puts the virtual desktop's left edge at -1920, and Windows
/// reports exactly that. Every mapping from a desktop coordinate to a pixel in
/// the captured bitmap has to subtract [bounds] `.topLeft`; forgetting to is the
/// single likeliest bug in this whole feature, which is why the subtraction
/// lives in one place — `OverlayGeometry.toFrameRect` — and has its own tests.
class VirtualDesktop {
  const VirtualDesktop({required this.bounds, required this.displays});

  /// The union of every display, in physical pixels.
  final ui.Rect bounds;

  final List<Display> displays;

  Display? get primary {
    for (final display in displays) {
      if (display.isPrimary) return display;
    }
    return displays.isEmpty ? null : displays.first;
  }

  /// The display containing [point], or null for a point in the dead space of
  /// an L-shaped arrangement.
  ///
  /// Later displays win an overlap. Monitors are not supposed to overlap, but a
  /// mirrored pair reports two identical rectangles and something has to be
  /// returned rather than asserted.
  Display? displayAt(ui.Offset point) {
    Display? found;
    for (final display in displays) {
      if (display.bounds.contains(point)) found = display;
    }
    return found;
  }

  @override
  String toString() =>
      'VirtualDesktop(${bounds.width.toInt()}x${bounds.height.toInt()} '
      '@ ${bounds.left.toInt()},${bounds.top.toInt()}, '
      '${displays.length} display(s))';
}

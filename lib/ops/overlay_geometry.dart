import 'dart:ui' as ui;

/// The arithmetic between what the pointer does and what the bitmap holds.
///
/// All of it lives here rather than in the overlay widget, so it can be tested
/// without a window — which matters, because none of it can be checked by
/// looking at a screenshot. A selection one pixel out looks exactly like a
/// selection that is right.
///
/// Three coordinate spaces meet in this class:
///
/// - **Logical** — Flutter's, what a `PointerEvent` reports, sized by
///   [logicalSize].
/// - **Physical desktop** — what the platform calls a screen coordinate. Its
///   origin is [bounds] `.topLeft` and **is routinely negative**: a monitor to
///   the left of the primary one puts it at -1920.
/// - **Frame** — an index into the captured bitmap, always starting at (0, 0).
///
/// The scale between the first two is taken from [logicalSize] — the size the
/// frozen frame is actually being painted into — and **not** from the window's
/// `devicePixelRatio`. Those two agree once the overlay has settled, but taking
/// the ratio directly means the mapping is right from the first frame, and that
/// there is no state where the overlay has to refuse to draw because it is not
/// sure yet. That refusal was a black screen the size of the desktop.
class OverlayGeometry {
  const OverlayGeometry({required this.bounds, required this.logicalSize});

  /// The virtual desktop in physical pixels, origin included. `bounds.size` is
  /// also the captured bitmap's size in pixels.
  final ui.Rect bounds;

  /// The size the frame is being painted into, in Flutter's own units.
  final ui.Size logicalSize;

  /// Physical pixels per logical pixel, across and down.
  ///
  /// Kept as two numbers rather than one. They are equal whenever the window is
  /// where it was put, but during a resize they are not, and a single ratio
  /// would put the pointer somewhere the picture is not for exactly as long as
  /// that lasts.
  double get scaleX => bounds.width / logicalSize.width;
  double get scaleY => bounds.height / logicalSize.height;

  /// A logical point inside the overlay, as a physical desktop coordinate.
  ui.Offset toPhysical(ui.Offset logical) => ui.Offset(
    bounds.left + logical.dx * scaleX,
    bounds.top + logical.dy * scaleY,
  );

  /// The inverse of [toPhysical].
  ui.Offset toLogical(ui.Offset physical) => ui.Offset(
    (physical.dx - bounds.left) / scaleX,
    (physical.dy - bounds.top) / scaleY,
  );

  /// The rectangle a drag between [from] and [to] describes, in logical units.
  ///
  /// Normalised, so dragging up-and-left gives the same rectangle as dragging
  /// down-and-right, and clamped to the overlay: a pointer can be dragged past
  /// the edge of the desktop and the selection must not follow it there.
  ui.Rect dragRect(ui.Offset from, ui.Offset to) {
    final rect = ui.Rect.fromPoints(from, to);
    return ui.Rect.fromLTRB(
      rect.left.clamp(0.0, logicalSize.width),
      rect.top.clamp(0.0, logicalSize.height),
      rect.right.clamp(0.0, logicalSize.width),
      rect.bottom.clamp(0.0, logicalSize.height),
    );
  }

  /// The pixels of the captured bitmap a logical selection covers.
  ///
  /// The origin is floored and the far edge ceiled, so the result is never
  /// *narrower* than what was shown — a selection drawn around something must
  /// contain all of it. Rounding the width independently of the origin is the
  /// tempting shortcut, and it drifts by a pixel on one edge at fractional
  /// scales, which is exactly what 125% and 150% displays produce.
  ///
  /// Note there is no subtraction of `bounds.topLeft` here: a logical
  /// coordinate is already relative to the overlay's own corner, and the bitmap
  /// starts at that same corner. The subtraction belongs to [physicalToFrame],
  /// which starts from a screen coordinate instead.
  ui.Rect toFrameRect(ui.Rect logical) => _clampToFrame(
    ui.Rect.fromLTRB(
      (logical.left * scaleX).floorToDouble(),
      (logical.top * scaleY).floorToDouble(),
      (logical.right * scaleX).ceilToDouble(),
      (logical.bottom * scaleY).ceilToDouble(),
    ),
  );

  /// A physical desktop rectangle as bitmap pixels.
  ///
  /// **This is where the negative origin is dealt with.** A monitor at
  /// x = -1920 produces screen coordinates that are meaningless as bitmap
  /// indices until [bounds] `.topLeft` comes off them.
  ui.Rect physicalToFrame(ui.Rect physical) {
    final rect = physical.shift(-bounds.topLeft);
    return _clampToFrame(
      ui.Rect.fromLTRB(
        rect.left.floorToDouble(),
        rect.top.floorToDouble(),
        rect.right.ceilToDouble(),
        rect.bottom.ceilToDouble(),
      ),
    );
  }

  /// Whether a selection is big enough to mean anything.
  ///
  /// A click without a drag produces a rectangle of nearly zero area, and
  /// treating that as a snip hands back a useless image while hiding the fact
  /// that the person meant to cancel. Four pixels each way is small enough that
  /// no deliberate selection is ever refused.
  bool isSelectable(ui.Rect logical) {
    final frame = toFrameRect(logical);
    return frame.width >= minimumFrameExtent &&
        frame.height >= minimumFrameExtent;
  }

  static const double minimumFrameExtent = 4;

  ui.Rect _clampToFrame(ui.Rect rect) {
    final left = rect.left.clamp(0.0, bounds.width);
    final top = rect.top.clamp(0.0, bounds.height);
    return ui.Rect.fromLTRB(
      left,
      top,
      rect.right.clamp(left, bounds.width),
      rect.bottom.clamp(top, bounds.height),
    );
  }
}

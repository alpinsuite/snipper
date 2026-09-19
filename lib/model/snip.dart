import 'dart:ui' as ui;

/// One captured image, and where on the desktop it came from.
///
/// Whoever holds a [Snip] owns its [image] and disposes it when it is replaced.
/// `ui.Image` is refcounted and a screenshot is several megabytes, so leaking
/// one is not academic.
class Snip {
  const Snip({required this.image, required this.source});

  final ui.Image image;

  /// The physical desktop rectangle these pixels were taken from. Kept because
  /// it is the only way to say anything true about where a snip came from, and
  /// because its origin may be negative.
  final ui.Rect source;

  int get width => image.width;
  int get height => image.height;

  void dispose() => image.dispose();

  @override
  String toString() => 'Snip($width x $height from $source)';
}

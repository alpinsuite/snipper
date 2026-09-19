import 'dart:typed_data';

/// The byte order of a raw frame as the platform handed it over.
enum PixelOrder {
  /// Blue, green, red, alpha. What a Windows 32-bit DIB and an X11 `ZPixmap`
  /// on a little-endian machine both produce.
  bgra,

  /// Red, green, blue, alpha.
  rgba,
}

/// A raw frame straight from a platform capture, before anything decodes it.
///
/// This type exists so the two capture backends hand back the same thing and
/// the awkward parts are normalised in one tested place rather than twice.
/// There are three of those parts and every one of them has bitten a screenshot
/// tool before:
///
/// 1. **The rows are padded.** X11 aligns each row of an `XImage`, so
///    `bytesPerRow` is regularly larger than `width * 4` and a straight copy
///    comes out sheared.
/// 2. **The rows may run bottom-up.** A Windows DIB does by default; this asks
///    for top-down, but the flag is carried rather than assumed.
/// 3. **The alpha byte is zero.** `BitBlt` from a screen device context does
///    not write alpha, so a buffer that looks perfectly correct in a debugger
///    decodes to a fully transparent image. Forcing it opaque is not optional.
class RasterFrame {
  RasterFrame({
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bytes,
    this.order = PixelOrder.bgra,
    this.topDown = true,
  }) : assert(width > 0 && height > 0, 'a frame with no pixels'),
       assert(
         bytesPerRow >= width * 4,
         'a row cannot be narrower than its pixels',
       ),
       assert(
         bytes.length >= bytesPerRow * height,
         'the buffer is shorter than the frame it claims to hold',
       );

  final int width;
  final int height;

  /// Distance between the starts of two consecutive rows. May exceed
  /// `width * 4`.
  final int bytesPerRow;

  final Uint8List bytes;
  final PixelOrder order;

  /// False when the first row in [bytes] is the *bottom* of the image.
  final bool topDown;

  /// Tightly packed, top-down, BGRA, opaque — what
  /// `ui.decodeImageFromPixels` wants for `PixelFormat.bgra8888`.
  ///
  /// The row copies are `setRange`, which is a memory move rather than a Dart
  /// loop; only the per-pixel pass is interpreted, and it works on 32-bit words
  /// rather than bytes. At 5120x1440 that is about seven million iterations,
  /// which is single-digit milliseconds and happens once per capture.
  ///
  /// Reading four bytes as one word assumes a little-endian host, which every
  /// platform Flutter targets is.
  Uint8List toPackedBgra8888() {
    final rowBytes = width * 4;
    final packed = Uint8List(rowBytes * height);
    for (var y = 0; y < height; y++) {
      final sourceRow = topDown ? y : height - 1 - y;
      final start = sourceRow * bytesPerRow;
      packed.setRange(y * rowBytes, (y + 1) * rowBytes, bytes, start);
    }

    final words = packed.buffer.asUint32List();
    if (order == PixelOrder.rgba) {
      for (var i = 0; i < words.length; i++) {
        final word = words[i];
        words[i] =
            0xFF000000 |
            ((word & 0x00FF0000) >> 16) |
            (word & 0x0000FF00) |
            ((word & 0x000000FF) << 16);
      }
    } else {
      for (var i = 0; i < words.length; i++) {
        words[i] |= 0xFF000000;
      }
    }
    return packed;
  }
}

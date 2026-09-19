import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/model/raster_frame.dart';

/// The BGRA bytes of one pixel, as a platform buffer holds them.
Uint8List _bgra(int b, int g, int r, [int a = 0]) =>
    Uint8List.fromList(<int>[b, g, r, a]);

/// Reads the pixel at [x], [y] out of a packed BGRA buffer.
({int b, int g, int r, int a}) _pixel(
  Uint8List packed,
  int width,
  int x,
  int y,
) {
  final i = (y * width + x) * 4;
  return (b: packed[i], g: packed[i + 1], r: packed[i + 2], a: packed[i + 3]);
}

void main() {
  test('alpha is forced opaque', () {
    // BitBlt from a screen device context leaves alpha at zero. Decoding that
    // as bgra8888 gives a completely transparent image, which is the most
    // confusing possible symptom: the buffer looks right in a debugger.
    final frame = RasterFrame(
      width: 1,
      height: 1,
      bytesPerRow: 4,
      bytes: _bgra(0x10, 0x20, 0x30),
    );
    expect(_pixel(frame.toPackedBgra8888(), 1, 0, 0).a, 0xFF);
  });

  test('padded rows are packed without shearing', () {
    // X11 aligns each row, so bytesPerRow regularly exceeds width * 4. Copying
    // straight through produces a picture that leans further right every row.
    const width = 3;
    const height = 2;
    const stride = 16; // 12 bytes of pixels, 4 of padding
    final bytes = Uint8List(stride * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * stride + x * 4;
        bytes[i] = x; // blue carries the column
        bytes[i + 1] = y; // green carries the row
        bytes[i + 2] = 0;
      }
      // Junk in the padding, so a bad copy is visible rather than plausible.
      bytes[y * stride + 12] = 0xEE;
    }

    final packed = RasterFrame(
      width: width,
      height: height,
      bytesPerRow: stride,
      bytes: bytes,
    ).toPackedBgra8888();

    expect(packed.length, width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = _pixel(packed, width, x, y);
        expect(pixel.b, x, reason: 'column at ($x, $y)');
        expect(pixel.g, y, reason: 'row at ($x, $y)');
      }
    }
  });

  test('a bottom-up frame is flipped', () {
    // The default for a Windows DIB. This asks for top-down, but the flag is
    // carried rather than assumed.
    const width = 1;
    const height = 3;
    final bytes = Uint8List(width * 4 * height);
    for (var row = 0; row < height; row++) {
      bytes[row * 4] = row; // blue carries the source row index
    }

    final packed = RasterFrame(
      width: width,
      height: height,
      bytesPerRow: width * 4,
      bytes: bytes,
      topDown: false,
    ).toPackedBgra8888();

    // Source row 0 is the bottom of the image, so it must come out last.
    expect(_pixel(packed, width, 0, 0).b, 2);
    expect(_pixel(packed, width, 0, 1).b, 1);
    expect(_pixel(packed, width, 0, 2).b, 0);
  });

  test('an RGBA frame comes out as BGRA', () {
    final frame = RasterFrame(
      width: 1,
      height: 1,
      bytesPerRow: 4,
      // Bytes in RGBA order: red 0x11, green 0x22, blue 0x33.
      bytes: Uint8List.fromList(<int>[0x11, 0x22, 0x33, 0x00]),
      order: PixelOrder.rgba,
    );
    final pixel = _pixel(frame.toPackedBgra8888(), 1, 0, 0);
    expect(pixel.b, 0x33);
    expect(pixel.g, 0x22);
    expect(pixel.r, 0x11);
    expect(pixel.a, 0xFF);
  });

  test('a BGRA frame keeps its channels where they were', () {
    final frame = RasterFrame(
      width: 1,
      height: 1,
      bytesPerRow: 4,
      bytes: _bgra(0x33, 0x22, 0x11),
    );
    final pixel = _pixel(frame.toPackedBgra8888(), 1, 0, 0);
    expect(pixel.b, 0x33);
    expect(pixel.g, 0x22);
    expect(pixel.r, 0x11);
  });

  test('padding, bottom-up and RGBA all at once', () {
    const width = 2;
    const height = 2;
    const stride = 12;
    final bytes = Uint8List(stride * height);
    // Source row 0 (the image's bottom): red ramp.
    bytes.setRange(0, 8, <int>[0x10, 0, 0, 0, 0x20, 0, 0, 0]);
    // Source row 1 (the image's top): another.
    bytes.setRange(stride, stride + 8, <int>[0x30, 0, 0, 0, 0x40, 0, 0, 0]);

    final packed = RasterFrame(
      width: width,
      height: height,
      bytesPerRow: stride,
      bytes: bytes,
      order: PixelOrder.rgba,
      topDown: false,
    ).toPackedBgra8888();

    // Red arrived in byte 0 and must leave in byte 2, and the rows must swap.
    expect(_pixel(packed, width, 0, 0).r, 0x30);
    expect(_pixel(packed, width, 1, 0).r, 0x40);
    expect(_pixel(packed, width, 0, 1).r, 0x10);
    expect(_pixel(packed, width, 1, 1).r, 0x20);
    expect(_pixel(packed, width, 0, 0).b, 0);
  });
}

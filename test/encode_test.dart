import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:snipper/ops/encode.dart';

/// A small image with a distinct colour in each corner, so a round trip that
/// flips or rotates it is visible in the assertions rather than plausible.
Future<ui.Image> _corners() {
  const width = 4;
  const height = 4;
  final pixels = Uint8List(width * height * 4);
  void set(int x, int y, int b, int g, int r) {
    final i = (y * width + x) * 4;
    pixels[i] = b;
    pixels[i + 1] = g;
    pixels[i + 2] = r;
    pixels[i + 3] = 0xFF;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      set(x, y, 0x80, 0x80, 0x80);
    }
  }
  set(0, 0, 0x00, 0x00, 0xFF); // top-left red
  set(3, 0, 0x00, 0xFF, 0x00); // top-right green
  set(0, 3, 0xFF, 0x00, 0x00); // bottom-left blue

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG keeps every pixel exactly', () async {
    final source = await _corners();
    final bytes = await Encode.encode(source, SnipFormat.png);
    final decoded = img.decodePng(bytes)!;

    expect(decoded.width, 4);
    expect(decoded.height, 4);
    // Lossless, so the corners come back untouched — and in the right corners,
    // which is what catches a channel swap or a flipped row order.
    expect(decoded.getPixel(0, 0).r, 0xFF);
    expect(decoded.getPixel(0, 0).g, 0x00);
    expect(decoded.getPixel(3, 0).g, 0xFF);
    expect(decoded.getPixel(0, 3).b, 0xFF);
    expect(decoded.getPixel(0, 0).a, 0xFF);
  });

  test('JPEG comes back the same size and roughly the same colours', () async {
    final source = await _corners();
    final bytes = await Encode.encode(source, SnipFormat.jpeg);
    final decoded = img.decodeJpg(bytes)!;

    expect(decoded.width, 4);
    expect(decoded.height, 4);
    // Lossy, and a 4x4 image is all edges, so this only asserts the corner is
    // recognisably red rather than exactly it. What it is really checking is
    // that the channels did not get swapped on the way through package:image.
    final corner = decoded.getPixel(0, 0);
    expect(corner.r, greaterThan(corner.b));
    expect(corner.r, greaterThan(corner.g));
  });

  test('a lower quality makes a smaller file', () async {
    // Not a size assertion for its own sake: it proves the quality argument is
    // actually reaching the encoder rather than being dropped.
    final source = await _corners();
    final high = await Encode.encode(source, SnipFormat.jpeg, jpegQuality: 95);
    final low = await Encode.encode(source, SnipFormat.jpeg, jpegQuality: 20);
    expect(low.length, lessThan(high.length));
  });
}

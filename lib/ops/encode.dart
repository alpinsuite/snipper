import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// What a snip can be written as.
enum SnipFormat {
  /// Lossless, and what a screenshot should be by default: text and interface
  /// edges are exactly the kind of hard-edged content JPEG makes a mess of.
  png,

  /// For when the file has to be small and the content is a photograph, or when
  /// something downstream will not take a PNG.
  jpeg;

  String get extension => switch (this) {
    SnipFormat.png => 'png',
    SnipFormat.jpeg => 'jpg',
  };

  /// Every extension that should open as this format, lower case and without
  /// the dot — a save dialog offers one, but a person may type the other.
  List<String> get extensions => switch (this) {
    SnipFormat.png => const <String>['png'],
    SnipFormat.jpeg => const <String>['jpg', 'jpeg'],
  };

  static SnipFormat forPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return SnipFormat.png;
    final extension = path.substring(dot + 1).toLowerCase();
    for (final format in SnipFormat.values) {
      if (format.extensions.contains(extension)) return format;
    }
    return SnipFormat.png;
  }
}

/// Turning a rendered image into bytes.
///
/// PNG comes out of `dart:ui` directly, which is both faster and better than
/// re-encoding through `package:image`: the engine's encoder is native, and the
/// pixels are already where it wants them. JPEG has no `dart:ui` encoder, so
/// that one goes the long way round.
abstract final class Encode {
  /// The default JPEG quality.
  ///
  /// High, deliberately. A screenshot is mostly text and flat interface colour,
  /// which is what JPEG is worst at, and anyone choosing JPEG for one has a
  /// reason that is not "as small as possible".
  static const int defaultJpegQuality = 92;

  static Future<Uint8List> encode(
    ui.Image image,
    SnipFormat format, {
    int jpegQuality = defaultJpegQuality,
  }) async {
    switch (format) {
      case SnipFormat.png:
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('the engine would not encode a PNG');
        }
        return data.buffer.asUint8List();

      case SnipFormat.jpeg:
        // Straight RGBA out of the engine, then package:image on top. The
        // intermediate copy is the price of there being no native encoder.
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) {
          throw StateError('the engine would not hand over its pixels');
        }
        final raw = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: data.buffer,
          numChannels: 4,
        );
        return img.encodeJpg(raw, quality: jpegQuality);
    }
  }
}

// Draws the application icon and writes every file the platforms need.
//
// The mark is the marquee: four corner brackets around an empty middle, the
// same picture as `SlateIcons.regionSelect` and as the band the overlay draws
// while a region is being chosen. It is inverted onto an accent badge, because
// a launcher icon sits on an unknown background and a transparent hairline
// glyph disappears against half of them.
//
// Generated rather than drawn by hand so the sizes stay in step with each other
// and with the palette. Re-run after any change to the mark:
//
//   dart run tools/make_icons.dart
//
// Writes:
//   windows/runner/resources/app_icon.ico   the Windows executable's icon
//   assets/icon/snipper.png                 512px, for the Linux desktop entry
//   packaging/icons/snipper-<size>.png      the hicolor sizes a .desktop needs
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// `SlatePalette.dark.accent`, the one colour the interface leans on.
final img.Color _accent = img.ColorRgba8(0xE0, 0xA3, 0x3E, 0xFF);

/// `SlatePalette.dark.onAccent` — what is legible on top of it.
final img.Color _ink = img.ColorRgba8(0x1B, 0x12, 0x06, 0xFF);

/// The icon at [size] pixels square, with smooth edges.
///
/// `package:image` draws hard-edged shapes, so the badge comes out visibly
/// jagged at exactly the sizes a launcher shows. Drawing four times over and
/// averaging down is the cheapest antialiasing there is, and it costs nothing
/// here: this runs once, offline.
img.Image draw(int size) {
  const supersample = 4;
  final large = _drawAliased(size * supersample);
  return img.copyResize(
    large,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
}

/// The drawing itself, at whatever resolution it is handed.
///
/// Everything is expressed as a fraction of [size] so the 16 px favicon and the
/// 512 px desktop icon are the same drawing rather than two that drifted.
img.Image _drawAliased(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  // The badge, with a real margin around it. Filling the tile edge to edge
  // makes an icon sit larger than everything beside it in a taskbar, and puts
  // its corners hard against whatever the bar is painted in.
  final inset = (size * 0.085).round();
  img.fillRect(
    image,
    x1: inset,
    y1: inset,
    x2: size - 1 - inset,
    y2: size - 1 - inset,
    radius: size * 0.185,
    color: _accent,
  );

  // The marquee. Corner brackets rather than a closed rectangle: a rectangle on
  // a rounded badge reads as a second badge, and the whole point of the mark is
  // that the middle is empty — it is a frame around something, not a shape.
  //
  // Drawn as filled rectangles rather than strokes, because a stroked shape at
  // 16 px lands on half-pixels and comes out grey along two of its sides.
  // Measured against the badge, not the canvas: a glyph sized off the full
  // square puts its corners hard against the rounded edge.
  final thickness = math.max(1, (size * 0.068).round());
  final arm = math.max(2 * thickness, (size * 0.155).round());
  final near = (size * 0.235).round();
  final far = size - 1 - near;

  void bracket(int x, int y, int dx, int dy) {
    // The horizontal arm, then the vertical one, both growing away from the
    // corner they start at.
    img.fillRect(
      image,
      x1: math.min(x, x + dx * arm),
      y1: math.min(y, y + dy * thickness),
      x2: math.max(x, x + dx * arm),
      y2: math.max(y, y + dy * thickness),
      color: _ink,
    );
    img.fillRect(
      image,
      x1: math.min(x, x + dx * thickness),
      y1: math.min(y, y + dy * arm),
      x2: math.max(x, x + dx * thickness),
      y2: math.max(y, y + dy * arm),
      color: _ink,
    );
  }

  bracket(near, near, 1, 1);
  bracket(far, near, -1, 1);
  bracket(far, far, -1, -1);
  bracket(near, far, 1, -1);

  return image;
}

Future<void> write(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  stdout.writeln('${file.path}  ${bytes.length} bytes');
}

Future<void> main() async {
  // The sizes Windows actually picks between: the taskbar wants 32, the alt-tab
  // switcher 48, and Explorer's large-icon view 256.
  const icoSizes = <int>[16, 24, 32, 48, 64, 128, 256];
  await write(
    'windows/runner/resources/app_icon.ico',
    img.IcoEncoder().encodeImages(icoSizes.map(draw).toList()),
  );

  await write('assets/icon/snipper.png', img.encodePng(draw(512)));

  // The hicolor theme sizes a Linux .desktop entry is looked up in.
  for (final size in <int>[16, 24, 32, 48, 64, 128, 256, 512]) {
    await write('packaging/icons/snipper-$size.png', img.encodePng(draw(size)));
  }
}

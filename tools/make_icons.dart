// Draws the application icon and writes every file the platforms need.
//
// The drawing is the brand pack's `icons/snipper.svg`, restated in Dart because
// there is no SVG rasteriser on the machines this runs on. Geometry, stroke
// weight and colours are the SVG's, on the same 100x100 grid, so the two stay
// comparable by reading them side by side:
//
//   container   rounded square, radius 23, gradient #8A6FE0 -> #5B3FC4
//   glyph       white, stroke 6.5, round caps and joins
//               four corner brackets around an empty middle, and four
//               edge ticks at half opacity
//
// The empty middle is the point: the mark is a selection, and what is being
// selected is whatever is behind it.
//
// Full bleed, with no margin of its own. That is the brand's container and the
// convention every desktop now expects: the platform masks and insets the tile
// it is given, and an icon that insets itself first ends up smaller than
// everything beside it.
//
// Generated rather than drawn by hand so the sizes stay in step with each other
// and with the brand. Re-run after any change to the mark:
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

/// One unit of the brand's 100x100 grid, at this raster size.
double _u(int size) => size / 100.0;

/// A point on the brand grid.
class P {
  const P(this.x, this.y);
  final double x;
  final double y;
}

/// The quarter-arc from [a0] to [a1] degrees on a circle, as a polyline.
///
/// Enough segments that the join is invisible once the 4x supersample comes
/// back down; a rounded corner is never more than a few pixels of arc.
List<P> arc(double cx, double cy, double r, double a0, double a1) {
  const steps = 10;
  return <P>[
    for (int i = 0; i <= steps; i++)
      () {
        final t = a0 + (a1 - a0) * i / steps;
        final rad = t * math.pi / 180.0;
        return P(cx + r * math.cos(rad), cy + r * math.sin(rad));
      }(),
  ];
}

/// A rounded rectangle on the brand grid, as a closed polyline.
List<P> roundedRect(double x, double y, double w, double h, double r) => <P>[
  P(x + r, y),
  P(x + w - r, y),
  ...arc(x + w - r, y + r, r, -90, 0),
  P(x + w, y + h - r),
  ...arc(x + w - r, y + h - r, r, 0, 90),
  P(x + r, y + h),
  ...arc(x + r, y + h - r, r, 90, 180),
  P(x, y + r),
  ...arc(x + r, y + r, r, 180, 270),
  P(x + r, y),
];

/// A transparent layer the same size as the icon.
img.Image layer(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  return image;
}

/// Fills the brand's container: a rounded square carrying a vertical two-stop
/// gradient, edge to edge.
///
/// Row by row rather than through a mask, because the rounded rectangle's
/// horizontal extent at a given row is a closed-form thing and the alternative
/// is compositing two images to get the same answer.
void fillContainer(img.Image image, int size, img.Color top, img.Color bottom) {
  final u = _u(size);
  final r = 23.0 * u;
  final maxX = size - 1.0;
  final maxY = size - 1.0;

  for (int y = 0; y < size; y++) {
    final fy = y.toDouble();
    double inset = 0;
    if (fy < r) {
      final dy = r - fy;
      inset = r - math.sqrt(math.max(0, r * r - dy * dy));
    } else if (fy > maxY - r) {
      final dy = fy - (maxY - r);
      inset = r - math.sqrt(math.max(0, r * r - dy * dy));
    }
    final t = maxY == 0 ? 0.0 : fy / maxY;
    final color = img.ColorRgba8(
      (top.r + (bottom.r - top.r) * t).round(),
      (top.g + (bottom.g - top.g) * t).round(),
      (top.b + (bottom.b - top.b) * t).round(),
      255,
    );
    img.drawLine(
      image,
      x1: inset.round(),
      y1: y,
      x2: (maxX - inset).round(),
      y2: y,
      color: color,
    );
  }
}

/// Strokes [path] with round caps and joins.
///
/// Stamped as overlapping discs rather than drawn as lines: `package:image` has
/// no round cap, and a disc every third of a radius gives caps, joins and a
/// constant width for free. Cheap enough — this runs once, offline.
void stroke(
  img.Image image,
  int size,
  List<P> path,
  double width,
  img.Color c,
) {
  final u = _u(size);
  final radius = math.max(1.0, width * u / 2);
  final step = math.max(1.0, radius / 3);

  void disc(double x, double y) => img.fillCircle(
    image,
    x: x.round(),
    y: y.round(),
    radius: radius.round(),
    color: c,
  );

  for (int i = 0; i < path.length - 1; i++) {
    final a = path[i], b = path[i + 1];
    final ax = a.x * u, ay = a.y * u, bx = b.x * u, by = b.y * u;
    final dx = bx - ax, dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    final n = math.max(1, (len / step).ceil());
    for (int k = 0; k <= n; k++) {
      disc(ax + dx * k / n, ay + dy * k / n);
    }
  }
}

/// Scales a whole layer's alpha, for the parts the brand draws at reduced
/// opacity. Applied to the finished layer rather than to the stroke colour, or
/// every overlapping disc would compound into a darker seam.
void fade(img.Image image, double opacity) {
  for (final p in image) {
    if (p.a != 0) p.a = (p.a * opacity).round();
  }
}

Future<void> write(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  stdout.writeln('${file.path}  ${bytes.length} bytes');
}

/// The two stops of the brand's snipper gradient.
final img.Color _top = img.ColorRgba8(0x8A, 0x6F, 0xE0, 0xFF);
final img.Color _bottom = img.ColorRgba8(0x5B, 0x3F, 0xC4, 0xFF);
final img.Color _glyph = img.ColorRgba8(0xFF, 0xFF, 0xFF, 0xFF);

/// The brand's stroke weight, on the 100-unit grid.
const double _stroke = 6.5;

/// The icon at [size] pixels square, with smooth edges.
///
/// `package:image` draws hard-edged shapes, so the tile came out visibly
/// jagged at exactly the sizes a launcher shows. Drawing four times over and
/// averaging down is the cheapest antialiasing there is, and it costs nothing
/// here: this runs once, offline.
img.Image draw(int size) {
  const supersample = 4;
  // Below about 24px the ticks stop being ticks: at half opacity they fill the
  // gaps between the brackets and the marquee reads as one closed rectangle,
  // which is the opposite of what it means. The brand does the same thing to
  // the house mark, which drops to eight dots below the same threshold rather
  // than shrinking nine into mush. A heavier stroke goes with it, because a
  // 6.5-unit line is under two pixels at 24 and vanishes into the antialiasing.
  final small = size <= 24;
  final large = _drawAliased(size * supersample, small: small);
  return img.copyResize(
    large,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
}

img.Image _drawAliased(int size, {required bool small}) {
  final image = layer(size);
  fillContainer(image, size, _top, _bottom);
  final weight = small ? 9.0 : _stroke;

  // The four corners of the marquee. Each is a leg, a quarter turn of radius 4,
  // and the other leg — the SVG's arc command, spelled out.
  final corners = <List<P>>[
    <P>[
      const P(24, 38),
      const P(24, 28),
      ...arc(28, 28, 4, 180, 270),
      const P(38, 24),
    ],
    <P>[
      const P(62, 24),
      const P(72, 24),
      ...arc(72, 28, 4, 270, 360),
      const P(76, 38),
    ],
    <P>[
      const P(76, 62),
      const P(76, 72),
      ...arc(72, 72, 4, 0, 90),
      const P(62, 76),
    ],
    <P>[
      const P(38, 76),
      const P(28, 76),
      ...arc(28, 72, 4, 90, 180),
      const P(24, 62),
    ],
  ];
  for (final corner in corners) {
    stroke(image, size, corner, weight, _glyph);
  }

  // The midpoint ticks, held back to half opacity: they say the edges continue
  // without drawing an edge that would close the selection. Dropped entirely at
  // small sizes, where they close it.
  if (small) return image;

  final ticks = layer(size);
  const marks = <List<P>>[
    <P>[P(48, 24), P(52, 24)],
    <P>[P(48, 76), P(52, 76)],
    <P>[P(24, 48), P(24, 52)],
    <P>[P(76, 48), P(76, 52)],
  ];
  for (final mark in marks) {
    stroke(ticks, size, mark, _stroke, _glyph);
  }
  fade(ticks, 0.5);
  img.compositeImage(image, ticks);

  return image;
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

  // The hicolor theme sizes a Linux .desktop entry is looked up in. 64, 128,
  // 256 and 512 are also what Flathub and Snap ask for.
  for (final size in <int>[16, 24, 32, 48, 64, 128, 256, 512]) {
    await write('packaging/icons/snipper-$size.png', img.encodePng(draw(size)));
  }
}

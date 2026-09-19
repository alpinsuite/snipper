import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snipper/capture/linux_capture.dart';

/// The real runner, the real channel and a real X server.
///
/// CI starts Xvfb at a known size, paints the root window one known colour with
/// `xsetroot`, and runs this inside it:
///
///   xvfb-run -a -s "-screen 0 1600x900x24" \
///     flutter test integration_test/linux_capture_test.dart -d linux
///
/// That is the whole X11 path end to end — GDK reading the root window, the
/// packing in `capture_channel.cc`, the codec, [LinuxCaptureService] and the
/// decode — checked against pixels whose value is known in advance.
///
/// It cannot reach the portal path: there is no compositor and no
/// xdg-desktop-portal in a CI container. Both paths share everything after the
/// pixbuf, so what is left untested there is the D-Bus conversation alone.
const String _expectedSize = String.fromEnvironment(
  'SNIPPER_SCREEN',
  defaultValue: '1600x900',
);
const int _expectedColour = int.fromEnvironment(
  'SNIPPER_ROOT_COLOUR',
  defaultValue: 0x336699,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final size = _expectedSize.split('x').map(int.parse).toList();

  testWidgets(
    'the root window comes back, at its size and in its colour',
    (tester) async {
      await tester.runAsync(() async {
        final service = LinuxCaptureService();
        expect(service.isWayland, isFalse, reason: 'this test is the X11 path');

        final desktop = await service.enumerateDisplays();
        expect(desktop.displays, isNotEmpty);
        expect(desktop.bounds.width, size[0]);
        expect(desktop.bounds.height, size[1]);

        final result = await service.captureVirtualDesktop();
        addTearDown(result.frame.dispose);
        expect(result.frame.width, size[0]);
        expect(result.frame.height, size[1]);
        expect(
          result.bounds,
          ui.Rect.fromLTWH(0, 0, size[0] * 1.0, size[1] * 1.0),
        );

        final data = await result.frame.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final bytes = data!.buffer.asUint8List();

      // What the screenshot is made of, most common colour first. Printed into
      // every failure below: "the corner is black" and "the whole frame is
      // black" are different bugs, and a bare mismatch cannot tell them apart.
      final histogram = <int, int>{};
      for (var i = 0; i < bytes.length; i += 4 * 97) {
        final colour = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
        histogram[colour] = (histogram[colour] ?? 0) + 1;
      }
      final commonest = histogram.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final seen = commonest
          .take(4)
          .map((e) => '#${e.key.toRadixString(16).padLeft(6, '0')} x${e.value}')
          .join(', ');

        // The bottom-right corner, where this test's own window is not: without a
        // window manager it opens at the origin, 1280 by 720.
        final at = ((size[1] - 5) * size[0] + (size[0] - 5)) * 4;
        final rgb = (bytes[at] << 16) | (bytes[at + 1] << 8) | bytes[at + 2];
        expect(
          rgb.toRadixString(16).padLeft(6, '0'),
          _expectedColour.toRadixString(16).padLeft(6, '0'),
          reason: 'a channel swap or a sheared row shows up here; saw $seen',
        );
        expect(bytes[at + 3], 0xFF, reason: 'the root window has no alpha');

        // And the same colour a long way from there — near the left edge, below
        // the window — so a frame that is right in one corner and sheared
        // elsewhere does not pass.
        final far = (size[1] - 100) * size[0] * 4 + 40 * 4;
        final farRgb =
            (bytes[far] << 16) | (bytes[far + 1] << 8) | bytes[far + 2];
        expect(
          farRgb.toRadixString(16).padLeft(6, '0'),
          _expectedColour.toRadixString(16).padLeft(6, '0'),
        );
      });
    },
    skip: !Platform.isLinux,
  );
}

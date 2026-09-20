import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snipper/capture/capture_service.dart';
import 'package:snipper/capture/linux_capture.dart';

/// The Wayland path, against a portal that is not one.
///
/// Under Wayland a screenshot is a D-Bus conversation with the desktop, and CI
/// has no desktop. `tools/fake_portal.py` owns the portal's bus name on a
/// private session bus and answers as the specification says a portal does,
/// working through a fixed script of behaviours — one per call, in the order
/// the calls are made below. The two files are a pair: change one, change both.
///
///   SNIPPER_CAPTURE=portal dbus-run-session -- xvfb-run -a ... \
///     flutter test integration_test/linux_portal_test.dart -d linux
///
/// What this proves is that the runner's half of the conversation is right:
/// the token, the request path, the subscription, both orderings of reply and
/// return, a portal that picks its own path, a cancel, a refusal, a missing
/// portal, and that the file it is handed gets deleted. What it cannot prove
/// is that GNOME or KDE answer the way the specification says they do.
const int _fixtureWidth = 320;
const int _fixtureHeight = 200;
const int _fixtureColour = 0xc0392b;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> expectFixture(CaptureResult result) async {
    addTearDown(result.frame.dispose);
    expect(result.frame.width, _fixtureWidth);
    expect(result.frame.height, _fixtureHeight);
    expect(
      result.bounds,
      ui.Rect.fromLTWH(0, 0, _fixtureWidth * 1.0, _fixtureHeight * 1.0),
    );

    final data = await result.frame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final bytes = data!.buffer.asUint8List();
    final at = (100 * _fixtureWidth + 160) * 4;
    final rgb = (bytes[at] << 16) | (bytes[at + 1] << 8) | bytes[at + 2];
    expect(
      rgb.toRadixString(16).padLeft(6, '0'),
      _fixtureColour.toRadixString(16).padLeft(6, '0'),
    );
    expect(bytes[at + 3], 0xFF);
  }

  testWidgets(
    'every way the desktop can answer',
    (tester) async {
      await tester.runAsync(() async {
        final service = LinuxCaptureService();
        expect(
          service.isWayland,
          isTrue,
          reason: 'run this with SNIPPER_CAPTURE=portal',
        );
        expect(service.canDrawOwnOverlay, isFalse);

        // 1. "ok" — a whole-screen capture, which must not be interactive.
        await expectFixture(await service.captureVirtualDesktop());

        // 2. "ok" — a region, which is the desktop's own selection.
        await expectFixture(await service.captureSelectedByDesktop());

        // 3. "early" — the answer beats the method's own return.
        await expectFixture(await service.captureSelectedByDesktop());

        // 4. "legacy-handle" — the portal chose a request path of its own.
        await expectFixture(await service.captureSelectedByDesktop());

        // 5. "cancel" — a quiet end, not an error.
        await expectLater(
          service.captureSelectedByDesktop(),
          throwsA(isA<CaptureCancelled>()),
        );

        // 6. "refuse" — an error with a sentence in it.
        await expectLater(
          service.captureSelectedByDesktop(),
          throwsA(isA<CaptureException>()),
        );

        // 7. "ok-then-vanish" — the last answer before the portal leaves.
        await expectFixture(await service.captureVirtualDesktop());

        // 8. No portal on the bus at all: a machine without
        //    xdg-desktop-portal. The message has to name the fix.
        await Future<void>.delayed(const Duration(seconds: 1));
        await expectLater(
          service.captureVirtualDesktop(),
          throwsA(
            isA<CaptureException>().having(
              (error) => error.message,
              'message',
              contains('xdg-desktop-portal'),
            ),
          ),
        );
      });
    },
    skip: !Platform.isLinux,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

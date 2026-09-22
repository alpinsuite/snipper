import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/capture/capture_service.dart';
import 'package:snipper/capture/linux_capture.dart';

/// The native side is exercised for real by `integration_test/` under Xvfb.
/// These tests stand in for it, to pin down what this class does with each
/// thing the channel can say — including the things a healthy X server never
/// says, which is exactly why they cannot be left to the integration test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(LinuxCaptureService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String>[];
  Object? Function(MethodCall call)? answer;

  setUp(() {
    calls.clear();
    answer = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return answer?.call(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<String, Object?> monitor({
    String id = 'monitor-0',
    int x = 0,
    int y = 0,
    int width = 1920,
    int height = 1080,
    double scale = 1,
    bool primary = true,
  }) => <String, Object?>{
    'id': id,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'scale': scale,
    'primary': primary,
  };

  /// A packed RGBA frame, every pixel [rgba].
  Map<String, Object?> frame(int width, int height, List<int> rgba) {
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      bytes.setRange(i, i + 4, rgba);
    }
    return <String, Object?>{
      'width': width,
      'height': height,
      'bytesPerRow': width * 4,
      'bytes': bytes,
    };
  }

  group('which display server', () {
    LinuxCaptureService withEnv(Map<String, String> env) =>
        LinuxCaptureService(environment: env);

    test('X11 when there is no Wayland socket', () {
      final service = withEnv(<String, String>{'DISPLAY': ':0'});
      expect(service.isWayland, isFalse);
    });

    test('the desktop selects, on either display server', () {
      // Growing this application's own window to cover the screen is what the
      // Windows build does. On Linux it left the engine with no frame at the
      // new size and crashed on the first click into it, about half the time.
      for (final environment in <Map<String, String>>[
        <String, String>{'DISPLAY': ':0'},
        <String, String>{'DISPLAY': ':0', 'WAYLAND_DISPLAY': 'wayland-0'},
      ]) {
        expect(withEnv(environment).canDrawOwnOverlay, isFalse);
      }
    });

    test('Wayland when the compositor advertises itself', () {
      final service = withEnv(<String, String>{
        'DISPLAY': ':0',
        'WAYLAND_DISPLAY': 'wayland-0',
      });
      expect(service.isWayland, isTrue);
      expect(service.canDrawOwnOverlay, isFalse);
    });

    test('GDK_BACKEND=x11 wins over a Wayland socket', () {
      // Running under XWayland on purpose: GDK obeys the pin, so the root
      // window is readable and the overlay can be placed.
      final service = withEnv(<String, String>{
        'WAYLAND_DISPLAY': 'wayland-0',
        'GDK_BACKEND': 'x11',
      });
      expect(service.isWayland, isFalse);
    });

    test('SNIPPER_CAPTURE=portal hands everything to the desktop', () {
      // On an X server, where nothing else would: the runner honours the same
      // variable, and the two have to agree about who runs the selection.
      final service = withEnv(<String, String>{
        'DISPLAY': ':0',
        'GDK_BACKEND': 'x11',
        'SNIPPER_CAPTURE': 'portal',
      });
      expect(service.isWayland, isTrue);
      expect(service.canDrawOwnOverlay, isFalse);
    });

    test('only the first GDK_BACKEND entry counts, as in GDK', () {
      final service = withEnv(<String, String>{
        'WAYLAND_DISPLAY': 'wayland-0',
        'GDK_BACKEND': 'wayland,x11',
      });
      expect(service.isWayland, isTrue);
    });
  });

  group('monitors', () {
    test('the desktop is the union of every monitor', () async {
      answer = (_) => <Object?>[
        monitor(),
        monitor(
          id: 'monitor-1',
          x: 1920,
          width: 2560,
          height: 1440,
          primary: false,
        ),
      ];

      final desktop = await LinuxCaptureService().enumerateDisplays();

      expect(desktop.displays, hasLength(2));
      expect(desktop.bounds, const ui.Rect.fromLTWH(0, 0, 4480, 1440));
      expect(desktop.primary!.id, 'monitor-0');
    });

    test('a scale factor is carried, never applied', () async {
      // The channel has already multiplied: these are device pixels.
      answer = (_) => <Object?>[monitor(width: 3840, height: 2160, scale: 2)];

      final desktop = await LinuxCaptureService().enumerateDisplays();

      expect(desktop.displays.single.scaleFactor, 2);
      expect(desktop.bounds.size, const ui.Size(3840, 2160));
    });

    test('no monitors is a failure with a sentence in it', () async {
      answer = (_) => <Object?>[];
      await expectLater(
        LinuxCaptureService().enumerateDisplays(),
        throwsA(isA<CaptureException>()),
      );
    });
  });

  group('capture', () {
    test('the frame decodes at its own size, from the origin', () async {
      answer = (call) => call.method == 'enumerateDisplays'
          ? <Object?>[monitor(width: 6, height: 4)]
          : frame(6, 4, <int>[0x33, 0x66, 0x99, 0xFF]);

      final result = await LinuxCaptureService().captureVirtualDesktop();

      expect(calls.first, 'captureDesktop');
      expect(result.frame.width, 6);
      expect(result.frame.height, 4);
      expect(result.bounds, const ui.Rect.fromLTWH(0, 0, 6, 4));
      result.frame.dispose();
    });

    test('the channel sends RGBA, and red comes out red', () async {
      answer = (call) => call.method == 'enumerateDisplays'
          ? <Object?>[monitor(width: 2, height: 2)]
          : frame(2, 2, <int>[0xFF, 0x00, 0x00, 0xFF]);

      final result = await LinuxCaptureService().captureVirtualDesktop();
      final data = await result.frame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      // Swapped channels are the classic bug here, and they are invisible on a
      // grey desktop. Red in, red out.
      expect(data!.buffer.asUint8List().sublist(0, 4), <int>[0xFF, 0, 0, 0xFF]);
      result.frame.dispose();
    });

    test('a region chosen by the desktop uses the interactive call', () async {
      answer = (call) => call.method == 'enumerateDisplays'
          ? <Object?>[monitor()]
          : frame(5, 3, <int>[0, 0, 0, 0xFF]);

      final result = await LinuxCaptureService().captureSelectedByDesktop();

      expect(calls.first, 'captureInteractive');
      // The region is smaller than any monitor and the bounds say so: they
      // come from the pixels, not from the monitor list.
      expect(result.bounds, const ui.Rect.fromLTWH(0, 0, 5, 3));
      result.frame.dispose();
    });

    test('a screenshot survives the monitor list failing afterwards', () async {
      answer = (call) => call.method == 'enumerateDisplays'
          ? <Object?>[]
          : frame(4, 4, <int>[0, 0, 0, 0xFF]);

      final result = await LinuxCaptureService().captureVirtualDesktop();

      expect(result.desktop.displays.single.bounds, result.bounds);
      result.frame.dispose();
    });
  });

  group('what the desktop can refuse', () {
    test('a closed selection is a cancel, not an error', () async {
      answer = (_) => throw PlatformException(code: 'cancelled');
      await expectLater(
        LinuxCaptureService().captureSelectedByDesktop(),
        throwsA(isA<CaptureCancelled>()),
      );
    });

    test('a missing portal says which package to install', () async {
      answer = (_) => throw PlatformException(
        code: 'portal-unavailable',
        message:
            'This desktop has no screenshot portal. Install xdg-desktop-portal.',
      );
      await expectLater(
        LinuxCaptureService().captureVirtualDesktop(),
        throwsA(
          isA<CaptureException>().having(
            (error) => error.message,
            'message',
            contains('xdg-desktop-portal'),
          ),
        ),
      );
    });

    test('a build without the channel fails with a sentence', () async {
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        LinuxCaptureService().captureVirtualDesktop(),
        throwsA(isA<CaptureException>()),
      );
    });

    Object? refuse(MethodCall call, {required String permission}) =>
        switch (call.method) {
          'screenshotPermission' => <String, Object?>{
            'app': 'snipper',
            'permission': permission,
            'asksInFront': true,
          },
          _ => throw PlatformException(
            code: 'portal-refused',
            message: 'The desktop declined to take a screenshot.',
          ),
        };

    test(
      'a whole screen refused after a no says how to be asked again',
      () async {
        // GNOME remembers a no and never asks again, and its settings have no
        // switch for an application installed from a package.
        answer = (call) => refuse(call, permission: 'no');
        await expectLater(
          LinuxCaptureService().captureVirtualDesktop(),
          throwsA(
            isA<CaptureRefused>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('no longer asks'),
                contains('Region captures still work'),
                contains(
                  LinuxCaptureService.forgetPermissionCommand('snipper'),
                ),
              ),
            ),
          ),
        );
      },
    );

    test(
      'a whole screen refused otherwise says to answer the question',
      () async {
        answer = (call) => refuse(call, permission: 'unset');
        await expectLater(
          LinuxCaptureService().captureVirtualDesktop(),
          throwsA(
            isA<CaptureRefused>().having(
              (error) => error.message,
              'message',
              contains('answer it, then try again'),
            ),
          ),
        );
      },
    );

    test('a refused region is refused, and nothing is looked up', () async {
      // The user chose that capture in the desktop's own interface; no
      // permission was involved, so there is none to explain.
      answer = (call) => refuse(call, permission: 'no');
      await expectLater(
        LinuxCaptureService().captureSelectedByDesktop(),
        throwsA(
          isA<CaptureRefused>().having(
            (error) => error.message,
            'message',
            'The desktop declined to take a screenshot.',
          ),
        ),
      );
      expect(calls, isNot(contains('screenshotPermission')));
    });

    test('the way back names the application, and works for none', () {
      expect(
        LinuxCaptureService.forgetPermissionCommand('snipper'),
        endsWith("DeletePermission screenshot screenshot \"'snipper'\""),
      );
      // The empty name — every unsandboxed application the portal cannot
      // name — has to survive the shell as an argument of its own.
      expect(
        LinuxCaptureService.forgetPermissionCommand(''),
        endsWith("DeletePermission screenshot screenshot \"''\""),
      );
    });
  });

  group('whether the desktop will hand the whole screen over', () {
    const wayland = <String, String>{'WAYLAND_DISPLAY': 'wayland-0'};

    Future<WholeScreenConsent> consentWith(
      Map<String, Object?> recorded, {
      Map<String, String> environment = wayland,
    }) {
      answer = (_) => recorded;
      return LinuxCaptureService(environment: environment).wholeScreenConsent();
    }

    test('an X server hands it over, and nothing is asked', () async {
      final consent = await consentWith(
        <String, Object?>{'permission': 'no', 'asksInFront': true},
        environment: const <String, String>{'DISPLAY': ':0'},
      );
      expect(consent, WholeScreenConsent.given);
      expect(calls, isEmpty);
    });

    test('a recorded yes is given', () async {
      expect(
        await consentWith(<String, Object?>{
          'permission': 'yes',
          'asksInFront': true,
        }),
        WholeScreenConsent.given,
      );
    });

    test('a recorded no is refused', () async {
      expect(
        await consentWith(<String, Object?>{
          'permission': 'no',
          'asksInFront': true,
        }),
        WholeScreenConsent.refused,
      );
    });

    test('nothing recorded, where GNOME asks for the focused window', () async {
      expect(
        await consentWith(<String, Object?>{
          'permission': 'unset',
          'asksInFront': true,
        }),
        WholeScreenConsent.askInFront,
      );
    });

    test('nothing recorded, where the desktop asks by itself', () async {
      // Ubuntu 22.04's GNOME, and every other desktop: they show a dialog of
      // their own on the capture itself, and need no window in front for it.
      expect(
        await consentWith(<String, Object?>{
          'permission': 'unset',
          'asksInFront': false,
        }),
        WholeScreenConsent.given,
      );
    });

    test('a runner that cannot say is taken at its capture', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await LinuxCaptureService(environment: wayland).wholeScreenConsent(),
        WholeScreenConsent.given,
      );
    });
  });
}

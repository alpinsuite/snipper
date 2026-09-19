import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:snipper/capture/capture_service.dart';
import 'package:snipper/controller/capture_controller.dart';
import 'package:snipper/model/capture_request.dart';
import 'package:snipper/model/display.dart';
import 'package:snipper/ops/overlay_geometry.dart';
import 'package:snipper/overlay/overlay_window.dart';

/// Records what the controller asked the window to do, in order.
///
/// The whole point of this fake is the last assertion in most of these tests:
/// `leave` was called. A window left frameless, topmost and the size of the
/// desktop cannot be recovered from inside the application, so "every exit
/// restores it" is not a nicety, it is the thing that must not regress.
class FakeOverlayWindow implements OverlayWindow {
  final List<String> calls = <String>[];
  ui.Rect? enteredWith;

  @override
  Future<void> enter(ui.Rect physicalBounds) async {
    enteredWith = physicalBounds;
    calls.add('enter');
  }

  @override
  Future<void> leave() async => calls.add('leave');

  @override
  Future<void> hideFromCapture() async => calls.add('hide');

  @override
  Future<void> showAfterCapture() async => calls.add('show');
}

class FakeCaptureService implements CaptureService {
  FakeCaptureService({
    this.bounds = const ui.Rect.fromLTWH(0, 0, 40, 30),
    this.failWith,
  });

  final ui.Rect bounds;

  /// When set, [captureVirtualDesktop] throws this instead of returning.
  final Object? failWith;

  int captures = 0;

  @override
  bool get canDrawOwnOverlay => true;

  @override
  Future<VirtualDesktop> enumerateDisplays() async => _desktop();

  @override
  Future<CaptureResult> captureVirtualDesktop() async {
    captures++;
    final failure = failWith;
    if (failure != null) throw failure;
    return CaptureResult(
      frame: await _image(bounds.width.toInt(), bounds.height.toInt()),
      bounds: bounds,
      desktop: _desktop(),
    );
  }

  VirtualDesktop _desktop() => VirtualDesktop(
    bounds: bounds,
    displays: <Display>[
      Display(id: 'fake', bounds: bounds, scaleFactor: 1, isPrimary: true),
    ],
  );

  @override
  void dispose() {}
}

/// A solid image of the given size, so a crop has something real to cut.
Future<ui.Image> _image(int width, int height) {
  final pixels = Uint8List(width * height * 4)
    ..fillRange(0, width * height * 4, 0xFF);
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

  const geometry = OverlayGeometry(
    bounds: ui.Rect.fromLTWH(0, 0, 40, 30),
    logicalSize: ui.Size(40, 30),
  );

  late FakeOverlayWindow overlay;
  late FakeCaptureService service;
  late CaptureController controller;

  void build({Object? failWith, ui.Rect? bounds}) {
    overlay = FakeOverlayWindow();
    service = FakeCaptureService(
      failWith: failWith,
      bounds: bounds ?? const ui.Rect.fromLTWH(0, 0, 40, 30),
    );
    controller = CaptureController(service: service, overlay: overlay);
  }

  setUp(build);

  group('full screen', () {
    test('hands back the whole frame and never opens an overlay', () async {
      final snip = await controller.capture(
        const CaptureRequest(mode: CaptureMode.fullScreen),
      );

      expect(snip, isNotNull);
      expect(snip!.width, 40);
      expect(snip.height, 30);
      expect(overlay.calls, contains('hide'));
      expect(overlay.calls, isNot(contains('enter')));
      expect(controller.stage, CaptureStage.idle);
    });

    test('the window is given back', () async {
      await controller.capture(
        const CaptureRequest(mode: CaptureMode.fullScreen),
      );
      expect(overlay.calls, contains('leave'));
    });
  });

  group('region', () {
    test('the overlay is placed over the captured rectangle', () async {
      final pending = controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );
      await pumpEventQueue();

      expect(controller.stage, CaptureStage.selecting);
      expect(overlay.enteredWith, const ui.Rect.fromLTWH(0, 0, 40, 30));

      controller.cancel();
      await pending;
    });

    test('a dragged rectangle becomes a snip of that size', () async {
      final pending = controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );
      await pumpEventQueue();

      await controller.selectRegion(
        const ui.Rect.fromLTRB(5, 5, 25, 20),
        geometry,
      );
      final snip = await pending;

      expect(snip, isNotNull);
      expect(snip!.width, 20);
      expect(snip.height, 15);
      expect(controller.stage, CaptureStage.idle);
      expect(overlay.calls, contains('leave'));
    });

    test('the snip records where on the desktop it came from', () async {
      // A desktop whose origin is negative, which is what a monitor placed to
      // the left of the primary one produces.
      build(bounds: const ui.Rect.fromLTWH(-40, 0, 80, 30));
      const shifted = OverlayGeometry(
        bounds: ui.Rect.fromLTWH(-40, 0, 80, 30),
        logicalSize: ui.Size(80, 30),
      );

      final pending = controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );
      await pumpEventQueue();
      await controller.selectRegion(
        const ui.Rect.fromLTRB(0, 0, 10, 10),
        shifted,
      );
      final snip = await pending;

      // Frame pixels 0..10 are desktop coordinates -40..-30.
      expect(snip!.source, const ui.Rect.fromLTRB(-40, 0, -30, 10));
    });

    test('Escape cancels and gives the window back', () async {
      final pending = controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );
      await pumpEventQueue();

      controller.cancel();

      expect(await pending, isNull);
      expect(controller.stage, CaptureStage.idle);
      expect(overlay.calls, contains('leave'));
    });

    test('a drag too small to mean anything is a cancel', () async {
      final pending = controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );
      await pumpEventQueue();

      await controller.selectRegion(
        const ui.Rect.fromLTRB(10, 10, 11, 11),
        geometry,
      );

      expect(await pending, isNull);
      expect(overlay.calls, contains('leave'));
    });
  });

  group('failure', () {
    test('a refused capture is reported and the window comes back', () async {
      build(failWith: const CaptureException('the display server said no'));

      final snip = await controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );

      expect(snip, isNull);
      expect(controller.stage, CaptureStage.failed);
      expect(controller.failure, 'the display server said no');
      expect(overlay.calls, contains('leave'));
      expect(overlay.calls, contains('show'));
    });

    test('an unexpected error still gives the window back', () async {
      build(failWith: StateError('something nobody predicted'));

      // Reported rather than swallowed, so it is intercepted here instead of
      // failing the test it is the subject of.
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      await controller.capture(const CaptureRequest(mode: CaptureMode.region));

      expect(controller.stage, CaptureStage.failed);
      expect(overlay.calls, contains('leave'));
      expect(reported, hasLength(1));
    });

    test('a failure can be dismissed', () async {
      build(failWith: const CaptureException('nope'));
      await controller.capture(const CaptureRequest(mode: CaptureMode.region));

      controller.acknowledgeFailure();

      expect(controller.stage, CaptureStage.idle);
      expect(controller.failure, isNull);
    });
  });

  group('delay', () {
    test('counts down, then captures', () {
      fakeAsync((async) {
        final pending = controller.capture(
          const CaptureRequest(
            mode: CaptureMode.fullScreen,
            delay: Duration(seconds: 3),
          ),
        );

        expect(controller.stage, CaptureStage.arming);
        expect(controller.secondsRemaining, 3);
        // The window is out of the way for the whole countdown, not just for
        // the instant of the capture — the point of a delay is to arrange
        // something on screen without this application in the way.
        expect(overlay.calls, contains('hide'));

        async.elapse(const Duration(seconds: 1));
        expect(controller.secondsRemaining, 2);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(service.captures, 1);

        pending.ignore();
      });
    });

    test('cancelling during the countdown takes no picture', () {
      fakeAsync((async) {
        final pending = controller.capture(
          const CaptureRequest(
            mode: CaptureMode.fullScreen,
            delay: Duration(seconds: 5),
          ),
        );

        async.elapse(const Duration(seconds: 2));
        controller.cancel();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));

        expect(service.captures, 0);
        expect(overlay.calls, contains('leave'));
        pending.ignore();
      });
    });
  });

  test('a second request while one is in flight is ignored', () async {
    final first = controller.capture(
      const CaptureRequest(mode: CaptureMode.region),
    );
    await pumpEventQueue();

    final second = await controller.capture(
      const CaptureRequest(mode: CaptureMode.region),
    );

    expect(second, isNull);
    expect(service.captures, 1);

    controller.cancel();
    await first;
  });
}

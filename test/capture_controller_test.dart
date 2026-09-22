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

  @override
  Future<void> bringToFront() async => calls.add('front');
}

class FakeCaptureService implements CaptureService {
  FakeCaptureService({
    this.bounds = const ui.Rect.fromLTWH(0, 0, 40, 30),
    this.failWith,
    this.canDrawOwnOverlay = true,
    this.consent = WholeScreenConsent.given,
    List<Object>? answers,
    this.template,
  }) : _answers = answers ?? <Object>[];

  final ui.Rect bounds;

  /// When set, [captureVirtualDesktop] throws this instead of returning.
  final Object? failWith;

  /// What [wholeScreenConsent] says.
  final WholeScreenConsent consent;

  /// What [captureVirtualDesktop] does, one call at a time, before it falls
  /// back to [failWith] or a frame the size of [bounds]: a [ui.Size] is the
  /// size of the frame handed back, and anything else is thrown.
  final List<Object> _answers;

  /// A frame already decoded, handed back as a clone, so a capture finishes
  /// without waiting on the engine — which never comes inside `fakeAsync`.
  final ui.Image? template;

  /// Every frame handed out, in order, so a test can see which were thrown
  /// away.
  final List<ui.Image> frames = <ui.Image>[];

  int captures = 0;

  /// How many times the desktop was asked to run the selection itself.
  int desktopSelections = 0;

  @override
  final bool canDrawOwnOverlay;

  @override
  Future<CaptureResult> captureSelectedByDesktop() async {
    desktopSelections++;
    final failure = failWith;
    if (failure != null) throw failure;
    return CaptureResult(
      frame: await _image(12, 8),
      bounds: const ui.Rect.fromLTWH(0, 0, 12, 8),
      desktop: _desktop(),
    );
  }

  @override
  Future<VirtualDesktop> enumerateDisplays() async => _desktop();

  @override
  Future<WholeScreenConsent> wholeScreenConsent() async => consent;

  @override
  Future<CaptureResult> captureVirtualDesktop() async {
    captures++;
    final answer = _answers.isEmpty ? null : _answers.removeAt(0);
    if (answer != null && answer is! ui.Size) throw answer;
    final failure = failWith;
    if (answer == null && failure != null) throw failure;

    final size = answer is ui.Size ? answer : bounds.size;
    final frame =
        template?.clone() ??
        await _image(size.width.toInt(), size.height.toInt());
    frames.add(frame);
    return CaptureResult(
      frame: frame,
      bounds: bounds.topLeft & size,
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

  void build({
    Object? failWith,
    ui.Rect? bounds,
    bool canDrawOwnOverlay = true,
    WholeScreenConsent consent = WholeScreenConsent.given,
    List<Object>? answers,
    ui.Image? template,
  }) {
    overlay = FakeOverlayWindow();
    service = FakeCaptureService(
      failWith: failWith,
      bounds: bounds ?? const ui.Rect.fromLTWH(0, 0, 40, 30),
      canDrawOwnOverlay: canDrawOwnOverlay,
      consent: consent,
      answers: answers,
      template: template,
    );
    controller = CaptureController(service: service, overlay: overlay);
  }

  setUp(build);

  /// Waits until the desktop is frozen and a rectangle can be chosen.
  ///
  /// Not `pumpEventQueue`: that drains a fixed number of turns of the event
  /// loop, and the capture on the way here decodes an image, which finishes on
  /// an engine callback whenever the engine gets to it. On a busy machine that
  /// is later than the turns run out, `selectRegion` finds nothing frozen and
  /// returns, and the test then waits forever for a selection nobody made.
  /// That is how this file timed out in CI about one run in three.
  Future<void> untilSelecting() async {
    while (controller.stage != CaptureStage.selecting) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

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
      await untilSelecting();

      expect(controller.stage, CaptureStage.selecting);
      expect(overlay.enteredWith, const ui.Rect.fromLTWH(0, 0, 40, 30));

      controller.cancel();
      await pending;
    });

    test('a dragged rectangle becomes a snip of that size', () async {
      final pending = controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );
      await untilSelecting();

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
      await untilSelecting();
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
      await untilSelecting();

      controller.cancel();

      expect(await pending, isNull);
      expect(controller.stage, CaptureStage.idle);
      expect(overlay.calls, contains('leave'));
    });

    test('a drag too small to mean anything is a cancel', () async {
      final pending = controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );
      await untilSelecting();

      await controller.selectRegion(
        const ui.Rect.fromLTRB(10, 10, 11, 11),
        geometry,
      );

      expect(await pending, isNull);
      expect(overlay.calls, contains('leave'));
    });
  });

  // Wayland: the application cannot cover the desktop with its own window, so
  // the desktop runs the selection and hands back the region.
  group('region, where the desktop has to select', () {
    test('the desktop is asked, and the overlay is never entered', () async {
      build(canDrawOwnOverlay: false);

      final snip = await controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );

      expect(service.desktopSelections, 1);
      expect(service.captures, 0);
      expect(overlay.calls, isNot(contains('enter')));
      // What came back is the region itself, not a desktop to crop.
      expect(snip, isNotNull);
      expect(snip!.width, 12);
      expect(snip.height, 8);
      expect(controller.stage, CaptureStage.idle);
    });

    test('the window is still hidden first and given back after', () async {
      build(canDrawOwnOverlay: false);

      await controller.capture(const CaptureRequest(mode: CaptureMode.region));

      expect(overlay.calls.first, 'hide');
      expect(overlay.calls, contains('show'));
      expect(overlay.calls, contains('leave'));
    });

    test('closing the selection is a cancel, not a failure', () async {
      build(canDrawOwnOverlay: false, failWith: const CaptureCancelled());

      final snip = await controller.capture(
        const CaptureRequest(mode: CaptureMode.region),
      );

      expect(snip, isNull);
      expect(controller.failure, isNull);
      expect(controller.stage, CaptureStage.idle);
      expect(overlay.calls, contains('leave'));
    });

    test(
      'a full-screen capture does not involve the selection at all',
      () async {
        build(canDrawOwnOverlay: false);

        await controller.capture(
          const CaptureRequest(mode: CaptureMode.fullScreen),
        );

        expect(service.desktopSelections, 0);
        expect(service.captures, 1);
      },
    );
  });

  // GNOME, from 45: before an application may take a screenshot by itself the
  // desktop asks the user once, and GNOME Shell puts the question only on
  // behalf of the focused window. Asked from behind a hidden window, it
  // refuses without asking anyone — which is what Snipper 0.1.0 did, and why
  // it could not capture the whole screen on Ubuntu 24.04.
  group('a desktop that asks first', () {
    test('is asked with the window in front, before it steps aside', () async {
      build(
        consent: WholeScreenConsent.askInFront,
        answers: <Object>[const ui.Size(99, 99)],
      );

      final snip = await controller.capture(
        const CaptureRequest(mode: CaptureMode.fullScreen),
      );

      expect(overlay.calls.take(2), <String>['front', 'hide']);
      expect(service.captures, 2);
      // What is kept is the capture taken with the window out of the way; the
      // one taken while asking has the window in it, and is thrown away.
      expect(snip!.width, 40);
      expect(service.frames.first.debugDisposed, isTrue);
      expect(controller.stage, CaptureStage.idle);
    });

    test('a no is reported, and nothing is taken behind it', () async {
      build(
        consent: WholeScreenConsent.askInFront,
        answers: <Object>[const CaptureRefused('the user said no')],
      );

      final snip = await controller.capture(
        const CaptureRequest(mode: CaptureMode.fullScreen),
      );

      expect(snip, isNull);
      expect(controller.failure, 'the user said no');
      expect(controller.stage, CaptureStage.failed);
      expect(service.captures, 1);
      expect(overlay.calls, isNot(contains('hide')));
      expect(overlay.calls, contains('leave'));
    });

    test('is asked before a countdown, not after it', () async {
      // Decoded here, outside the fake clock, which the engine does not keep.
      final template = await _image(40, 30);
      addTearDown(template.dispose);

      fakeAsync((async) {
        build(consent: WholeScreenConsent.askInFront, template: template);
        final stages = <CaptureStage>[];
        controller.addListener(() => stages.add(controller.stage));

        final pending = controller.capture(
          const CaptureRequest(
            mode: CaptureMode.fullScreen,
            delay: Duration(seconds: 3),
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();

        expect(
          stages.indexOf(CaptureStage.asking),
          lessThan(stages.indexOf(CaptureStage.arming)),
        );
        expect(overlay.calls.first, 'front');
        expect(service.captures, 2);
        pending.ignore();
      });
    });

    test('a refusal from behind the window brings it forward once', () async {
      // The records said yes and the desktop refused anyway: the question is
      // put in front, and the capture taken again with the window aside.
      build(
        answers: <Object>[
          const CaptureRefused('nobody was asked'),
          const ui.Size(99, 99),
        ],
      );

      final snip = await controller.capture(
        const CaptureRequest(mode: CaptureMode.fullScreen),
      );

      expect(service.captures, 3);
      expect(overlay.calls.where((call) => call == 'front'), hasLength(1));
      expect(snip!.width, 40);
      expect(service.frames.first.debugDisposed, isTrue);
    });

    test('a second refusal is the answer, and is not asked again', () async {
      build(
        answers: <Object>[
          const CaptureRefused('nobody was asked'),
          const CaptureRefused('the user said no'),
        ],
      );

      await controller.capture(
        const CaptureRequest(mode: CaptureMode.fullScreen),
      );

      expect(controller.failure, 'the user said no');
      expect(service.captures, 2);
    });

    test('a desktop already told no is not asked in front', () async {
      build(
        consent: WholeScreenConsent.refused,
        answers: <Object>[const CaptureRefused('told no before')],
      );

      await controller.capture(
        const CaptureRequest(mode: CaptureMode.fullScreen),
      );

      expect(overlay.calls, isNot(contains('front')));
      expect(controller.failure, 'told no before');
      expect(service.captures, 1);
    });

    test('a region the desktop selects needs no asking', () async {
      // The user chooses the moment of those, in the desktop's own interface.
      build(canDrawOwnOverlay: false, consent: WholeScreenConsent.askInFront);

      await controller.capture(const CaptureRequest(mode: CaptureMode.region));

      expect(overlay.calls, isNot(contains('front')));
      expect(service.desktopSelections, 1);
      expect(service.captures, 0);
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
        // The desktop is asked first whether it will hand the screen over,
        // which is a round trip to the platform even when the answer is yes.
        async.flushMicrotasks();

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
    await untilSelecting();

    final second = await controller.capture(
      const CaptureRequest(mode: CaptureMode.region),
    );

    expect(second, isNull);
    expect(service.captures, 1);

    controller.cancel();
    await first;
  });
}

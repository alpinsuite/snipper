import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../capture/capture_service.dart';
import '../model/capture_request.dart';
import '../model/snip.dart';
import '../ops/overlay_geometry.dart';
import '../overlay/overlay_window.dart';

/// Where a capture has got to.
enum CaptureStage {
  /// Nothing happening. The ordinary state of the application.
  idle,

  /// A delay is counting down and the window is already out of the way.
  arming,

  /// The platform is being asked for pixels.
  capturing,

  /// The frozen desktop is on screen and a rectangle is being dragged out.
  selecting,

  /// The capture failed and the reason is being shown.
  failed,
}

/// Drives one capture from beginning to end.
///
/// The rule this class exists to keep is that the window is always given back.
/// Every path out — a finished selection, a cancel, a platform failure, an
/// exception from anywhere — passes through the same `finally`, because a
/// window left frameless, topmost and the size of the desktop cannot be
/// recovered from inside the application. That is also why the region path
/// *awaits* its selection here rather than returning and being called back
/// later: it keeps the whole capture inside one `try`.
class CaptureController extends ChangeNotifier {
  CaptureController({required this.service, required this.overlay});

  /// Public and final so a test can hand in a fake of each. The window restore
  /// is the highest-stakes line here and it has to be assertable.
  final CaptureService service;
  final OverlayWindow overlay;

  CaptureStage _stage = CaptureStage.idle;
  CaptureStage get stage => _stage;

  /// Seconds still to wait, while [stage] is [CaptureStage.arming].
  int _secondsRemaining = 0;
  int get secondsRemaining => _secondsRemaining;

  /// The frozen desktop, while [stage] is [CaptureStage.selecting].
  CaptureResult? _frozen;
  CaptureResult? get frozen => _frozen;

  /// Why the last capture failed, while [stage] is [CaptureStage.failed].
  String? _failure;
  String? get failure => _failure;

  Timer? _countdown;
  Completer<Snip?>? _selection;

  /// True while a capture is in flight, so a second request — the button, the
  /// menu and the global hotkey can all arrive at once — is ignored rather
  /// than overlapping the first.
  bool get isBusy =>
      _stage != CaptureStage.idle && _stage != CaptureStage.failed;

  /// Takes a capture. Returns the snip, or null if it was cancelled or failed.
  Future<Snip?> capture(CaptureRequest request) async {
    if (isBusy) return null;
    _failure = null;

    try {
      if (request.delay > Duration.zero) {
        if (!await _armAndWait(request.delay)) return null;
      }

      _setStage(CaptureStage.capturing);
      await overlay.hideFromCapture();
      final result = await service.captureVirtualDesktop();
      // Before anything is drawn: on Windows this clears the
      // exclude-from-capture flag, and leaving it set would make the overlay
      // invisible to every other screenshot tool — including whichever one is
      // being used to check that this works.
      await overlay.showAfterCapture();

      if (request.mode == CaptureMode.fullScreen) {
        // Handed straight over rather than copied, so it must not be registered
        // as the frozen image — that one is disposed below.
        return Snip(image: result.frame, source: result.bounds);
      }

      _frozen = result;
      _selection = Completer<Snip?>();
      _setStage(CaptureStage.selecting);
      await overlay.enter(result.bounds);

      // Completed by [selectRegion] or [cancel], both called by the overlay.
      return await _selection!.future;
    } on CaptureException catch (error) {
      _failure = error.message;
      return null;
    } on Object catch (error, stack) {
      // Anything unexpected is still a capture that did not happen, and the
      // window still has to come back. Reported rather than swallowed.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'snipper'),
      );
      _failure = '$error';
      return null;
    } finally {
      _countdown?.cancel();
      _countdown = null;
      _selection = null;
      await _restore();
      _disposeFrozen();
      _setStage(_failure == null ? CaptureStage.idle : CaptureStage.failed);
    }
  }

  /// Called by the overlay when a rectangle has been dragged out.
  Future<void> selectRegion(ui.Rect logical, OverlayGeometry geometry) async {
    final frozen = _frozen;
    final selection = _selection;
    if (frozen == null || selection == null || selection.isCompleted) return;

    // A click without a drag is somebody changing their mind, not a request for
    // a one-pixel image.
    if (!geometry.isSelectable(logical)) {
      selection.complete(null);
      return;
    }

    final frame = geometry.toFrameRect(logical);
    final cropped = await _crop(frozen.frame, frame);
    if (selection.isCompleted) {
      // Cancelled while the crop was in flight.
      cropped.dispose();
      return;
    }
    selection.complete(
      Snip(image: cropped, source: frame.shift(frozen.bounds.topLeft)),
    );
  }

  /// Escape, a right-click, or a delay abandoned before it elapsed.
  void cancel() {
    _countdown?.cancel();
    _countdown = null;
    final selection = _selection;
    if (selection != null && !selection.isCompleted) {
      selection.complete(null);
    }
  }

  /// Dismisses a failure message.
  void acknowledgeFailure() {
    if (_stage != CaptureStage.failed) return;
    _failure = null;
    _setStage(CaptureStage.idle);
  }

  /// Counts down with the window already out of the way, so whatever is being
  /// captured can be arranged first. Returns false if it was cancelled.
  Future<bool> _armAndWait(Duration delay) async {
    _secondsRemaining = delay.inSeconds;
    _setStage(CaptureStage.arming);
    await overlay.hideFromCapture();

    final elapsed = Completer<bool>();
    // Cancelling during the countdown completes the same future every other
    // cancel does, so there is exactly one way to abandon a capture.
    final abandoned = Completer<Snip?>();
    _selection = abandoned;
    unawaited(
      abandoned.future.then((_) {
        if (!elapsed.isCompleted) elapsed.complete(false);
      }),
    );

    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsRemaining--;
      notifyListeners();
      if (_secondsRemaining <= 0) {
        timer.cancel();
        _countdown = null;
        if (!elapsed.isCompleted) elapsed.complete(true);
      }
    });

    final ran = await elapsed.future;
    _selection = null;
    return ran;
  }

  Future<void> _restore() async {
    // Both, unconditionally: leaving an overlay that is not up is a no-op, and
    // getting the window back is worth two redundant platform calls.
    await overlay.leave();
    await overlay.showAfterCapture();
  }

  void _disposeFrozen() {
    _frozen?.frame.dispose();
    _frozen = null;
  }

  void _setStage(CaptureStage stage) {
    _stage = stage;
    notifyListeners();
  }

  static Future<ui.Image> _crop(ui.Image source, ui.Rect frame) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      frame,
      ui.Rect.fromLTWH(0, 0, frame.width, frame.height),
      // No resampling: this is a straight cut out of a bitmap at 1:1, and
      // anything else softens text that was crisp on screen.
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    return recorder.endRecording().toImage(
      frame.width.round(),
      frame.height.round(),
    );
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _disposeFrozen();
    super.dispose();
  }
}

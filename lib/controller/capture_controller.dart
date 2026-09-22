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

  /// The desktop is asking the user whether this application may take
  /// screenshots, and the window is in front so that it can.
  asking,

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
      // First, and before any countdown: whether the desktop will hand the
      // whole screen over once this window has stepped aside. Where it will
      // not until it has asked the user, the question is put now, while the
      // window is still in front to be asked on behalf of. A countdown is
      // time the user meant for arranging the screen, not for answering it.
      var consent = WholeScreenConsent.given;
      if (request.mode == CaptureMode.fullScreen || service.canDrawOwnOverlay) {
        _setStage(CaptureStage.capturing);
        consent = await service.wholeScreenConsent();
        if (consent == WholeScreenConsent.askInFront) await _askInFront();
      }

      if (request.delay > Duration.zero) {
        if (!await _armAndWait(request.delay)) return null;
      }

      _setStage(CaptureStage.capturing);
      await overlay.hideFromCapture();

      if (request.mode == CaptureMode.region && !service.canDrawOwnOverlay) {
        // Wayland. This application cannot put a window over the desktop
        // there, so the desktop's own interface runs the selection and what
        // comes back is already the region. Nothing is frozen and the overlay
        // is never entered; the `finally` below still gives the window back.
        final chosen = await service.captureSelectedByDesktop();
        await overlay.showAfterCapture();
        return Snip(image: chosen.frame, source: chosen.bounds);
      }

      final result = await _captureDesktop(
        mayAsk: consent == WholeScreenConsent.given,
      );
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
    } on CaptureCancelled {
      // Backing out of the desktop's selection is the same as pressing Escape
      // in ours: no snip, and nothing to report.
      return null;
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

  /// Puts the desktop's question to the user, with this window in front so
  /// that the desktop will put it.
  ///
  /// GNOME — 46 on Ubuntu 24.04, where this was found — asks once before an
  /// application may take a screenshot whose moment the user did not choose,
  /// and GNOME Shell puts the question
  /// only on behalf of the focused window. Asked from behind a hidden one it
  /// refuses before anyone has been asked — at once when some other window
  /// has the focus, and after 25 seconds when none has — and that refusal is
  /// what Snipper 0.1.0 reported, every time.
  ///
  /// There is no asking without capturing, so the answer comes back as a
  /// capture: yes is a picture of the screen with this window in it, which is
  /// thrown away, and no is a [CaptureRefused] that ends the capture and says
  /// why. After a yes the desktop remembers, and does not ask again.
  Future<void> _askInFront() async {
    _setStage(CaptureStage.asking);
    await overlay.bringToFront();
    final asked = await service.captureVirtualDesktop();
    asked.frame.dispose();
  }

  /// The whole desktop, with this window out of the way.
  ///
  /// [mayAsk] is for a desktop that was expected not to ask and refused
  /// anyway — its records said yes and no longer do, or were read wrongly.
  /// Then the question is put once, in front, and the capture tried again;
  /// the cost is up to 25 seconds of GNOME's waiting first, which is why
  /// asking is otherwise done before the window ever steps aside. Never a
  /// loop: a second refusal is the user's answer, and is reported.
  Future<CaptureResult> _captureDesktop({required bool mayAsk}) async {
    try {
      return await service.captureVirtualDesktop();
    } on CaptureRefused {
      if (!mayAsk) rethrow;
      await _askInFront();
      _setStage(CaptureStage.capturing);
      await overlay.hideFromCapture();
      return service.captureVirtualDesktop();
    }
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

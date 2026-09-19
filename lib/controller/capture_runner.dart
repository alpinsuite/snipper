import '../core/settings_controller.dart';
import '../io/clipboard_service.dart';
import '../model/annotation.dart';
import '../model/capture_request.dart';
import '../model/snip.dart';
import '../ops/encode.dart';
import '../ops/flatten.dart';
import 'capture_controller.dart';
import 'shot_controller.dart';

/// Taking a snip and doing the two things that always follow it.
///
/// This exists because a capture is asked for from three places that have
/// nothing else in common: a button inside the widget tree, a global hotkey
/// arriving from a platform channel, and a command-line switch handled before
/// there is a widget tree at all. `AppActions` is the single home for commands
/// the *interface* issues; the other two callers have no `BuildContext` to
/// reach it through, and duplicating "capture, then open, then copy if that is
/// the setting" three times is how the hotkey ends up quietly not copying.
class CaptureRunner {
  const CaptureRunner({
    required this.captures,
    required this.shot,
    required this.settings,
  });

  final CaptureController captures;
  final ShotController shot;
  final SettingsController settings;

  /// Takes a snip and opens it. Returns null if it was cancelled or failed.
  ///
  /// [copy] overrides the copy-on-capture setting, for `--clipboard`, which
  /// says what to do with the result regardless of what the interface is set
  /// to.
  Future<Snip?> run(
    CaptureMode mode, {
    bool useConfiguredDelay = true,
    bool? copy,
    bool open = true,
  }) async {
    final snip = await captures.capture(
      CaptureRequest(
        mode: mode,
        delay: useConfiguredDelay
            ? Duration(seconds: settings.delaySeconds)
            : Duration.zero,
      ),
    );
    if (snip == null) return null;

    if (open) shot.open(snip);

    // The overwhelmingly common next action after taking a screenshot is
    // pasting it somewhere, so unless it has been turned off it is already on
    // the clipboard by the time the window comes back.
    if (copy ?? settings.copyOnCapture) {
      // Flattened even though a fresh snip has no marks yet, so there is one
      // route to the clipboard rather than two that could diverge. The marks
      // come from the shot only when this snip is the one that was opened into
      // it; otherwise they belong to whatever was there before.
      final marks = open ? shot.annotations : const <Annotation>[];
      await ClipboardService.writePng(
        await Encode.encode(await Flatten.render(snip, marks), SnipFormat.png),
      );
    }
    return snip;
  }
}

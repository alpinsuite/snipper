import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../controller/capture_controller.dart';
import '../controller/capture_runner.dart';
import '../controller/shot_controller.dart';
import '../core/settings_controller.dart';
import '../io/clipboard_service.dart';
import '../io/file_dialogs.dart';
import '../io/save_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../model/capture_request.dart';
import '../ops/encode.dart';
import '../ops/flatten.dart';
import 'dialogs.dart';
import 'labels.dart';
import 'settings_dialog.dart';

/// Every user command, implemented exactly once.
///
/// The menu, the toolbar and the keyboard shortcuts all call through here, so
/// they cannot drift apart — which is the failure mode that produces a menu
/// item quietly doing something slightly different from the button next to it.
///
/// Constructed cheaply per use from a [BuildContext]; it holds nothing.
class AppActions {
  AppActions(this.context);

  final BuildContext context;

  SettingsController get _settings => context.read<SettingsController>();
  CaptureController get _captures => context.read<CaptureController>();
  ShotController get _shot => context.read<ShotController>();
  AppLocalizations get _l10n => AppLocalizations.of(context);

  bool get hasSnip => _shot.hasSnip;

  /// Takes a snip in whichever mode the capture bar is set to.
  ///
  /// This is what the New button and the global hotkey both call; the menu
  /// items name a mode explicitly instead, because a menu that does something
  /// different depending on a control elsewhere is a menu nobody trusts.
  Future<void> captureRegion() => _capture(_settings.captureMode);

  Future<void> captureMode(CaptureMode mode) => _capture(mode);

  Future<void> _capture(CaptureMode mode) async {
    // Everything is read out of the context *before* the await, and nothing
    // after it. A region capture swaps the whole window over to the overlay,
    // which unmounts the button or menu item this was called from — and a
    // `context.read` on a deactivated element throws rather than returning the
    // controller, so the snip would be taken and then quietly dropped.
    //
    // The work itself is CaptureRunner's, because the hotkey and the command
    // line ask for the same thing from outside the widget tree and there is no
    // BuildContext to reach this class through from either.
    await context.read<CaptureRunner>().run(mode);
  }

  void cancelCapture() => _captures.cancel();

  /// Writes the snip wherever the save dialog says.
  ///
  /// The format follows the extension that comes back, not a control in the
  /// interface: the dialog is where the choice is made on both platforms, and
  /// two places to choose a format is one place too many.
  Future<void> save() async {
    final shot = _shot;
    final settings = _settings;
    final l10n = _l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);

    final snip = shot.snip;
    if (snip == null) return;

    final path = await FileDialogs.saveSnip(
      suggestedName: SaveNaming.fileName(DateTime.now(), 'png'),
      labelOf: (format) => Labels.format(l10n, format),
      initialDirectory: settings.saveFolder,
    );
    if (path == null) return;

    try {
      final format = SnipFormat.forPath(path);
      final bytes = await Encode.encode(await _flattened(shot), format);
      await File(path).writeAsBytes(bytes);
      // Remembered so the next save opens where the last one went, which is
      // almost always where this one should go too.
      await settings.setSaveFolder(File(path).parent.path);
      _say(messenger, l10n.saved(_baseName(path)));
    } on FileSystemException catch (error) {
      _say(messenger, '${l10n.saveFailed}: ${error.osError?.message ?? ''}');
    }
  }

  /// Puts the snip on the clipboard.
  Future<void> copy() async {
    final shot = _shot;
    final l10n = _l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);

    final snip = shot.snip;
    if (snip == null) return;

    final ok = await ClipboardService.writePng(
      await Encode.encode(await _flattened(shot), SnipFormat.png),
    );
    _say(messenger, ok ? l10n.copied : l10n.copyFailed);
  }

  Future<void> setThemeMode(ThemeMode mode) => _settings.setThemeMode(mode);

  Future<void> setCopyOnCapture(bool value) =>
      _settings.setCopyOnCapture(value);

  void showSettings() => showSettingsDialog(context);

  void showAbout() => showAboutSnipperDialog(context);

  Future<void> quit() => windowManager.close();

  /// The snip with its marks burned in.
  ///
  /// Both routes out of the application go through here, which is what makes
  /// "a redaction that has not been flattened has not been shared" true rather
  /// than merely intended.
  ///
  /// The result may be the snip's own image when there are no marks, so it is
  /// never disposed by the caller — the shot still owns it.
  static Future<ui.Image> _flattened(ShotController shot) =>
      Flatten.render(shot.snip!, shot.annotations);

  /// Says something, if there is still a messenger to say it to.
  ///
  /// Resolved before the await that precedes every call, because by the time a
  /// file has been written the context may be gone.
  void _say(ScaffoldMessengerState? messenger, String message) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  static String _baseName(String path) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

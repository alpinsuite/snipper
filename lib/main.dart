import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'capture/capture_service.dart';
import 'capture/hotkey_service.dart';
import 'controller/capture_controller.dart';
import 'controller/capture_runner.dart';
import 'controller/shot_controller.dart';
import 'controller/tool_controller.dart';
import 'core/fire_and_forget.dart';
import 'core/settings_controller.dart';
import 'model/startup_request.dart';
import 'overlay/overlay_window.dart';

/// Entry point.
///
/// Three ways in, and they end up in the same place. The window is the ordinary
/// one. A global hotkey is the Windows way to reach it from anywhere. And a
/// command-line switch is the Linux way: a client there cannot register a
/// system-wide binding, so the desktop environment's own shortcut editor is
/// pointed at `snipper --region` instead.
Future<void> main(List<String> args) async {
  final options = StartupOptions.parse(args);
  if (options.showHelp) {
    // Only reaches a terminal on Linux — a Windows GUI binary has no console
    // attached. Documented in the README rather than worked around, because
    // attaching one makes every ordinary launch flash a black window.
    for (final error in options.errors) {
      stderr.writeln('snipper: $error');
    }
    stdout.writeln(StartupOptions.usage);
    exit(options.errors.isEmpty ? 0 : 64); // EX_USAGE
  }

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final settings = await SettingsController.load();
  final shot = ShotController();
  final tools = ToolController();
  final captures = CaptureController(
    service: CaptureService.forPlatform(),
    overlay: OverlayWindow.forPlatform(),
  );
  final hotkeys = HotkeyService.forPlatform();
  final runner = CaptureRunner(
    captures: captures,
    shot: shot,
    settings: settings,
  );

  final startup = options.request;

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1080, 720),
      // Below this the capture bar's controls start colliding, and an annotator
      // whose controls do not fit is not a smaller annotator.
      minimumSize: Size(760, 520),
      center: true,
      title: 'Snipper',
      // The title bar is drawn by the application instead, so the menus, the
      // title and the window buttons share one themed row.
      // See lib/ui/window_bar.dart.
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      // A capture asked for on the command line starts with nothing on screen.
      // The region overlay shows the window itself when it needs it, and
      // `--clipboard` never shows it at all.
      if (startup != null) return;
      await windowManager.show();
      await windowManager.focus();
    },
  );

  if (hotkeys.supported) {
    hotkeys.onPressed = () => fireAndForget(_fromHotkey(runner, settings));
    final binding = settings.hotkey;
    if (binding != null) {
      // A refusal is not fatal and not worth a dialog at startup: the setting
      // says what happened when it is opened, and everything else still works.
      fireAndForget(hotkeys.register(binding).then((_) {}));
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<ShotController>.value(value: shot),
        ChangeNotifierProvider<ToolController>.value(value: tools),
        ChangeNotifierProvider<CaptureController>.value(value: captures),
        Provider<HotkeyService>.value(value: hotkeys),
        Provider<CaptureRunner>.value(value: runner),
      ],
      child: const SnipperApp(),
    ),
  );

  if (startup != null) {
    fireAndForget(_fromCommandLine(runner, startup));
  }
}

/// A capture the hotkey asked for.
///
/// The window comes forward afterwards, because the point of the hotkey is to
/// take a shot from inside some other application and the shot then needs
/// somewhere to be. Ignored while a capture is already in flight — the
/// controller refuses the second one, and this is what stops a held key from
/// queueing them.
Future<void> _fromHotkey(
  CaptureRunner runner,
  SettingsController settings,
) async {
  if (runner.captures.isBusy) return;
  final snip = await runner.run(settings.captureMode);
  if (snip == null) return;
  await windowManager.show();
  await windowManager.focus();
}

/// A capture the command line asked for.
///
/// With `--clipboard` the process exits as soon as the image is on the
/// clipboard and the window is never shown — which is the shape a desktop
/// shortcut wants. Without it, the window appears with the snip open, ready to
/// be marked up.
Future<void> _fromCommandLine(
  CaptureRunner runner,
  StartupRequest startup,
) async {
  // One frame first. The overlay is this window, and placing it before the
  // engine has produced anything gives a fullscreen rectangle of nothing.
  await Future<void>.delayed(const Duration(milliseconds: 120));

  final snip = await runner.run(
    startup.mode,
    useConfiguredDelay: startup.useConfiguredDelay,
    copy: startup.copyAndExit ? true : null,
    open: !startup.copyAndExit,
  );

  if (startup.copyAndExit) {
    // Nothing was opened and nothing is on screen, so there is nothing to keep
    // the process around for. A cancelled capture exits the same way, so a
    // shortcut pressed by mistake does not leave a window behind.
    exit(snip == null ? 1 : 0);
  }

  if (snip == null) {
    exit(0);
  }
  await windowManager.show();
  await windowManager.focus();
}

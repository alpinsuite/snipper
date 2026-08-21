import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'capture/capture_service.dart';
import 'controller/capture_controller.dart';
import 'controller/shot_controller.dart';
import 'controller/tool_controller.dart';
import 'core/settings_controller.dart';
import 'overlay/overlay_window.dart';

/// Entry point.
///
/// [args] carries the capture switches, so a desktop-environment shortcut can
/// run `snipper --region` and get a snip without the window ever being the
/// thing anyone interacted with. That is the whole global-hotkey story on
/// Linux, where a client cannot register a system-wide binding at all.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final settings = await SettingsController.load();
  final shot = ShotController();
  final tools = ToolController();
  final captures = CaptureController(
    service: CaptureService.forPlatform(),
    overlay: OverlayWindow.forPlatform(),
  );

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
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<ShotController>.value(value: shot),
        ChangeNotifierProvider<ToolController>.value(value: tools),
        ChangeNotifierProvider<CaptureController>.value(value: captures),
      ],
      child: const SnipperApp(),
    ),
  );
}

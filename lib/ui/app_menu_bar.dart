import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../controller/shot_controller.dart';
import '../core/fire_and_forget.dart';
import '../core/settings_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../model/capture_request.dart';
import 'app_actions.dart';
import 'app_shortcuts.dart';
import 'shortcut_label.dart';

/// The application menu, drawn in-app rather than by the platform.
///
/// Flutter's `PlatformMenuBar` has no Linux backend, and an in-app menu keeps
/// one theme across the whole window on both targets.
///
/// The panels are built lazily by [SlateMenuButton], so the enabled state of
/// every command is read when the menu opens rather than captured when the bar
/// was last laid out.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // No height or background of its own: it is embedded in WindowBar, which
    // supplies both so the menus and the window buttons read as one bar.
    return SlateMenuBar(
      children: <Widget>[
        SlateMenuButton(label: l10n.menuFile, items: _fileMenu),
        SlateMenuButton(label: l10n.menuCapture, items: _captureMenu),
        SlateMenuButton(label: l10n.menuView, items: _viewMenu),
        SlateMenuButton(label: l10n.menuHelp, items: _helpMenu),
      ],
    );
  }

  static List<Widget> _fileMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = AppActions(context);
    final hasSnip = context.watch<ShotController>().hasSnip;

    return <Widget>[
      SlateMenuItem(
        label: l10n.actionSave,
        shortcut: shortcutLabel(l10n, AppShortcuts.save),
        onPressed: hasSnip ? () => fireAndForget(actions.save()) : null,
      ),
      SlateMenuItem(
        label: l10n.actionCopy,
        shortcut: shortcutLabel(l10n, AppShortcuts.copy),
        onPressed: hasSnip ? () => fireAndForget(actions.copy()) : null,
      ),
      const SlateMenuSeparator(),
      SlateMenuItem(
        label: l10n.actionQuit,
        shortcut: shortcutLabel(l10n, AppShortcuts.quit),
        onPressed: () => fireAndForget(actions.quit()),
      ),
    ];
  }

  static List<Widget> _captureMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = AppActions(context);
    final settings = context.watch<SettingsController>();

    return <Widget>[
      SlateMenuItem(
        label: l10n.actionCaptureRegion,
        shortcut: shortcutLabel(l10n, AppShortcuts.newSnip),
        onPressed: () => fireAndForget(actions.captureMode(CaptureMode.region)),
      ),
      SlateMenuItem(
        label: l10n.actionCaptureFullScreen,
        shortcut: shortcutLabel(l10n, AppShortcuts.captureFullScreen),
        onPressed: () =>
            fireAndForget(actions.captureMode(CaptureMode.fullScreen)),
      ),
      const SlateMenuSeparator(),
      SlateMenuItem(
        label: l10n.settingCopyOnCapture,
        checked: settings.copyOnCapture,
        closesMenu: false,
        onPressed: () =>
            fireAndForget(actions.setCopyOnCapture(!settings.copyOnCapture)),
      ),
      const SlateMenuSeparator(),
      SlateMenuItem(
        label: l10n.actionSettings,
        onPressed: actions.showSettings,
      ),
    ];
  }

  static List<Widget> _viewMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return <Widget>[SlateSubmenu(label: l10n.menuTheme, items: _themeMenu)];
  }

  static List<Widget> _themeMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = AppActions(context);
    final mode = context.watch<SettingsController>().themeMode;

    return <Widget>[
      for (final (ThemeMode value, String label) in <(ThemeMode, String)>[
        (ThemeMode.system, l10n.themeSystem),
        (ThemeMode.light, l10n.themeLight),
        (ThemeMode.dark, l10n.themeDark),
      ])
        SlateMenuItem(
          label: label,
          checked: mode == value,
          onPressed: () => fireAndForget(actions.setThemeMode(value)),
        ),
    ];
  }

  static List<Widget> _helpMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = AppActions(context);

    return <Widget>[
      SlateMenuItem(label: l10n.actionAbout, onPressed: actions.showAbout),
    ];
  }
}

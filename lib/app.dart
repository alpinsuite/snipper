import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import 'controller/capture_controller.dart';
import 'core/settings_controller.dart';
import 'core/theme.dart';
import 'l10n/generated/app_localizations.dart';
import 'ui/app_shell.dart';
import 'ui/overlay/region_overlay.dart';

/// Root widget: theme, localisation and the window shell.
class SnipperApp extends StatelessWidget {
  const SnipperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Installed here rather than around the MaterialApp because the
      // brightness that decides the palette is only known once themeMode and
      // the platform have been resolved, which happens inside it.
      builder: (context, child) => SlateTheme(
        data: AppTheme.slateFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _Window(),
    );
  }
}

/// Swaps the whole window between the application and the region overlay.
///
/// A swap rather than a pushed route, because the *window* is what changed: by
/// the time the overlay is on screen it has been made borderless and stretched
/// across the desktop, and there is no chrome left underneath for a route to
/// sit on. Coming back is the same swap in reverse, so there is no navigation
/// stack to get out of step with the window's actual shape.
class _Window extends StatelessWidget {
  const _Window();

  @override
  Widget build(BuildContext context) {
    final selecting =
        context.watch<CaptureController>().stage == CaptureStage.selecting;
    return selecting ? const RegionOverlay() : const AppShell();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../controller/shot_controller.dart';
import '../l10n/generated/app_localizations.dart';

/// The row along the bottom: what is on screen, and how big it really is.
///
/// The dimensions are the snip's own pixels, not the size it is being shown at.
/// A screenshot's value is that it is a record of something, and the first
/// question anyone asks of one is how big it actually is.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snip = context.watch<ShotController>().snip;

    return SlateStatusBar(
      leading: <Widget>[SlateStatusItem(label: l10n.statusReady)],
      trailing: <Widget>[
        if (snip != null)
          SlateStatusItem(label: l10n.snipSize(snip.width, snip.height)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../controller/capture_controller.dart';
import '../controller/shot_controller.dart';
import '../core/fire_and_forget.dart';
import '../core/settings_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../model/capture_request.dart';
import 'app_actions.dart';
import 'labels.dart';

/// The row that takes a snip: what to capture, how long to wait, and go.
///
/// A toolbar rather than a page of its own. The mode and the delay are the only
/// two decisions a capture needs, and putting them in front of the button means
/// nobody has to remember which mode was left selected.
class CaptureBar extends StatelessWidget {
  const CaptureBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsController>();
    final captures = context.watch<CaptureController>();
    final shot = context.watch<ShotController>();
    final actions = AppActions(context);

    return Container(
      height: theme.metrics.barHeight,
      color: theme.palette.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          SlateButton(
            label: l10n.captureNew,
            kind: SlateButtonKind.primary,
            icon: SlateIcons.camera,
            onPressed: captures.isBusy
                ? null
                : () => fireAndForget(actions.captureRegion()),
          ),
          const SizedBox(width: 10),
          SlateSegmented<CaptureMode>(
            value: settings.captureMode,
            values: CaptureMode.values,
            labelOf: (mode) => Labels.captureMode(l10n, mode),
            onChanged: (mode) => fireAndForget(settings.setCaptureMode(mode)),
          ),
          const SizedBox(width: 10),
          SlateIcon(SlateIcons.timer, size: 14, color: theme.palette.inkDim),
          const SizedBox(width: 5),
          SlateSelect<int>(
            value: settings.delaySeconds,
            values: SettingsController.delayChoices,
            labelOf: (seconds) => Labels.delay(l10n, seconds),
            onChanged: (seconds) =>
                fireAndForget(settings.setDelaySeconds(seconds)),
          ),
          const Spacer(),
          SlateIconButton(
            icon: SlateIcons.copy,
            tooltip: l10n.actionCopy,
            onPressed: shot.hasSnip
                ? () => fireAndForget(actions.copy())
                : null,
          ),
          const SizedBox(width: 4),
          SlateIconButton(
            icon: SlateIcons.save,
            tooltip: l10n.actionSave,
            onPressed: shot.hasSnip
                ? () => fireAndForget(actions.save())
                : null,
          ),
          const SizedBox(width: 8),
          if (captures.stage == CaptureStage.arming)
            Text(
              l10n.armingIn(captures.secondsRemaining),
              style: theme.textStyle,
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../controller/shot_controller.dart';
import '../controller/tool_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../model/annotation.dart';
import '../tools/annotation_draft.dart';
import 'labels.dart';

/// The row of settings for whichever tool is active.
///
/// Only the controls the active tool actually uses are shown. A colour picker
/// beside a blur tool is a control that does nothing, and a control that does
/// nothing is worse than one that is missing — it has to be tried before it can
/// be ruled out.
///
/// Changing a setting while a mark is selected restyles that mark too. That is
/// the point of marks being objects: picking a different colour is how you fix
/// an arrow you have already drawn, not something you can only decide in
/// advance.
class ToolOptionsBar extends StatelessWidget {
  const ToolOptionsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);
    final tools = context.watch<ToolController>();
    final shot = context.watch<ShotController>();
    final tool = tools.tool;

    void restyle(AnnotationStyle Function(AnnotationStyle style) change) {
      final selected = shot.selected;
      if (selected != null) shot.restyle(selected.id, change(selected.style));
    }

    return Container(
      height: theme.metrics.barHeight,
      color: theme.palette.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          Text(Labels.tool(l10n, tool), style: theme.dimTextStyle),
          const SizedBox(width: 12),

          if (tool.usesColour) ...<Widget>[
            SlateColorButton(
              icon: SlateIcons.palette,
              tooltip: l10n.optionColour,
              color: tools.colour,
              recents: tools.recents,
              recentsLabel: l10n.optionRecentColours,
              onPressed: () {},
              onPicked: (colour) {
                tools.setColour(colour);
                restyle((style) => style.copyWith(color: colour));
              },
            ),
            const SizedBox(width: 12),
          ],

          if (tool.usesWidth) ...<Widget>[
            Text(
              tool == ToolId.redact ? l10n.optionStrength : l10n.optionWidth,
              style: theme.dimTextStyle,
            ),
            const SizedBox(width: 6),
            SlateSlider(
              value: tools.strokeWidth,
              min: 1,
              max: 24,
              onChanged: (width) {
                tools.setStrokeWidth(width);
                restyle((style) => style.copyWith(strokeWidth: width));
              },
            ),
            const SizedBox(width: 12),
          ],

          if (tool.usesFill) ...<Widget>[
            SlateCheckbox(
              value: tools.filled,
              label: l10n.optionFilled,
              onChanged: (filled) {
                tools.setFilled(filled);
                restyle((style) => style.copyWith(filled: filled));
              },
            ),
            const SizedBox(width: 12),
          ],

          if (tool.usesRedaction) ...<Widget>[
            SlateSegmented<RedactionKind>(
              value: tools.redaction,
              values: RedactionKind.values,
              labelOf: (kind) => Labels.redaction(l10n, kind),
              onChanged: (kind) {
                tools.setRedaction(kind);
                restyle((style) => style.copyWith(redaction: kind));
              },
            ),
            const SizedBox(width: 12),
          ],

          if (tool.usesFontSize) ...<Widget>[
            Text(l10n.optionSize, style: theme.dimTextStyle),
            const SizedBox(width: 6),
            SlateSlider(
              value: tools.fontSize,
              min: 10,
              max: 96,
              onChanged: (size) {
                tools.setFontSize(size);
                restyle((style) => style.copyWith(fontSize: size));
              },
            ),
            const SizedBox(width: 12),
          ],

          const Spacer(),

          SlateIconButton(
            icon: SlateIcons.trash,
            tooltip: l10n.actionDelete,
            danger: true,
            onPressed: shot.selectedId == null ? null : shot.deleteSelected,
          ),
          const SizedBox(width: 8),
          SlateIconButton(
            icon: SlateIcons.undo,
            tooltip: l10n.actionUndo,
            onPressed: shot.canUndo ? shot.undo : null,
          ),
          const SizedBox(width: 2),
          SlateIconButton(
            icon: SlateIcons.redo,
            tooltip: l10n.actionRedo,
            onPressed: shot.canRedo ? shot.redo : null,
          ),
        ],
      ),
    );
  }
}

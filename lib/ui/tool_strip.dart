import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../controller/tool_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../tools/annotation_draft.dart';
import 'labels.dart';

/// The vertical strip of tools down the left edge.
///
/// One column rather than paint's two: there are ten tools here and no more
/// coming, so a single column of them is shorter than the image beside it and
/// nothing has to be scrolled or hidden behind a "more" button.
class ToolStrip extends StatelessWidget {
  const ToolStrip({super.key});

  /// Wide enough for a control plus its hover surface, and no wider — the
  /// snip is what the window is for.
  static const double width = 38;

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);
    final tools = context.watch<ToolController>();

    return Container(
      width: width,
      color: theme.palette.panel,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: <Widget>[
          for (final tool in ToolId.values) ...<Widget>[
            SlateIconButton(
              icon: Labels.toolIcon(tool),
              tooltip: Labels.tool(l10n, tool),
              selected: tools.tool == tool,
              onPressed: () => tools.setTool(tool),
            ),
            // A gap after the pointer, which is not a drawing tool, and after
            // the last drawing shape, so the strip reads as three groups
            // rather than one list of ten.
            if (tool == ToolId.select || tool == ToolId.ellipse)
              const SizedBox(height: 8)
            else
              const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

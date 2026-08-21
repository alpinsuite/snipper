import 'package:slate_ui/slate_ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../model/annotation.dart';
import '../model/capture_request.dart';
import '../ops/encode.dart';
import '../tools/annotation_draft.dart';

/// Where enum values are phrased, and nowhere else.
///
/// An enum is a program's word for something and a label is a person's, and the
/// two do not have to agree. Keeping the translation here means a `switch` over
/// a tool in a widget is a bug rather than a habit.
///
/// [toolIcon] sits here too. It is not a string, but it is the same kind of
/// decision — the mapping from a program's word to what a person sees — and
/// splitting the two halves across two files is how they drift.
abstract final class Labels {
  static String captureMode(AppLocalizations l10n, CaptureMode mode) =>
      switch (mode) {
        CaptureMode.region => l10n.modeRegion,
        CaptureMode.fullScreen => l10n.modeFullScreen,
      };

  static String delay(AppLocalizations l10n, int seconds) =>
      seconds == 0 ? l10n.delayNone : l10n.delaySeconds(seconds);

  static String format(AppLocalizations l10n, SnipFormat format) =>
      switch (format) {
        SnipFormat.png => l10n.formatPng,
        SnipFormat.jpeg => l10n.formatJpeg,
      };

  static String tool(AppLocalizations l10n, ToolId tool) => switch (tool) {
    ToolId.select => l10n.toolSelect,
    ToolId.pen => l10n.toolPen,
    ToolId.highlighter => l10n.toolHighlighter,
    ToolId.arrow => l10n.toolArrow,
    ToolId.line => l10n.toolLine,
    ToolId.rectangle => l10n.toolRectangle,
    ToolId.ellipse => l10n.toolEllipse,
    ToolId.redact => l10n.toolRedact,
    ToolId.step => l10n.toolStep,
    ToolId.text => l10n.toolText,
  };

  static SlateIconDraw toolIcon(ToolId tool) => switch (tool) {
    ToolId.select => SlateIcons.cursor,
    ToolId.pen => SlateIcons.pencil,
    ToolId.highlighter => SlateIcons.highlight,
    ToolId.arrow => SlateIcons.arrow,
    ToolId.line => SlateIcons.line,
    ToolId.rectangle => SlateIcons.rectangle,
    ToolId.ellipse => SlateIcons.ellipse,
    ToolId.redact => SlateIcons.blur,
    ToolId.step => SlateIcons.stepBadge,
    ToolId.text => SlateIcons.textCursor,
  };

  static String redaction(AppLocalizations l10n, RedactionKind kind) =>
      switch (kind) {
        RedactionKind.blur => l10n.redactBlur,
        RedactionKind.pixelate => l10n.redactPixelate,
        RedactionKind.solid => l10n.redactSolid,
      };
}

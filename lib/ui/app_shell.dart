import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../controller/capture_controller.dart';
import '../controller/shot_controller.dart';
import '../core/fire_and_forget.dart';
import '../l10n/generated/app_localizations.dart';
import '../model/capture_request.dart';
import 'app_actions.dart';
import 'app_shortcuts.dart';
import 'capture_bar.dart';
import 'editor_view.dart';
import 'status_bar.dart';
import 'tool_options_bar.dart';
import 'tool_strip.dart';
import 'window_bar.dart';

/// The window: title bar, capture bar, the snip being worked on, status bar.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShortcutScope(
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            const Column(
              children: <Widget>[
                WindowBar(),
                SlateSeparator(),
                CaptureBar(),
                SlateSeparator(),
                Expanded(child: _Stage()),
                SlateSeparator(),
                StatusBar(),
              ],
            ),
            // Above the content so the grips stay reachable where a panel
            // reaches the window edge.
            const WindowResizeEdges(),
          ],
        ),
      ),
    );
  }
}

/// Whatever the window has to show: a snip being annotated, a failure, or an
/// invitation to take one.
class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final shot = context.watch<ShotController>();
    final captures = context.watch<CaptureController>();

    final failure = captures.failure;
    if (failure != null) {
      return ColoredBox(
        color: theme.palette.background,
        child: _Failure(message: failure),
      );
    }
    if (captures.stage == CaptureStage.asking) {
      return ColoredBox(
        color: theme.palette.background,
        child: const _Asking(),
      );
    }
    if (!shot.hasSnip) {
      return ColoredBox(
        color: theme.palette.background,
        child: const _EmptyState(),
      );
    }

    // The tool strip and its options only exist once there is something to
    // draw on. An editor with no document is a row of controls that cannot do
    // anything, which is a worse first impression than an empty window.
    return const Column(
      children: <Widget>[
        ToolOptionsBar(),
        SlateSeparator(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ToolStrip(),
              SlateSeparator(vertical: true),
              Expanded(child: EditorView()),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the window shows before anything has been captured.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SlateIcon(
              SlateIcons.regionSelect,
              size: 44,
              color: theme.palette.inkDim,
            ),
            const SizedBox(height: 14),
            Text(l10n.emptyTitle, style: theme.titleStyle),
            const SizedBox(height: 6),
            Text(
              l10n.emptyBody,
              textAlign: TextAlign.center,
              style: theme.dimTextStyle,
            ),
          ],
        ),
      ),
    );
  }
}

/// The window while the desktop asks whether Snipper may capture the screen.
///
/// The window has come forward in the middle of a capture, and the desktop's
/// question is on top of it; this says why both happened, since neither was
/// the user's doing. It shows once, the first time, and after that the desktop
/// remembers the answer.
class _Asking extends StatelessWidget {
  const _Asking();

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SlateIcon(SlateIcons.lock, size: 44, color: theme.palette.inkDim),
            const SizedBox(height: 14),
            Text(l10n.askingTitle, style: theme.titleStyle),
            const SizedBox(height: 6),
            Text(
              l10n.askingBody,
              textAlign: TextAlign.center,
              style: theme.dimTextStyle,
            ),
          ],
        ),
      ),
    );
  }
}

/// A capture that did not happen, and why.
///
/// Shown in the window rather than as a dialog: everything that fails here is
/// environmental — a portal that is not installed, a display server that said
/// no — and a modal that has to be dismissed before the setting that would fix
/// it can be reached is the wrong shape for that.
class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);
    final captures = context.read<CaptureController>();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SlateIcon(
              SlateIcons.warning,
              size: 32,
              color: theme.palette.danger,
            ),
            const SizedBox(height: 12),
            Text(l10n.captureFailed, style: theme.titleStyle),
            const SizedBox(height: 6),
            // Selectable, because some of these end in a command to run: the
            // way back from a desktop that has been told no.
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: theme.dimTextStyle,
            ),
            const SizedBox(height: 14),
            SlateButton(
              label: l10n.actionClose,
              onPressed: captures.acknowledgeFailure,
            ),
          ],
        ),
      ),
    );
  }
}

/// The key bindings that are live while the window has focus.
///
/// This scope sits *below* `WidgetsApp`, which is where Flutter installs the
/// default text-editing shortcuts, so a binding here wins the key over a
/// focused text field. Nothing unmodified is bound for that reason.
class _ShortcutScope extends StatelessWidget {
  const _ShortcutScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final actions = AppActions(context);
    // Watched, not read: these bindings only exist once there is
    // something to save, so this scope has to rebuild when that changes.
    final shot = context.watch<ShotController>();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        AppShortcuts.newSnip: () => fireAndForget(actions.captureRegion()),
        AppShortcuts.captureFullScreen: () =>
            fireAndForget(actions.captureMode(CaptureMode.fullScreen)),
        if (shot.hasSnip) ...<ShortcutActivator, VoidCallback>{
          AppShortcuts.save: () => fireAndForget(actions.save()),
          AppShortcuts.copy: () => fireAndForget(actions.copy()),
          AppShortcuts.undo: shot.undo,
          AppShortcuts.redo: shot.redo,
          AppShortcuts.redoAlternate: shot.redo,
          // Delete is unmodified, so it is withdrawn while a text note is
          // being typed -- otherwise it would eat the key before the field
          // that has focus ever sees it.
          if (shot.selectedId != null)
            AppShortcuts.deleteSelection: shot.deleteSelected,
        },
        AppShortcuts.quit: () => fireAndForget(actions.quit()),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

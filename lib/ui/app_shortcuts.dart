import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Every keyboard shortcut, declared once.
///
/// The menu renders these into its right-hand column and the shell binds them;
/// declaring them in both places is how a menu ends up promising a key that
/// does nothing.
///
/// The global hotkey is deliberately not here. This list is what works while
/// the window has focus; a system-wide binding is registered with the platform,
/// is configurable, and can be refused by whatever already owns the keys — see
/// `lib/capture/hotkey_service.dart`.
abstract final class AppShortcuts {
  /// A new region snip — the thing this application is for, on the key every
  /// capture tool uses for it.
  static const SingleActivator newSnip = SingleActivator(
    LogicalKeyboardKey.keyN,
    control: true,
  );

  static const SingleActivator captureFullScreen = SingleActivator(
    LogicalKeyboardKey.keyN,
    control: true,
    shift: true,
  );

  static const SingleActivator save = SingleActivator(
    LogicalKeyboardKey.keyS,
    control: true,
  );

  static const SingleActivator copy = SingleActivator(
    LogicalKeyboardKey.keyC,
    control: true,
  );

  static const SingleActivator undo = SingleActivator(
    LogicalKeyboardKey.keyZ,
    control: true,
  );

  /// Redo is bound twice on purpose: Ctrl+Y is the Windows convention and
  /// Ctrl+Shift+Z the one every editor also accepts. Only [redo] is shown in
  /// the menu, because a menu that lists both teaches neither.
  static const SingleActivator redo = SingleActivator(
    LogicalKeyboardKey.keyY,
    control: true,
  );

  static const SingleActivator redoAlternate = SingleActivator(
    LogicalKeyboardKey.keyZ,
    control: true,
    shift: true,
  );

  static const SingleActivator deleteSelection = SingleActivator(
    LogicalKeyboardKey.delete,
  );

  static const SingleActivator quit = SingleActivator(
    LogicalKeyboardKey.keyQ,
    control: true,
  );
}

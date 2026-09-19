import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/generated/app_localizations.dart';

/// Formats a shortcut the way a menu should display it.
///
/// Material's own menu items do this internally, but the kit's rows take a
/// plain string: a widget kit has no business deciding how a platform names its
/// modifier keys, and the application does — it has the translations.
///
/// Modifiers come from [AppLocalizations]; the key itself uses its own label,
/// which is already correct for letters, digits and punctuation in any locale.
///
/// Adapted from shrink's `lib/ui/shortcut_label.dart`.
String shortcutLabel(AppLocalizations l10n, SingleActivator activator) {
  final parts = <String>[
    if (activator.control) l10n.keyCtrl,
    if (activator.shift) l10n.keyShift,
    if (activator.alt) l10n.keyAlt,
    _triggerLabel(l10n, activator.trigger),
  ];
  return parts.join('+');
}

String _triggerLabel(AppLocalizations l10n, LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.delete) return l10n.keyDelete;
  if (key == LogicalKeyboardKey.escape) return l10n.keyEscape;
  if (key == LogicalKeyboardKey.printScreen) return l10n.keyPrintScreen;
  return key.keyLabel;
}

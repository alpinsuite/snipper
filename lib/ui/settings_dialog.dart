import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../capture/hotkey_service.dart';
import '../core/settings_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../model/hotkey_binding.dart';

/// The few things worth remembering between launches.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  /// What the last attempt to take the binding said, if it said anything.
  HotkeyFailure? _failure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.slate;
    final settings = context.watch<SettingsController>();
    final hotkeys = context.read<HotkeyService>();

    return SlateDialog(
      title: l10n.settingsTitle,
      width: 420,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SlateCheckbox(
            value: settings.copyOnCapture,
            label: l10n.settingCopyOnCapture,
            onChanged: (value) => settings.setCopyOnCapture(value),
          ),
          const SizedBox(height: 14),
          const SlateSeparator(),
          const SizedBox(height: 14),

          Text(l10n.settingGlobalHotkey, style: theme.sectionStyle),
          const SizedBox(height: 6),
          if (!hotkeys.supported)
            // Absent rather than present and broken. The README says what to
            // do instead, and repeating it here is where somebody looking for
            // the setting will actually be.
            Text(l10n.settingHotkeyUnsupported, style: theme.dimTextStyle)
          else ...<Widget>[
            _HotkeyField(
              binding: settings.hotkey,
              onChanged: (binding) => _apply(hotkeys, settings, binding),
            ),
            const SizedBox(height: 6),
            Text(
              _failure == null
                  ? l10n.settingHotkeyHint
                  : switch (_failure!) {
                      HotkeyFailure.alreadyTaken => l10n.hotkeyAlreadyTaken,
                      HotkeyFailure.unsupported =>
                        l10n.settingHotkeyUnsupported,
                      HotkeyFailure.refused => l10n.hotkeyRefused,
                    },
              style: _failure == null
                  ? theme.dimTextStyle
                  : theme.dimTextStyle.copyWith(color: theme.palette.danger),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        SlateButton(
          label: l10n.actionClose,
          kind: SlateButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Future<void> _apply(
    HotkeyService hotkeys,
    SettingsController settings,
    HotkeyBinding? binding,
  ) async {
    // Registered first, saved second. A binding that Windows refused is not a
    // setting — remembering it would mean the dialog shows a shortcut that
    // does nothing every time it is opened.
    if (binding == null) {
      await hotkeys.unregister();
      await settings.setHotkey(null);
      if (mounted) setState(() => _failure = null);
      return;
    }

    final failure = await hotkeys.register(binding);
    if (failure == null) await settings.setHotkey(binding);
    if (mounted) setState(() => _failure = failure);
  }
}

/// A field that takes the next combination pressed into it.
///
/// A key capture rather than a list of combinations to choose from: the
/// binding has to be one nothing else on the machine has taken, and which ones
/// those are depends on the machine. Letting somebody try one and be told it is
/// taken is the only way to find out.
class _HotkeyField extends StatefulWidget {
  const _HotkeyField({required this.binding, required this.onChanged});

  final HotkeyBinding? binding;
  final ValueChanged<HotkeyBinding?> onChanged;

  @override
  State<_HotkeyField> createState() => _HotkeyFieldState();
}

class _HotkeyFieldState extends State<_HotkeyField> {
  final FocusNode _focus = FocusNode();
  bool _listening = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: GestureDetector(
              onTap: () {
                setState(() => _listening = true);
                _focus.requestFocus();
              },
              child: Container(
                height: theme.metrics.fieldHeight,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.palette.field,
                  border: Border.all(
                    color: _listening
                        ? theme.palette.accent
                        : theme.palette.fieldBorder,
                  ),
                  borderRadius: BorderRadius.circular(theme.metrics.radius),
                ),
                child: Text(
                  _listening
                      ? l10n.settingHotkeyListening
                      : widget.binding?.label ?? l10n.settingHotkeyOff,
                  style: widget.binding == null && !_listening
                      ? theme.dimTextStyle
                      : theme.textStyle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SlateButton(
          label: l10n.settingHotkeyClear,
          onPressed: widget.binding == null
              ? null
              : () {
                  setState(() => _listening = false);
                  widget.onChanged(null);
                },
        ),
      ],
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_listening || event is! KeyDownEvent) return KeyEventResult.ignored;

    // Escape gives up without changing anything, which is what it does
    // everywhere else and what a field that has swallowed the keyboard needs
    // to offer.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _listening = false);
      return KeyEventResult.handled;
    }

    // A modifier on its own is somebody still reaching for the rest of the
    // combination, not a binding. So is anything outside the set this
    // application is willing to take.
    final key = _keyFor(event.logicalKey);
    if (key == null) return KeyEventResult.handled;

    final keyboard = HardwareKeyboard.instance;
    final binding = HotkeyBinding(
      key: key,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      win: keyboard.isMetaPressed,
    );
    // Print Screen is the one key worth binding on its own, and the only one:
    // everything else without a modifier would be taken away from every text
    // field on the machine.
    if (!binding.isUsable && key != HotkeyKey.printScreen) {
      return KeyEventResult.handled;
    }

    setState(() => _listening = false);
    widget.onChanged(binding);
    return KeyEventResult.handled;
  }

  /// The pressed key as one this application is willing to bind, or null.
  ///
  /// `keyLabel` is already "A", "7" or "F5" for everything in [HotkeyKey]
  /// except Print Screen, which Flutter spells with a space.
  static HotkeyKey? _keyFor(LogicalKeyboardKey pressed) {
    if (pressed == LogicalKeyboardKey.printScreen) {
      return HotkeyKey.printScreen;
    }
    final label = pressed.keyLabel;
    return label.isEmpty ? null : HotkeyKey.forToken(label);
  }
}

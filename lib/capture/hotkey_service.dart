import 'dart:io';

import 'package:flutter/services.dart';

import '../model/hotkey_binding.dart';

/// Why a binding could not be taken.
enum HotkeyFailure {
  /// Something else on the machine already owns the combination. Almost always
  /// what a refusal means, and the only one worth naming to a person.
  alreadyTaken,

  /// The platform does not do this at all — Linux.
  unsupported,

  /// Anything else the platform said no to.
  refused,
}

/// A system-wide key combination that takes a snip from any application.
///
/// **Windows only, on purpose.** On Linux a client cannot register one: X11
/// needs `libkeybinder`, an extra build and runtime dependency for a feature
/// that then does not work under Wayland at all, where the compositor refuses
/// global grabs outright. Rather than ship something that works on one Linux
/// session type and silently fails on the other, `snipper --region` is a real
/// command-line switch and the README says to bind *that* to a desktop
/// shortcut. It is what Flameshot tells its users to do and it works on both.
///
/// [supported] is what the interface asks before showing the control, so the
/// setting is absent where it cannot work rather than present and broken.
abstract class HotkeyService {
  factory HotkeyService.forPlatform() =>
      Platform.isWindows ? WindowsHotkeyService() : const NoHotkeyService();

  bool get supported;

  /// Takes the binding. Returns null on success, or why not.
  ///
  /// Replaces whatever was registered before, so this is also how a binding is
  /// changed.
  Future<HotkeyFailure?> register(HotkeyBinding binding);

  Future<void> unregister();

  /// Called when the combination is pressed, from anywhere on the machine.
  set onPressed(void Function()? handler);

  void dispose();
}

/// The Windows binding, registered by `windows/runner/overlay_channel.cc`.
///
/// `RegisterHotKey` posts `WM_HOTKEY` to the *thread* queue, and that queue is
/// already being drained by the runner's own `GetMessage` loop. A Dart-side
/// `PeekMessage` pump loses that race essentially always, and a message with a
/// null window handle is then dropped by `DispatchMessage` regardless. So it
/// lives in the runner, next to the window procedure, and arrives here as a
/// method call.
class WindowsHotkeyService implements HotkeyService {
  WindowsHotkeyService() {
    _channel.setMethodCallHandler(_onCall);
  }

  /// The same channel the overlay placement uses. One channel, two directions:
  /// the overlay invokes outward, this listens inward. Only one handler can be
  /// installed per channel name, and this is it.
  static const MethodChannel _channel = MethodChannel(
    'com.alpinsuite.snipper/overlay',
  );

  void Function()? _handler;
  bool _registered = false;

  @override
  bool get supported => true;

  @override
  set onPressed(void Function()? handler) => _handler = handler;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'onHotkey') _handler?.call();
  }

  @override
  Future<HotkeyFailure?> register(HotkeyBinding binding) async {
    if (!binding.isUsable) return HotkeyFailure.refused;
    try {
      await _channel.invokeMethod<bool>('registerHotkey', <String, int>{
        'modifiers': binding.modifiers,
        'key': binding.virtualKey,
      });
      _registered = true;
      return null;
    } on PlatformException catch (error) {
      _registered = false;
      // ERROR_HOTKEY_ALREADY_REGISTERED. Worth telling apart from every other
      // refusal, because it is the only one the person can do something about.
      if (error.code == 'hotkey_refused' && error.details == 1409) {
        return HotkeyFailure.alreadyTaken;
      }
      return HotkeyFailure.refused;
    } on MissingPluginException {
      return HotkeyFailure.unsupported;
    }
  }

  @override
  Future<void> unregister() async {
    if (!_registered) return;
    _registered = false;
    try {
      await _channel.invokeMethod<bool>('unregisterHotkey');
    } on PlatformException {
      // Nothing useful to do about it, and nothing depends on it having
      // worked: the process is usually on its way out.
    } on MissingPluginException {
      // Same.
    }
  }

  @override
  void dispose() {
    _handler = null;
    _channel.setMethodCallHandler(null);
  }
}

/// Linux. Says so rather than pretending.
class NoHotkeyService implements HotkeyService {
  const NoHotkeyService();

  @override
  bool get supported => false;

  @override
  Future<HotkeyFailure?> register(HotkeyBinding binding) async =>
      HotkeyFailure.unsupported;

  @override
  Future<void> unregister() async {}

  @override
  set onPressed(void Function()? handler) {}

  @override
  void dispose() {}
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/capture_request.dart';
import '../model/hotkey_binding.dart';

/// Preferences that outlive a session.
///
/// Everything here is best-effort. If persistence fails the application still
/// runs on the defaults, because losing a remembered folder must never stop
/// anyone taking a screenshot.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs);

  static const _keyThemeMode = 'theme_mode';
  static const _keyCaptureMode = 'capture_mode';
  static const _keyHotkey = 'global_hotkey';
  static const _keyHotkeyEnabled = 'global_hotkey_enabled';
  static const _keyDelaySeconds = 'capture_delay_seconds';
  static const _keyCopyOnCapture = 'copy_on_capture';
  static const _keySaveFolder = 'save_folder';

  /// The delays the interface offers, in seconds. Nothing longer: a delay is
  /// for opening a menu, and past ten seconds people go and do something else.
  static const List<int> delayChoices = <int>[0, 3, 5, 10];

  final SharedPreferences _prefs;

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsController(prefs);
  }

  ThemeMode get themeMode => switch (_prefs.getString(_keyThemeMode)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_keyThemeMode, mode.name);
    notifyListeners();
  }

  /// The mode the capture bar is set to, remembered between launches.
  CaptureMode get captureMode =>
      _prefs.getString(_keyCaptureMode) == CaptureMode.fullScreen.name
      ? CaptureMode.fullScreen
      : CaptureMode.region;

  Future<void> setCaptureMode(CaptureMode mode) async {
    await _prefs.setString(_keyCaptureMode, mode.name);
    notifyListeners();
  }

  /// Seconds between asking for a capture and taking it.
  ///
  /// A value written by another version is clamped into the offered set rather
  /// than trusted, so a stale preferences file cannot leave the control showing
  /// something it cannot represent.
  int get delaySeconds {
    final stored = _prefs.getInt(_keyDelaySeconds) ?? 0;
    return delayChoices.contains(stored) ? stored : 0;
  }

  Future<void> setDelaySeconds(int seconds) async {
    await _prefs.setInt(_keyDelaySeconds, seconds);
    notifyListeners();
  }

  /// Whether every capture also lands on the clipboard.
  ///
  /// On by default. The overwhelmingly common next action after taking a
  /// screenshot is pasting it somewhere, and a tool that makes you press Ctrl+C
  /// first has put a step in front of its own purpose.
  bool get copyOnCapture => _prefs.getBool(_keyCopyOnCapture) ?? true;

  Future<void> setCopyOnCapture(bool value) async {
    await _prefs.setBool(_keyCopyOnCapture, value);
    notifyListeners();
  }

  /// The system-wide binding, or null when it has been turned off.
  ///
  /// Stored as its own label, so what is shown in the settings dialog and what
  /// is in the preferences file are the same string. Anything unparseable —
  /// a file from a future version, or edited by hand — falls back to the
  /// default rather than stopping the application from starting.
  HotkeyBinding? get hotkey {
    if (_prefs.getBool(_keyHotkeyEnabled) == false) return null;
    return HotkeyBinding.parse(_prefs.getString(_keyHotkey)) ??
        HotkeyBinding.defaultBinding;
  }

  Future<void> setHotkey(HotkeyBinding? binding) async {
    if (binding == null) {
      await _prefs.setBool(_keyHotkeyEnabled, false);
    } else {
      await _prefs.setBool(_keyHotkeyEnabled, true);
      await _prefs.setString(_keyHotkey, binding.label);
    }
    notifyListeners();
  }

  /// Where the save dialog opens, or null for the platform default.
  ///
  /// A folder that has been deleted or unplugged since last launch is treated
  /// as absent, rather than pointing the dialog at nothing.
  String? get saveFolder {
    final folder = _prefs.getString(_keySaveFolder);
    if (folder == null || !Directory(folder).existsSync()) return null;
    return folder;
  }

  Future<void> setSaveFolder(String? folder) async {
    if (folder == null) {
      await _prefs.remove(_keySaveFolder);
    } else {
      await _prefs.setString(_keySaveFolder, folder);
    }
    notifyListeners();
  }
}

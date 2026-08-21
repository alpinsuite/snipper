// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Snipper';

  @override
  String get appTagline => 'Screen capture and annotation';

  @override
  String get windowMinimize => 'Minimise';

  @override
  String get windowMaximize => 'Maximise';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

  @override
  String get menuFile => 'File';

  @override
  String get menuEdit => 'Edit';

  @override
  String get menuCapture => 'Capture';

  @override
  String get menuView => 'View';

  @override
  String get menuHelp => 'Help';

  @override
  String get menuTheme => 'Theme';

  @override
  String get themeSystem => 'Match System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get actionNewSnip => 'New Snip';

  @override
  String get actionCaptureRegion => 'Capture Region';

  @override
  String get actionCaptureFullScreen => 'Capture Full Screen';

  @override
  String get actionSave => 'Save As...';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionRedo => 'Redo';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionSelectAll => 'Select All';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get actionQuit => 'Quit';

  @override
  String get actionSettings => 'Settings...';

  @override
  String get actionAbout => 'About Snipper';

  @override
  String get keyCtrl => 'Ctrl';

  @override
  String get keyShift => 'Shift';

  @override
  String get keyAlt => 'Alt';

  @override
  String get keyDelete => 'Del';

  @override
  String get keyEscape => 'Esc';

  @override
  String get keyPrintScreen => 'PrtSc';

  @override
  String get emptyTitle => 'Nothing captured yet';

  @override
  String get emptyBody =>
      'Choose a mode and take a snip. The screen freezes while you drag out the region.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutBlurb =>
      'A screen capture and annotation tool for the Windows and Linux desktop.';

  @override
  String get overlayHint =>
      'Drag to select a region. Esc or right-click to cancel.';

  @override
  String get captureFailed => 'Could not take the screenshot';

  @override
  String get captureNew => 'New';

  @override
  String get captureDelay => 'Delay';

  @override
  String get delayNone => 'No delay';

  @override
  String delaySeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String get modeRegion => 'Region';

  @override
  String get modeFullScreen => 'Full Screen';

  @override
  String armingIn(int seconds) {
    return 'Capturing in $seconds...';
  }

  @override
  String snipSize(int width, int height) {
    return '$width x $height';
  }

  @override
  String get formatPng => 'PNG image';

  @override
  String get formatJpeg => 'JPEG image';

  @override
  String get saveTitle => 'Save snip';

  @override
  String saved(String name) {
    return 'Saved to $name';
  }

  @override
  String get saveFailed => 'Could not save the image';

  @override
  String get copied => 'Copied to the clipboard';

  @override
  String get copyFailed => 'The clipboard would not take the image';

  @override
  String get settingCopyOnCapture => 'Copy Every Snip to the Clipboard';

  @override
  String get toolSelect => 'Select';

  @override
  String get toolPen => 'Pen';

  @override
  String get toolHighlighter => 'Highlighter';

  @override
  String get toolArrow => 'Arrow';

  @override
  String get toolLine => 'Line';

  @override
  String get toolRectangle => 'Rectangle';

  @override
  String get toolEllipse => 'Ellipse';

  @override
  String get toolRedact => 'Redact';

  @override
  String get toolStep => 'Step Number';

  @override
  String get toolText => 'Text';

  @override
  String get optionColour => 'Colour';

  @override
  String get optionRecentColours => 'Recent';

  @override
  String get optionWidth => 'Width';

  @override
  String get optionStrength => 'Strength';

  @override
  String get optionSize => 'Size';

  @override
  String get optionFilled => 'Filled';

  @override
  String get redactBlur => 'Blur';

  @override
  String get redactPixelate => 'Pixelate';

  @override
  String get redactSolid => 'Solid';

  @override
  String get actionClearAnnotations => 'Remove All Marks';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingGlobalHotkey => 'Global hotkey';

  @override
  String get settingHotkeyHint =>
      'Click the field and press the combination you want.';

  @override
  String get settingHotkeyListening => 'Press a combination...';

  @override
  String get settingHotkeyOff => 'Off';

  @override
  String get settingHotkeyClear => 'Turn Off';

  @override
  String get settingHotkeyUnsupported =>
      'An application cannot take a system-wide key on Linux. Bind a desktop shortcut to `snipper --region` instead.';

  @override
  String get hotkeyAlreadyTaken =>
      'Something else on this machine already uses that combination.';

  @override
  String get hotkeyRefused => 'Windows would not take that combination.';

  @override
  String get statusReady => 'Ready';
}

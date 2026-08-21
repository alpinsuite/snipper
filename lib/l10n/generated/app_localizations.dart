import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application name, shown in the window title and About dialog
  ///
  /// In en, this message translates to:
  /// **'Snipper'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Screen capture and annotation'**
  String get appTagline;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimise'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximise'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowClose;

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// No description provided for @menuCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get menuCapture;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// No description provided for @menuTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get menuTheme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @actionNewSnip.
  ///
  /// In en, this message translates to:
  /// **'New Snip'**
  String get actionNewSnip;

  /// No description provided for @actionCaptureRegion.
  ///
  /// In en, this message translates to:
  /// **'Capture Region'**
  String get actionCaptureRegion;

  /// No description provided for @actionCaptureFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Capture Full Screen'**
  String get actionCaptureFullScreen;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get actionSave;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @actionRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get actionRedo;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get actionSelectAll;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get actionQuit;

  /// No description provided for @actionSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings...'**
  String get actionSettings;

  /// No description provided for @actionAbout.
  ///
  /// In en, this message translates to:
  /// **'About Snipper'**
  String get actionAbout;

  /// Modifier key name as shown in a menu's shortcut column
  ///
  /// In en, this message translates to:
  /// **'Ctrl'**
  String get keyCtrl;

  /// No description provided for @keyShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get keyShift;

  /// No description provided for @keyAlt.
  ///
  /// In en, this message translates to:
  /// **'Alt'**
  String get keyAlt;

  /// No description provided for @keyDelete.
  ///
  /// In en, this message translates to:
  /// **'Del'**
  String get keyDelete;

  /// No description provided for @keyEscape.
  ///
  /// In en, this message translates to:
  /// **'Esc'**
  String get keyEscape;

  /// No description provided for @keyPrintScreen.
  ///
  /// In en, this message translates to:
  /// **'PrtSc'**
  String get keyPrintScreen;

  /// No description provided for @emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing captured yet'**
  String get emptyTitle;

  /// No description provided for @emptyBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a mode and take a snip. The screen freezes while you drag out the region.'**
  String get emptyBody;

  /// Version line in the About dialog
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutBlurb.
  ///
  /// In en, this message translates to:
  /// **'A screen capture and annotation tool for the Windows and Linux desktop.'**
  String get aboutBlurb;

  /// No description provided for @overlayHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to select a region. Esc or right-click to cancel.'**
  String get overlayHint;

  /// No description provided for @captureFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not take the screenshot'**
  String get captureFailed;

  /// No description provided for @captureNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get captureNew;

  /// No description provided for @captureDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get captureDelay;

  /// No description provided for @delayNone.
  ///
  /// In en, this message translates to:
  /// **'No delay'**
  String get delayNone;

  /// A capture delay, as shown in the delay chooser
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String delaySeconds(int seconds);

  /// No description provided for @modeRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get modeRegion;

  /// No description provided for @modeFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full Screen'**
  String get modeFullScreen;

  /// Countdown shown while a delayed capture waits
  ///
  /// In en, this message translates to:
  /// **'Capturing in {seconds}...'**
  String armingIn(int seconds);

  /// The dimensions of the captured image, in the status bar
  ///
  /// In en, this message translates to:
  /// **'{width} x {height}'**
  String snipSize(int width, int height);

  /// No description provided for @formatPng.
  ///
  /// In en, this message translates to:
  /// **'PNG image'**
  String get formatPng;

  /// No description provided for @formatJpeg.
  ///
  /// In en, this message translates to:
  /// **'JPEG image'**
  String get formatJpeg;

  /// No description provided for @saveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save snip'**
  String get saveTitle;

  /// Confirmation after writing a snip to disk
  ///
  /// In en, this message translates to:
  /// **'Saved to {name}'**
  String saved(String name);

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the image'**
  String get saveFailed;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to the clipboard'**
  String get copied;

  /// No description provided for @copyFailed.
  ///
  /// In en, this message translates to:
  /// **'The clipboard would not take the image'**
  String get copyFailed;

  /// No description provided for @settingCopyOnCapture.
  ///
  /// In en, this message translates to:
  /// **'Copy Every Snip to the Clipboard'**
  String get settingCopyOnCapture;

  /// No description provided for @toolSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get toolSelect;

  /// No description provided for @toolPen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get toolPen;

  /// No description provided for @toolHighlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get toolHighlighter;

  /// No description provided for @toolArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get toolArrow;

  /// No description provided for @toolLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get toolLine;

  /// No description provided for @toolRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get toolRectangle;

  /// No description provided for @toolEllipse.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get toolEllipse;

  /// No description provided for @toolRedact.
  ///
  /// In en, this message translates to:
  /// **'Redact'**
  String get toolRedact;

  /// No description provided for @toolStep.
  ///
  /// In en, this message translates to:
  /// **'Step Number'**
  String get toolStep;

  /// No description provided for @toolText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get toolText;

  /// No description provided for @optionColour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get optionColour;

  /// No description provided for @optionRecentColours.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get optionRecentColours;

  /// No description provided for @optionWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get optionWidth;

  /// No description provided for @optionStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get optionStrength;

  /// No description provided for @optionSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get optionSize;

  /// No description provided for @optionFilled.
  ///
  /// In en, this message translates to:
  /// **'Filled'**
  String get optionFilled;

  /// No description provided for @redactBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get redactBlur;

  /// No description provided for @redactPixelate.
  ///
  /// In en, this message translates to:
  /// **'Pixelate'**
  String get redactPixelate;

  /// No description provided for @redactSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get redactSolid;

  /// No description provided for @actionClearAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Remove All Marks'**
  String get actionClearAnnotations;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingGlobalHotkey.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey'**
  String get settingGlobalHotkey;

  /// No description provided for @settingHotkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Click the field and press the combination you want.'**
  String get settingHotkeyHint;

  /// No description provided for @settingHotkeyListening.
  ///
  /// In en, this message translates to:
  /// **'Press a combination...'**
  String get settingHotkeyListening;

  /// No description provided for @settingHotkeyOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingHotkeyOff;

  /// No description provided for @settingHotkeyClear.
  ///
  /// In en, this message translates to:
  /// **'Turn Off'**
  String get settingHotkeyClear;

  /// No description provided for @settingHotkeyUnsupported.
  ///
  /// In en, this message translates to:
  /// **'An application cannot take a system-wide key on Linux. Bind a desktop shortcut to `snipper --region` instead.'**
  String get settingHotkeyUnsupported;

  /// No description provided for @hotkeyAlreadyTaken.
  ///
  /// In en, this message translates to:
  /// **'Something else on this machine already uses that combination.'**
  String get hotkeyAlreadyTaken;

  /// No description provided for @hotkeyRefused.
  ///
  /// In en, this message translates to:
  /// **'Windows would not take that combination.'**
  String get hotkeyRefused;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusReady;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

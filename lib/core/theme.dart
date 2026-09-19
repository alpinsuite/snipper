import 'package:flutter/material.dart';
import 'package:slate_ui/slate_ui.dart';

/// The application's chrome, which is the Slate kit and nothing else.
///
/// The one colour the kit has no opinion about is the ground behind a
/// screenshot, and the scrim the region overlay lays over the frozen desktop.
/// Both are derived from the palette rather than invented.
abstract final class AppTheme {
  static const SlateThemeData lightSlate = SlateThemeData.light();
  static const SlateThemeData darkSlate = SlateThemeData.dark();

  static SlateThemeData slateFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSlate : lightSlate;

  static ThemeData light() => lightSlate.toMaterialTheme();

  static ThemeData dark() => darkSlate.toMaterialTheme();

  /// The two squares of the transparency checkerboard behind a shot.
  ///
  /// Drawn rather than themed because it has to read as "nothing is here" in
  /// both palettes, which a single colour cannot do.
  static (Color, Color) checkerboard(SlatePalette palette) => palette.isDark
      ? (const Color(0xFF34383E), const Color(0xFF2A2E33))
      : (const Color(0xFFFFFFFF), const Color(0xFFE4E7EB));
}

/// The native save dialog.
///
/// Thin on purpose: `file_selector` already routes to GTK on Linux and to the
/// common item dialog on Windows. What this adds is the filter, built from
/// [SnipFormat] so the dialog offers exactly the formats that can be written —
/// a dialog offering a format the application then refuses is a dialog that
/// lied.
library;

import 'package:file_selector/file_selector.dart';

import '../ops/encode.dart';

abstract final class FileDialogs {
  /// Asks where to write a snip. Null when cancelled.
  ///
  /// [labelOf] phrases each format, because the kit's rule applies here too:
  /// nothing below the interface layer owns a user-visible string.
  static Future<String?> saveSnip({
    required String suggestedName,
    required String Function(SnipFormat format) labelOf,
    String? initialDirectory,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      initialDirectory: initialDirectory,
      acceptedTypeGroups: <XTypeGroup>[
        for (final format in SnipFormat.values)
          XTypeGroup(label: labelOf(format), extensions: format.extensions),
      ],
    );
    return location?.path;
  }

  /// Picks a folder, for the setting that says where snips go. Null when
  /// cancelled.
  static Future<String?> chooseFolder({String? confirmButtonText}) =>
      getDirectoryPath(confirmButtonText: confirmButtonText);
}

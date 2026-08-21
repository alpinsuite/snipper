import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

/// Putting an image on the system clipboard.
///
/// PNG is the interchange format: it is the one encoding every desktop toolkit
/// agrees on, and it keeps the alpha channel that BMP — the other common choice
/// — would drop.
///
/// Two paths, because one package does not cover both platforms. `pasteboard`
/// writes images on Windows. Its Linux plugin answers "not implemented" to
/// `writeImage`, so the application registers its own GTK channel in
/// `linux/runner/clipboard_channel.cc` rather than pulling in
/// `super_clipboard`, which needs a Rust toolchain in CI.
abstract final class ClipboardService {
  static const MethodChannel _channel = MethodChannel(
    'com.alpinsuite.snipper/clipboard',
  );

  /// Puts [png] on the clipboard.
  ///
  /// Returns false when the platform refused it, so the caller can say so
  /// rather than claiming a copy that did not happen — which is the worst
  /// possible failure here, because the next thing anyone does is paste.
  static Future<bool> writePng(Uint8List png) async {
    if (png.isEmpty) return false;
    try {
      if (Platform.isLinux) {
        await _channel.invokeMethod<void>('writeImage', png);
        return true;
      }
      await Pasteboard.writeImage(png);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

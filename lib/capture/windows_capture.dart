import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../model/display.dart';
import '../model/raster_frame.dart';
import 'capture_service.dart';

/// Screen capture on Windows, through GDI.
///
/// Entirely `dart:ffi` — there is no C++ in the capture path, which is worth
/// something given that the overlay *does* need a runner channel. The sequence
/// is the one every Windows screenshot tool uses: a device context for the
/// whole screen, a DIB section to blit into, and a pointer to its pixels.
///
/// Two things about the numbers here that are easy to get wrong:
///
/// - **They are physical pixels.** Flutter's runner declares `PerMonitorV2` in
///   `windows/runner/runner.exe.manifest`, so this process is not virtualised
///   and `GetSystemMetrics` reports real device pixels. A screenshot wants
///   exactly that. It also means these values must never be divided by a scale
///   factor on their way anywhere.
/// - **The origin is regularly negative.** `SM_XVIRTUALSCREEN` is -1920 for a
///   monitor placed left of the primary one.
class WindowsCaptureService implements CaptureService {
  @override
  bool get canDrawOwnOverlay => true;

  @override
  Future<VirtualDesktop> enumerateDisplays() async {
    final displays = <Display>[];

    // The callback runs synchronously inside EnumDisplayMonitors, so writing
    // to `displays` from it is safe and there is nothing to await.
    final callback = NativeCallable<MONITORENUMPROC>.isolateLocal((
      Pointer monitor,
      Pointer _,
      Pointer<RECT> _,
      int _,
    ) {
      final info = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
      try {
        if (GetMonitorInfo(HMONITOR(monitor), info)) {
          final rect = info.ref.rcMonitor;
          displays.add(
            Display(
              id: 'monitor-${monitor.address}',
              bounds: ui.Rect.fromLTRB(
                rect.left.toDouble(),
                rect.top.toDouble(),
                rect.right.toDouble(),
                rect.bottom.toDouble(),
              ),
              scaleFactor: _scaleFactorOf(HMONITOR(monitor)),
              isPrimary: info.ref.dwFlags & MONITORINFOF_PRIMARY != 0,
            ),
          );
        }
      } finally {
        free(info);
      }
      return TRUE;
    }, exceptionalReturn: 0);

    try {
      EnumDisplayMonitors(null, null, callback.nativeFunction, LPARAM(0));
    } finally {
      callback.close();
    }

    return VirtualDesktop(bounds: virtualScreenBounds(), displays: displays);
  }

  @override
  Future<CaptureResult> captureVirtualDesktop() async {
    final bounds = virtualScreenBounds();
    final desktop = await enumerateDisplays();
    final frame = _grab(bounds);
    return CaptureResult(
      frame: await decodeFrame(frame),
      bounds: bounds,
      desktop: desktop,
    );
  }

  /// The rectangle enclosing every monitor, in physical pixels.
  static ui.Rect virtualScreenBounds() {
    final left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    final top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    final width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (width <= 0 || height <= 0) {
      throw const CaptureException('Windows reported a screen with no pixels.');
    }
    return ui.Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }

  /// 1.0 at 96 DPI. Only ever shown to the person using the application; no
  /// coordinate is scaled by it.
  static double _scaleFactorOf(HMONITOR monitor) {
    final dpiX = calloc<Uint32>();
    final dpiY = calloc<Uint32>();
    try {
      GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, dpiX, dpiY);
      final dpi = dpiX.value;
      return dpi == 0 ? 1 : dpi / 96;
    } on Object {
      // Shcore is present on everything this targets, but a scale factor is
      // decoration and refusing to enumerate a monitor over it would not be.
      return 1;
    } finally {
      free(dpiX);
      free(dpiY);
    }
  }

  /// Blits [bounds] out of the screen into a buffer this process owns.
  RasterFrame _grab(ui.Rect bounds) {
    final width = bounds.width.toInt();
    final height = bounds.height.toInt();

    final screenDc = GetDC(null);
    if (screenDc.address == 0) {
      throw const CaptureException('Windows would not open a screen context.');
    }
    HDC? memoryDc;
    HBITMAP? bitmap;
    HGDIOBJ? previous;
    final info = calloc<BITMAPINFO>();
    final bits = calloc<Pointer>();

    try {
      memoryDc = CreateCompatibleDC(screenDc);
      if (memoryDc.address == 0) {
        throw const CaptureException('Windows would not open a draw context.');
      }

      // A negative height asks for a top-down bitmap. The default is bottom-up,
      // which every image format then has to undo.
      info.ref.bmiHeader
        ..biSize = sizeOf<BITMAPINFOHEADER>()
        ..biWidth = width
        ..biHeight = -height
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = BI_RGB;

      final created = CreateDIBSection(
        memoryDc,
        info,
        DIB_RGB_COLORS,
        bits,
        null,
        0,
      );
      bitmap = created.value;
      if (bitmap.address == 0 || bits.value == nullptr) {
        throw CaptureException(
          'Windows would not allocate a ${width}x$height bitmap.',
          cause: created.error,
        );
      }

      previous = SelectObject(memoryDc, HGDIOBJ(bitmap));

      // CAPTUREBLT is what includes layered windows — without it, anything
      // drawn with transparency comes out as a hole.
      final blit = BitBlt(
        memoryDc,
        0,
        0,
        width,
        height,
        screenDc,
        bounds.left.toInt(),
        bounds.top.toInt(),
        ROP_CODE(SRCCOPY | CAPTUREBLT),
      );
      if (!blit.value) {
        throw CaptureException(
          'Windows refused to copy the screen.',
          cause: blit.error,
        );
      }

      // Copied out of the DIB rather than wrapped, because the bitmap is
      // deleted before this returns and an `asTypedList` over freed GDI memory
      // is a crash that happens somewhere else entirely.
      final source = bits.value.cast<Uint8>().asTypedList(width * height * 4);
      return RasterFrame(
        width: width,
        height: height,
        bytesPerRow: width * 4,
        bytes: Uint8List.fromList(source),
      );
    } finally {
      if (previous != null && memoryDc != null && previous.address != 0) {
        SelectObject(memoryDc, previous);
      }
      if (bitmap != null && bitmap.address != 0) DeleteObject(HGDIOBJ(bitmap));
      if (memoryDc != null && memoryDc.address != 0) DeleteDC(memoryDc);
      ReleaseDC(null, screenDc);
      free(info);
      free(bits);
    }
  }

  @override
  void dispose() {}
}

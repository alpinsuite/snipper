import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../model/display.dart';
import '../model/raster_frame.dart';
import 'capture_service.dart';

/// Screen capture on Linux, through the runner's `capture` channel.
///
/// The native side — `linux/runner/capture_channel.cc` — has two ways to a
/// screenshot and chooses between them by display server. Under X11 it reads
/// the root window. Under Wayland no client may do that, so it asks
/// xdg-desktop-portal, which asks the compositor. This class does not care
/// which happened: both come back as one packed RGBA buffer.
///
/// What it *does* have to know is which world it is in before it captures
/// anything, because [canDrawOwnOverlay] is a synchronous question and the
/// answer decides how a region gets selected. That is read from the
/// environment, the same way GDK itself decides.
class LinuxCaptureService implements CaptureService {
  LinuxCaptureService({
    this.channel = const MethodChannel(channelName),
    Map<String, String>? environment,
  }) : _environment = environment ?? Platform.environment;

  static const String channelName = 'com.alpinsuite.snipper/capture';

  /// Replaceable so a test can answer in the desktop's place.
  final MethodChannel channel;
  final Map<String, String> _environment;

  /// Whether GDK will have picked Wayland for this process.
  ///
  /// GTK 3 tries Wayland first whenever `WAYLAND_DISPLAY` is set, unless
  /// `GDK_BACKEND` pins it elsewhere — which is how somebody runs this under
  /// XWayland on purpose, and then the X11 path is the right one.
  bool get isWayland {
    // The same switch the runner honours: `SNIPPER_CAPTURE=portal` sends every
    // capture through the desktop, X server or not. For these purposes that
    // *is* Wayland — the desktop runs the selection.
    if (_environment['SNIPPER_CAPTURE'] == 'portal') return true;

    final pinned = _environment['GDK_BACKEND'] ?? '';
    if (pinned.isNotEmpty) {
      return pinned.split(',').first.trim() == 'wayland';
    }
    return (_environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
  }

  /// False under Wayland: a client there cannot place a window, let alone
  /// stretch one across every monitor, so the desktop runs the selection.
  @override
  bool get canDrawOwnOverlay => !isWayland;

  @override
  Future<VirtualDesktop> enumerateDisplays() async {
    final List<Object?> raw = await _invoke<List<Object?>>('enumerateDisplays');
    final displays = <Display>[
      for (final entry in raw.cast<Map<Object?, Object?>>())
        Display(
          id: entry['id']! as String,
          bounds: ui.Rect.fromLTWH(
            (entry['x']! as num).toDouble(),
            (entry['y']! as num).toDouble(),
            (entry['width']! as num).toDouble(),
            (entry['height']! as num).toDouble(),
          ),
          scaleFactor: (entry['scale']! as num).toDouble(),
          isPrimary: entry['primary']! as bool,
        ),
    ];
    if (displays.isEmpty) {
      throw const CaptureException('The desktop reported no monitors.');
    }

    var bounds = displays.first.bounds;
    for (final display in displays.skip(1)) {
      bounds = bounds.expandToInclude(display.bounds);
    }
    return VirtualDesktop(bounds: bounds, displays: displays);
  }

  @override
  Future<CaptureResult> captureVirtualDesktop() => _capture('captureDesktop');

  @override
  Future<CaptureResult> captureSelectedByDesktop() =>
      _capture('captureInteractive');

  Future<CaptureResult> _capture(String method) async {
    final raw = await _invoke<Map<Object?, Object?>>(method);
    final frame = RasterFrame(
      width: raw['width']! as int,
      height: raw['height']! as int,
      bytesPerRow: raw['bytesPerRow']! as int,
      bytes: raw['bytes']! as Uint8List,
      order: PixelOrder.rgba,
    );

    // The frame's own size is the truth about what was captured. Under X11 it
    // is the root window, which starts at the origin. From the portal it is
    // whatever the compositor chose to hand over — possibly a region, possibly
    // at a fractional scale the monitor list knows nothing about — so the
    // bounds are taken from the pixels and never reconciled with the monitors.
    final bounds = ui.Rect.fromLTWH(
      0,
      0,
      frame.width.toDouble(),
      frame.height.toDouble(),
    );
    return CaptureResult(
      frame: await decodeFrame(frame),
      bounds: bounds,
      desktop: await _desktopOr(bounds),
    );
  }

  /// The monitor list, or a single monitor the size of the frame when the
  /// desktop will not say. A screenshot that arrived is not thrown away because
  /// a courtesy lookup failed afterwards.
  Future<VirtualDesktop> _desktopOr(ui.Rect bounds) async {
    try {
      return await enumerateDisplays();
    } on CaptureException {
      return VirtualDesktop(
        bounds: bounds,
        displays: <Display>[
          Display(
            id: 'desktop',
            bounds: bounds,
            scaleFactor: 1,
            isPrimary: true,
          ),
        ],
      );
    }
  }

  Future<T> _invoke<T>(String method) async {
    try {
      final result = await channel.invokeMethod<T>(method);
      if (result == null) {
        throw CaptureException('The desktop answered $method with nothing.');
      }
      return result;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') throw const CaptureCancelled();
      throw CaptureException(
        error.message ?? 'The desktop would not take a screenshot.',
        cause: error.code,
      );
    } on MissingPluginException catch (error) {
      throw CaptureException(
        'This build has no screen capture channel.',
        cause: error,
      );
    }
  }

  @override
  void dispose() {}
}

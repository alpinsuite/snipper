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
  /// The runner needs this distinction, because it reads the X root window
  /// directly where it can. The selection does not: [canDrawOwnOverlay] is
  /// false either way.
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

  /// Always false on Linux: the desktop runs the selection.
  ///
  /// Under Wayland there is no choice — a client cannot place a window, let
  /// alone stretch one across every monitor.
  ///
  /// Under X11 there is, and it was taken the other way first: the application
  /// grew its own window to cover the screen and drew the selection itself, as
  /// it does on Windows. That does not survive the Flutter engine. Resizing
  /// the window out from under it leaves the embedder waiting for a frame at
  /// the new size that never comes, and the overlay is a screen-sized
  /// rectangle of nothing that segfaults on the first click into it. It
  /// happened on about half of the runs in `tools/smoke_linux.sh`, from the
  /// hotkey and from `--region` alike, and neither showing the window first
  /// nor waiting on a real frame nor `gtk_window_fullscreen` made it reliable.
  ///
  /// So both display servers take the same road: `xdg-desktop-portal` is asked
  /// for an interactive screenshot, and whatever the user chose comes back
  /// already cropped. It costs a dependency that GNOME and KDE both ship, and
  /// a desktop without one says which package is missing.
  @override
  bool get canDrawOwnOverlay => false;

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
    final Map<Object?, Object?> raw;
    try {
      raw = await _invoke<Map<Object?, Object?>>(method);
    } on CaptureRefused {
      // Only a capture whose moment the user did not choose needs the
      // desktop's permission, so only then is there more to say than no.
      if (method != 'captureDesktop') rethrow;
      throw CaptureRefused(await _whyRefused(), cause: 'portal-refused');
    }
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

  /// An X server hands its root window to anyone who asks. Under Wayland the
  /// portal decides, and the runner reads what it has recorded — see
  /// `handle_screenshot_permission` in `linux/runner/capture_channel.cc`.
  @override
  Future<WholeScreenConsent> wholeScreenConsent() async {
    if (!isWayland) return WholeScreenConsent.given;
    final recorded = await _recordedPermission();
    return switch (recorded.permission) {
      'yes' => WholeScreenConsent.given,
      'no' => WholeScreenConsent.refused,
      _ =>
        recorded.asksInFront
            ? WholeScreenConsent.askInFront
            : WholeScreenConsent.given,
    };
  }

  /// What the portal has recorded about this application taking screenshots
  /// by itself, under the name it knows the application by, and whether this
  /// desktop asks only on behalf of the focused window.
  ///
  /// Never throws: it is asked on the way to every capture of the whole
  /// screen, and not knowing is an answer — the capture goes ahead and the
  /// desktop says what it says.
  Future<({String app, String permission, bool asksInFront})>
  _recordedPermission() async {
    try {
      final answer = await channel.invokeMethod<Map<Object?, Object?>>(
        'screenshotPermission',
      );
      return (
        app: answer?['app'] as String? ?? '',
        permission: answer?['permission'] as String? ?? 'unknown',
        asksInFront: answer?['asksInFront'] as bool? ?? false,
      );
    } on PlatformException {
      // Not knowing, below.
    } on MissingPluginException {
      // Likewise: a runner from before the question existed.
    }
    return (app: '', permission: 'unknown', asksInFront: false);
  }

  /// What to say once the desktop has refused the whole screen even with this
  /// window in front to ask on behalf of — which leaves two explanations, and
  /// the portal's permission store says which.
  ///
  /// Under GNOME a "no" is remembered and never asked again, and GNOME's
  /// settings have no switch for an application installed from a package, so
  /// the way back is spelt out in full. Region captures are unaffected either
  /// way: the user chooses those in the desktop's own interface, and the
  /// portal only asks about the ones taken without them.
  Future<String> _whyRefused() async {
    final recorded = await _recordedPermission();
    if (recorded.permission == 'no') {
      return 'Your desktop has been told not to let Snipper take screenshots '
          'by itself, so it no longer asks. Region captures still work. To be '
          'asked again, run:\n\n${forgetPermissionCommand(recorded.app)}';
    }
    return 'The desktop did not let Snipper capture the whole screen. If it '
        'is asking whether Snipper may take screenshots, answer it, then try '
        'again.';
  }

  /// The command that removes a remembered "no", so the desktop asks again.
  ///
  /// `gdbus` because it is on every GNOME desktop, which `flatpak` is not.
  /// The application ID is quoted as a GVariant string, because the empty ID
  /// — every unsandboxed application the portal cannot name — is otherwise no
  /// argument at all.
  static String forgetPermissionCommand(String app) =>
      'gdbus call --session '
      '--dest org.freedesktop.impl.portal.PermissionStore '
      '--object-path /org/freedesktop/impl/portal/PermissionStore '
      '--method org.freedesktop.impl.portal.PermissionStore.DeletePermission '
      "screenshot screenshot \"'$app'\"";

  Future<T> _invoke<T>(String method) async {
    try {
      final result = await channel.invokeMethod<T>(method);
      if (result == null) {
        throw CaptureException('The desktop answered $method with nothing.');
      }
      return result;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') throw const CaptureCancelled();
      if (error.code == 'portal-refused') {
        throw CaptureRefused(
          error.message ?? 'The desktop declined to take a screenshot.',
          cause: error.code,
        );
      }
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

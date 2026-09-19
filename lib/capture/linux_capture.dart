import '../model/display.dart';
import 'capture_service.dart';

/// Screen capture on Linux.
///
/// A placeholder until the X11 and portal backends land — see the plan's
/// ordering. It exists now so `CaptureService.forPlatform` compiles on both
/// targets and the controller above it can be written and tested once.
class LinuxCaptureService implements CaptureService {
  @override
  bool get canDrawOwnOverlay => true;

  @override
  Future<VirtualDesktop> enumerateDisplays() async =>
      throw const CaptureException(
        'Screen capture on Linux is not wired up yet.',
      );

  @override
  Future<CaptureResult> captureVirtualDesktop() async =>
      throw const CaptureException(
        'Screen capture on Linux is not wired up yet.',
      );

  @override
  void dispose() {}
}

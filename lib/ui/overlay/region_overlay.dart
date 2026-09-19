import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:slate_ui/slate_ui.dart';

import '../../controller/capture_controller.dart';
import '../../core/fire_and_forget.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ops/overlay_geometry.dart';
import 'overlay_painter.dart';

/// The frozen desktop with a rectangle being dragged out of it.
///
/// This replaces the whole window while a region capture is in progress — by
/// then the window has been made borderless and stretched over the desktop, so
/// there is no chrome left to keep.
///
/// **The geometry comes from `LayoutBuilder`, not from the window metrics.**
/// The window is resized to the desktop a frame or two after this widget first
/// builds, and reading `View.of(context)` does not register a dependency, so
/// nothing rebuilds when that finally happens. An earlier version guarded
/// against painting at the wrong size and waited for the metrics to agree;
/// since the rebuild never came, the guard never lifted, and the overlay was a
/// black screen the size of the desktop. `LayoutBuilder` rebuilds on every
/// resize by construction, and taking the scale from the size the frame is
/// *actually* painted into means there is nothing to wait for in the first
/// place.
class RegionOverlay extends StatefulWidget {
  const RegionOverlay({super.key});

  @override
  State<RegionOverlay> createState() => _RegionOverlayState();
}

class _RegionOverlayState extends State<RegionOverlay> {
  ui.Offset? _anchor;
  ui.Offset? _pointer;
  ui.Rect? _selection;

  @override
  Widget build(BuildContext context) {
    final captures = context.watch<CaptureController>();
    final frozen = captures.frozen;
    final theme = context.slate;
    final l10n = AppLocalizations.of(context);

    if (frozen == null) return const SizedBox.shrink();

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          captures.cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // A Material, not a ColoredBox, and not only for the black ground.
      //
      // `MaterialApp` does not wrap `home:` in a Material — `AppShell` gets one
      // from its Scaffold, and this route, which replaces the whole window,
      // has neither. Text with no Material above it is drawn with the yellow
      // double underline Flutter uses to say so, which on the overlay showed up
      // under the size readout.
      child: Material(
        color: const Color(0xFF000000),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final geometry = OverlayGeometry(
              bounds: frozen.bounds,
              logicalSize: constraints.biggest,
            );

            return Listener(
              onPointerDown: (event) => _onDown(captures, event),
              onPointerMove: (event) => _onMove(geometry, event),
              onPointerUp: (event) => _onUp(captures, geometry),
              onPointerHover: (event) =>
                  setState(() => _pointer = event.localPosition),
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CustomPaint(
                      painter: OverlayPainter(
                        frame: frozen.frame,
                        selection: _selection,
                        pointer: _selection == null ? _pointer : null,
                        accent: theme.palette.accent,
                      ),
                    ),
                    _Readout(
                      geometry: geometry,
                      selection: _selection,
                      hint: l10n.overlayHint,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onDown(CaptureController captures, PointerDownEvent event) {
    // A right-click is the other cancel, and the one a hand already on the
    // mouse reaches for.
    if (event.buttons & kSecondaryMouseButton != 0) {
      captures.cancel();
      return;
    }
    setState(() {
      _anchor = event.localPosition;
      _selection = ui.Rect.fromPoints(event.localPosition, event.localPosition);
    });
  }

  void _onMove(OverlayGeometry geometry, PointerMoveEvent event) {
    final anchor = _anchor;
    if (anchor == null) return;
    setState(() {
      _pointer = event.localPosition;
      _selection = geometry.dragRect(anchor, event.localPosition);
    });
  }

  void _onUp(CaptureController captures, OverlayGeometry geometry) {
    final selection = _selection;
    _anchor = null;
    if (selection == null) return;
    fireAndForget(captures.selectRegion(selection, geometry));
  }
}

/// The size of the selection in real pixels, or the hint before there is one.
///
/// Pinned to the top rather than following the pointer: a readout that moves is
/// a readout that ends up under the thing being measured.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.geometry,
    required this.selection,
    required this.hint,
  });

  final OverlayGeometry geometry;
  final ui.Rect? selection;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = context.slate;
    final region = selection;
    final String label;
    if (region == null || region.isEmpty) {
      label = hint;
    } else {
      final frame = geometry.toFrameRect(region);
      // i18n-exempt: two numbers and a multiplication sign.
      label = '${frame.width.toInt()} × ${frame.height.toInt()}';
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: DecoratedBox(
          decoration: theme.popoverDecoration,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(label, style: theme.textStyle),
          ),
        ),
      ),
    );
  }
}

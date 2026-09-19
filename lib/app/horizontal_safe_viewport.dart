import 'dart:ui' show DisplayFeature;

import 'package:flutter/widgets.dart';

/// Reserves side-mounted system chrome for every route, sheet, and overlay.
/// Descendants receive the usable window size so adaptive panes and interface
/// scaling do not lay themselves out beneath a vertical status area.
class HorizontalSafeViewport extends StatefulWidget {
  const HorizontalSafeViewport({
    super.key,
    required this.child,
    this.sideNavigation = false,
  });

  final bool sideNavigation;

  final Widget child;

  @override
  State<HorizontalSafeViewport> createState() => _HorizontalSafeViewportState();
}

class _HorizontalSafeViewportState extends State<HorizontalSafeViewport> {
  late final _entry = OverlayEntry(builder: _buildViewport);

  @override
  void didUpdateWidget(HorizontalSafeViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sideNavigation) _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    if (widget.sideNavigation) _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.sideNavigation
      ? Overlay(initialEntries: [_entry])
      : _buildViewport(context);

  Widget _buildViewport(BuildContext context) {
    final media = MediaQuery.of(context);
    final left = media.padding.left;
    final right = media.padding.right;
    final safeMedia = media.removePadding(removeLeft: true, removeRight: true);
    return Padding(
      padding: EdgeInsets.only(left: left, right: right),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final viewport = Offset.zero & size;
          return MediaQuery(
            data: safeMedia.copyWith(
              size: size,
              displayFeatures: [
                for (final feature in media.displayFeatures)
                  if (feature.bounds.right >= left &&
                      feature.bounds.left <= media.size.width - right)
                    DisplayFeature(
                      bounds: feature.bounds
                          .translate(-left, 0)
                          .intersect(viewport),
                      type: feature.type,
                      state: feature.state,
                    ),
              ],
            ),
            child: SideNavigationGeometry(
              window: media,
              enabled: widget.sideNavigation,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// The outer window geometry remains available after horizontal safe padding.
class SideNavigationGeometry extends InheritedWidget {
  const SideNavigationGeometry({
    super.key,
    required this.window,
    required this.enabled,
    required super.child,
  });
  final MediaQueryData window;
  final bool enabled;
  static SideNavigationGeometry? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SideNavigationGeometry>();

  /// Ordinary landscape camera insets are too narrow for navigation controls.
  bool fits(int count, double itemHeight) =>
      enabled &&
      window.size.height > window.size.width &&
      window.size.height >= 600 &&
      (window.padding.right >= 64 || window.padding.left >= 64) &&
      window.viewInsets.bottom == 0 &&
      count * itemHeight <= window.size.height / 2 - window.padding.bottom;

  @override
  bool updateShouldNotify(SideNavigationGeometry oldWidget) =>
      window != oldWidget.window || enabled != oldWidget.enabled;
}

/// Paints and hit-tests controls in the side strip of the full window overlay.
/// This overlay belongs to the unlocked app, below calls and the lock screen.
class SideNavigationPortal extends StatefulWidget {
  const SideNavigationPortal({
    super.key,
    required this.child,
    required this.visible,
  });
  final Widget child;
  final bool visible;
  @override
  State<SideNavigationPortal> createState() => _SideNavigationPortalState();
}

class _SideNavigationPortalState extends State<SideNavigationPortal> {
  final _controller = OverlayPortalController();
  @override
  void initState() {
    super.initState();
    _controller.show();
  }

  @override
  Widget build(BuildContext context) {
    final window = SideNavigationGeometry.of(context)!.window;
    final right = window.padding.right >= 64;
    return OverlayPortal(
      controller: _controller,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (_) => !widget.visible
          ? const SizedBox.shrink()
          : Positioned(
              right: right ? 0 : null,
              left: right ? null : 0,
              bottom: window.padding.bottom,
              width: right ? window.padding.right : window.padding.left,
              child: widget.child,
            ),
      child: const SizedBox.shrink(),
    );
  }
}

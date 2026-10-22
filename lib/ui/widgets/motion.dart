import 'dart:async';

import 'package:flutter/material.dart';

/// Animation durations and curves shared across the app.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 350);
  static const curve = Curves.easeOutCubic;
}

/// Cross-fades when the content changes. The child needs a different key or widget type to switch.
class FadeSwitcher extends StatelessWidget {
  const FadeSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.duration = Motion.medium,
    this.scale = false,
  });

  final Widget child;
  final Alignment alignment;
  final Duration duration;

  /// Scales up slightly while appearing (button state changes, etc.).
  final bool scale;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: duration,
    switchInCurve: Motion.curve,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => Stack(alignment: alignment, children: [...previous, ?current]),
    transitionBuilder: (child, animation) {
      final faded = FadeTransition(opacity: animation, child: child);
      return scale ? ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: faded) : faded;
    },
    child: child,
  );
}

/// Expands from the top or collapses with [visible]. Fully collapsed, the child isn't built.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.visible, required this.child, this.duration = Motion.slow});

  final bool visible;
  final Widget child;
  final Duration duration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.visible ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));

  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: Motion.curve,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(Reveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isDismissed && !widget.visible) return const SizedBox(width: double.infinity);
    // Clip only while animating; once expanded, glows and labels may extend outside.
    // (The widget structure must stay the same so the child's state isn't recreated when the animation ends.)
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) => ClipRect(
        clipBehavior: _controller.isAnimating ? Clip.hardEdge : Clip.none,
        child: Align(alignment: Alignment.topCenter, heightFactor: _curved.value, child: child),
      ),
      child: FadeTransition(opacity: _curved, child: widget.child),
    );
  }
}

/// Slides up slightly and fades in when first built. Shown immediately if [animate] is false.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.animate = true, this.delay = Duration.zero});

  final Widget child;
  final bool animate;
  final Duration delay;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  /// Created only if [Appear.animate] was true when first built; not created when shown without animation
  /// (cheaper during fast scrolling).
  ///
  /// Disposal is decided by this value. The widget's animate can change later (true at first, false on the next build),
  /// so deciding by it would leak a running animation.
  AnimationController? _controller;
  Animation<double>? _curved;
  Animation<Offset>? _offset;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;

    final controller = _controller = AnimationController(vsync: this, duration: Motion.slow);
    final curved = _curved = CurvedAnimation(parent: controller, curve: Motion.curve);
    _offset = Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved);
    if (widget.delay == Duration.zero) {
      controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = _curved;
    final offset = _offset;
    if (curved == null || offset == null) return widget.child;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: offset, child: widget.child),
    );
  }
}

/// Card whose background and border change smoothly on hover. Shaped like a Material 3 Card.
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.background,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Makes the card tappable (opening a folder, etc.).
  final VoidCallback? onTap;

  /// Background behind the card (video thumbnail, etc.), clipped to the card shape.
  final Widget Function(BuildContext context, bool hovered)? background;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Curves.easeOut,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceContainerHigh : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          // The border must be painted over the background image to be visible.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hovered ? colors.outlineVariant : colors.outlineVariant.withValues(alpha: 0)),
          ),
          child: Stack(
            children: [
              if (widget.background case final background?) Positioned.fill(child: background(context, _hovered)),
              AnimatedPadding(
                duration: Motion.medium,
                curve: Motion.curve,
                padding: widget.padding,
                child: AnimatedSize(
                  duration: Motion.medium,
                  curve: Motion.curve,
                  alignment: Alignment.topCenter,
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

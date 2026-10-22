import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/rendering.dart' show ScrollDirection;

/// Scroll controller that glides smoothly on mouse wheel input instead of jumping.
///
/// Scrollable forwards wheel events through [ScrollPosition.pointerScroll], so only that is replaced.
/// Dragging, the scrollbar and keyboard scrolling keep the default behavior.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({super.debugLabel});

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _SmoothScrollPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      super.pointerScroll(delta);
      return;
    }

    updateUserScrollDirection(delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward);

    // While gliding, only move the target so the velocity carries on.
    if (activity case final _WheelScrollActivity wheel) {
      wheel.target = (wheel.target + delta).clamp(minScrollExtent, maxScrollExtent);
      return;
    }

    final target = (pixels + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels) return;
    beginActivity(_WheelScrollActivity(this, context.vsync, target));
  }
}

/// Like browsers: a wheel tick sets a target, and every frame covers a fixed fraction of the remaining distance.
/// Repeated ticks just push the target further, so scrolling continues without stopping and restarting.
class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(ScrollPositionWithSingleContext super.delegate, TickerProvider vsync, this.target) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  /// The remaining distance shrinks by about 1/e every this many seconds; 0.07 arrives in roughly 0.2 s.
  static const _timeConstant = 0.07;

  double target;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _velocity = 0;

  @override
  ScrollPositionWithSingleContext get delegate => super.delegate as ScrollPositionWithSingleContext;

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    if (dt <= 0) return;

    final position = delegate.pixels;
    final remaining = target - position;
    if (remaining.abs() < 0.5) {
      delegate.setPixels(target);
      delegate.goIdle();
      return;
    }

    final step = remaining * (1 - exp(-dt / _timeConstant));
    _velocity = step / dt;
    // Stop at the edge.
    if (delegate.setPixels(position + step) != 0) delegate.goIdle();
  }

  @override
  bool get shouldIgnorePointer => true;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Adds an always-visible scrollbar and smooth wheel scrolling.
/// The default desktop scrollbar is turned off so they don't overlap.
class SmoothScrollbar extends StatelessWidget {
  const SmoothScrollbar({super.key, required this.controller, required this.builder});

  final SmoothScrollController controller;

  /// Builds the scroll view with the [ScrollBehavior] to pass to it.
  final Widget Function(BuildContext context, ScrollBehavior behavior) builder;

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: controller,
    thumbVisibility: true,
    interactive: true,
    child: builder(context, ScrollConfiguration.of(context).copyWith(scrollbars: false)),
  );
}

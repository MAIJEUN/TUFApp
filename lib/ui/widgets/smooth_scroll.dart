import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/rendering.dart' show ScrollDirection;

/// 마우스 휠로 스크롤할 때 한 번에 뛰지 않고 부드럽게 미끄러지게 하는 컨트롤러.
///
/// 휠 이벤트는 Scrollable이 [ScrollPosition.pointerScroll]로 넘기므로 그 부분만 바꾼다.
/// 드래그, 스크롤바, 키보드 스크롤은 기본 동작 그대로다.
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

    // 굴리는 중이면 목표만 옮긴다. 속도가 끊기지 않고 이어진다.
    if (activity case final _WheelScrollActivity wheel) {
      wheel.target = (wheel.target + delta).clamp(minScrollExtent, maxScrollExtent);
      return;
    }

    final target = (pixels + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels) return;
    beginActivity(_WheelScrollActivity(this, context.vsync, target));
  }
}

/// 브라우저처럼 휠을 굴리면 목표 위치를 정하고, 매 프레임 남은 거리의 일정 비율만큼 따라간다.
/// 휠을 연달아 굴리면 목표만 멀어지므로 멈췄다 다시 출발하는 일 없이 매끄럽게 이어진다.
class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(ScrollPositionWithSingleContext super.delegate, TickerProvider vsync, this.target) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  /// 남은 거리가 이 시간(초)마다 약 1/e로 줄어든다. 0.07이면 약 0.2초 만에 거의 도착한다.
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
    // 끝에 닿아 더 갈 수 없으면 멈춘다.
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

/// 항상 보이는 스크롤바 + 부드러운 휠 스크롤을 붙인다.
/// 기본 데스크톱 스크롤바는 겹치지 않도록 끈다.
class SmoothScrollbar extends StatelessWidget {
  const SmoothScrollbar({super.key, required this.controller, required this.builder});

  final SmoothScrollController controller;

  /// 스크롤 뷰에 넘길 [ScrollBehavior]를 받아 스크롤 뷰를 만든다.
  final Widget Function(BuildContext context, ScrollBehavior behavior) builder;

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: controller,
    thumbVisibility: true,
    interactive: true,
    child: builder(context, ScrollConfiguration.of(context).copyWith(scrollbars: false)),
  );
}

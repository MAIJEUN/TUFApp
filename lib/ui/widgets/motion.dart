import 'dart:async';

import 'package:flutter/material.dart';

/// 앱 전체에서 같이 쓰는 애니메이션 시간과 곡선.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 350);
  static const curve = Curves.easeOutCubic;
}

/// 내용이 바뀔 때 이전 것은 흐려지고 새 것이 나타난다. 자식에 key를 주거나 위젯 종류가 달라야 전환된다.
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

  /// 나타날 때 살짝 커지게 한다 (버튼 상태 전환 등).
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

/// [visible]에 따라 위에서부터 펼쳐지거나 접힌다. 완전히 접혀 있으면 자식을 만들지 않는다.
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
    // 움직이는 동안에만 잘라낸다. 다 펼쳐진 뒤에는 난이도 이름의 빛이나 라벨이 밖으로 나가도 보이게 둔다.
    // (위젯 구조는 그대로 두어야 자식 상태가 애니메이션 끝에 다시 만들어지지 않는다.)
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

/// 처음 만들어질 때 아래에서 살짝 올라오며 나타난다. [animate]가 false면 바로 보인다.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.animate = true, this.delay = Duration.zero});

  final Widget child;
  final bool animate;
  final Duration delay;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  /// 처음 만들어질 때 [Appear.animate]였으면 만든다. 애니메이션 없이 보여줄 때는 만들지 않는다
  /// (빠르게 스크롤할 때 부담을 줄인다).
  ///
  /// 정리할지는 이 값으로 정한다. 위젯의 animate는 나중에 바뀔 수 있어서(처음엔 true, 다음 빌드에서 false)
  /// 그것을 보고 정리하면 돌고 있던 애니메이션을 놓친다.
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

/// 마우스를 올리면 배경과 테두리가 부드럽게 바뀌는 카드. Material 3 Card와 같은 모양이다.
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

  /// 카드를 누를 수 있게 한다 (폴더 열기 등).
  final VoidCallback? onTap;

  /// 카드 뒤에 깔 배경 (영상 썸네일 등). 카드 모양대로 잘린다.
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
          // 테두리는 배경 이미지 위에 그려야 보인다.
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

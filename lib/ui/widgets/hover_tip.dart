import 'dart:async';

import 'package:flutter/material.dart';

/// 목록 카드 안에 수십 개씩 들어가는 작은 툴팁.
///
/// 기본 [Tooltip]은 화면의 모든 포인터 이벤트(마우스 이동, 휠)를 툴팁마다 받아 보고,
/// 그때 애니메이션 컨트롤러를 만든다. 카드마다 10개가 넘으니 휠 한 칸에도 수백 개가 깨어나고,
/// 빠르게 스크롤하면 오류까지 난다.
/// 이 위젯은 마우스가 실제로 올라왔을 때만 일하고, 한 번에 하나만 띄운다.
class HoverTip extends StatefulWidget {
  const HoverTip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  /// 마우스를 올리고 이만큼 머물러야 뜬다.
  static const delay = Duration(milliseconds: 500);

  @override
  State<HoverTip> createState() => _HoverTipState();
}

class _HoverTipState extends State<HoverTip> {
  /// 지금 떠 있는 툴팁. 새로 뜨면 이전 것은 닫는다.
  static _HoverTipState? _shown;

  Timer? _timer;
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    // 다른 툴팁이 떠 있던 중이면 옮겨 다닐 때 기다리지 않는다.
    _timer = Timer(_shown != null ? Duration.zero : HoverTip.delay, _show);
  }

  void _show() {
    if (!mounted || widget.message.isEmpty) return;
    final box = context.findRenderObject();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (box is! RenderBox || !box.attached || overlay == null) return;

    _shown?._hide();
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final target = box.localToGlobal(box.size.center(Offset.zero), ancestor: overlayBox);
    final verticalOffset = box.size.height / 2 + 6;

    _entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _TipLayout(target: target, verticalOffset: verticalOffset),
          child: _TipBubble(message: widget.message),
        ),
      ),
    );
    overlay.insert(_entry!);
    _shown = this;
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    if (identical(_shown, this)) _shown = null;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _schedule(),
    onExit: (_) => _hide(),
    child: Listener(onPointerDown: (_) => _hide(), child: widget.child),
  );
}

class _TipLayout extends SingleChildLayoutDelegate {
  const _TipLayout({required this.target, required this.verticalOffset});

  final Offset target;
  final double verticalOffset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: target,
    verticalOffset: verticalOffset,
    preferBelow: true,
    margin: 8,
  );

  @override
  bool shouldRelayout(_TipLayout oldDelegate) =>
      target != oldDelegate.target || verticalOffset != oldDelegate.verticalOffset;
}

/// 기본 툴팁과 같은 모양의 말풍선. 살짝 나타난다.
class _TipBubble extends StatelessWidget {
  const _TipBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltipTheme = TooltipTheme.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 120),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            tooltipTheme.decoration ??
            BoxDecoration(color: Colors.grey[700]!.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(4)),
        child: Text(message, style: tooltipTheme.textStyle ?? theme.textTheme.bodySmall?.copyWith(color: Colors.white)),
      ),
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 내용이 칸보다 길면 넘치는 쪽 끝을 **가로로만** 부드럽게 지운다.
/// 자식은 폭 제한 없이 배치되므로 Row처럼 좁히면 터지는 위젯도 담을 수 있다.
///
/// [offset]만큼 왼쪽으로 밀어서 그린다 (미끄러지는 애니메이션에 쓴다).
/// 다 들어가는 내용은 레이어를 만들지 않고 그대로 그린다.
class FadeEdges extends SingleChildRenderObjectWidget {
  const FadeEdges({super.key, required Widget super.child, this.offset = 0, this.fadeWidth = 16});

  final double offset;
  final double fadeWidth;

  @override
  RenderFadeEdges createRenderObject(BuildContext context) => RenderFadeEdges(offset: offset, fadeWidth: fadeWidth);

  @override
  void updateRenderObject(BuildContext context, RenderFadeEdges renderObject) {
    renderObject
      ..offset = offset
      ..fadeWidth = fadeWidth;
  }
}

class RenderFadeEdges extends RenderProxyBox {
  RenderFadeEdges({required double offset, required double fadeWidth})
    // ignore: prefer_initializing_formals
    : _offset = offset,
      // ignore: prefer_initializing_formals
      _fadeWidth = fadeWidth;

  double _offset;
  double _fadeWidth;

  /// 지금 왼쪽으로 밀려 있는 정도.
  double get offset => _offset;

  set offset(double value) {
    if (_offset == value) return;
    _offset = value;
    markNeedsPaint();
  }

  set fadeWidth(double value) {
    if (_fadeWidth == value) return;
    _fadeWidth = value;
    markNeedsPaint();
  }

  /// 칸보다 얼마나 더 긴지. 0이면 다 들어간다.
  double get overflow {
    final child = this.child;
    if (child == null || !hasSize) return 0;
    return (child.size.width - size.width).clamp(0.0, double.infinity);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }

    final wasOverflowing = hasSize && overflow > 0;
    // 폭은 제한하지 않는다 (Row가 넘쳐도 터지지 않는다). 높이는 부모가 준 대로.
    child.layout(
      BoxConstraints(minHeight: constraints.minHeight, maxHeight: constraints.maxHeight),
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
    // 넘치기 시작하거나 멈추면 마스크 레이어가 필요한지가 바뀐다.
    if (wasOverflowing != overflow > 0) markNeedsCompositingBitsUpdate();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(-_offset, 0),
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;

    final childOffset = offset + Offset(-_offset, 0);
    // 다 들어가면 레이어도 잘라내기도 필요 없다 (목록에 수백 개가 놓이므로 중요하다).
    if (overflow <= 0 && _offset <= 0) {
      context.paintChild(child, childOffset);
      return;
    }

    final fadeStart = _offset > 0.5;
    final fadeEnd = _offset < overflow - 0.5;
    if (!fadeStart && !fadeEnd) {
      context.pushClipRect(needsCompositing, offset, Offset.zero & size, (context, offset) {
        context.paintChild(child, childOffset);
      });
      return;
    }

    // 가장자리는 ShaderMask와 같은 방식(마스크 레이어)으로 지운다.
    // 캔버스에 직접 레이어를 여닫으면, 안쪽에 따로 레이어가 필요한 내용(나타나는 중인 아이콘 등)이 있을 때
    // 그 사이에 캔버스가 바뀌어 오류가 난다. 마스크 레이어는 그런 내용도 함께 감싼다.
    //
    // 칸이 소수점 위치에 놓이면 가장자리 픽셀이 칸에 반쯤만 걸치고, 레이어 경계도 픽셀 단위로 반올림된다.
    // 칸 크기로만 지우면 걸친 한 줄이 남으므로, 자르기는 칸보다 조금 넓게, 지우기는 그보다 더 넓게 한다.
    // 그라디언트는 끝 색이 이어져서(clamp) 칸 밖으로 넓힌 곳은 투명하게 지워진다.
    const clipOut = 2.0;
    const maskOut = 6.0;
    final fade = (_fadeWidth / size.width).clamp(0.0, 0.5);
    final mask = Rect.fromLTRB(
      offset.dx - maskOut,
      offset.dy - maskOut,
      offset.dx + size.width + maskOut,
      offset.dy + size.height + maskOut,
    );

    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTRB(-clipOut, 0, size.width + clipOut, size.height),
      oldLayer: _clipLayer.layer,
      (context, offset) {
        final layer = _maskLayer.layer ??= ShaderMaskLayer();
        layer
          ..maskRect = mask
          ..blendMode = BlendMode.dstIn
          // 셰이더 좌표는 마스크 사각형의 왼쪽 위가 기준이다.
          ..shader = ui.Gradient.linear(
            Offset(maskOut, maskOut + size.height / 2),
            Offset(maskOut + size.width, maskOut + size.height / 2),
            const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            [0, fadeStart ? fade : 0, fadeEnd ? 1 - fade : 1, 1],
          );
        context.pushLayer(layer, (context, _) => context.paintChild(child, childOffset), Offset.zero);
      },
    );
  }

  final _maskLayer = LayerHandle<ShaderMaskLayer>();
  final _clipLayer = LayerHandle<ClipRectLayer>();

  /// 넘칠 때는 마스크 레이어를 쓰므로 합성이 필요하다.
  @override
  bool get alwaysNeedsCompositing => child != null && (overflow > 0 || _offset > 0);

  @override
  void dispose() {
    _maskLayer.layer = null;
    _clipLayer.layer = null;
    super.dispose();
  }
}

/// 내용이 칸보다 길면 마우스를 올렸을 때 끝까지 흘러가서 멈춰 있고, 마우스를 치우면 처음으로 돌아온다.
/// 평소에는 넘치는 쪽 끝만 흐리게 지운 채 가만히 있는다.
class SlideOverflow extends StatefulWidget {
  const SlideOverflow({super.key, required this.child});

  final Widget child;

  @override
  State<SlideOverflow> createState() => _SlideOverflowState();
}

class _SlideOverflowState extends State<SlideOverflow> with SingleTickerProviderStateMixin {
  /// 흘러가는 속도 (초당 픽셀).
  static const _speedPerSecond = 60.0;

  /// 돌아올 때는 빠르게.
  static const _returnDuration = Duration(milliseconds: 300);

  late final AnimationController _controller = AnimationController(vsync: this);
  final _key = GlobalKey();
  bool _hovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _overflow {
    final render = _key.currentContext?.findRenderObject();
    return render is RenderFadeEdges ? render.overflow : 0.0;
  }

  /// 마우스가 들어온 시점에는 배치가 이미 끝나 있으므로 바로 시작한다.
  /// (다음 프레임을 기다리면, 다른 변화가 없을 때 프레임이 오지 않아 움직이지 않는다.)
  void _onEnter() {
    _hovered = true;
    final distance = _overflow;
    if (distance <= 1) return;

    final remaining = distance * (1 - _controller.value);
    final ms = (remaining / _speedPerSecond * 1000).round().clamp(300, 8000);
    _controller.animateTo(
      1,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeInOut,
    );
  }

  void _onExit() {
    if (!_hovered) return;
    _hovered = false;
    if (_controller.value == 0 && !_controller.isAnimating) return;
    _controller.animateTo(0, duration: _returnDuration, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _onEnter(),
    onExit: (_) => _onExit(),
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => FadeEdges(key: _key, offset: _overflow * _controller.value, child: child!),
      child: widget.child,
    ),
  );
}

/// 미끄러뜨려 보여줄 한 줄 글자. 줄바꿈과 자르기를 끈다.
/// 끝부분을 흐리게 지우는 일은 [FadeEdges]가 가로로만 처리한다.
Text slidingText(String text, {TextStyle? style}) =>
    Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style);

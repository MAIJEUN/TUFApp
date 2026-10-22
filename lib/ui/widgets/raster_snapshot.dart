import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 그리기 비싼 부분(아이콘이 수십 개 겹친 줄, 테를 두른 태그들)을 그림 한 장으로 구워 두고,
/// 스크롤할 때는 그 그림만 그린다.
///
/// 이 앱의 그리기 엔진(Impeller)은 바뀌지 않은 내용도 프레임마다 처음부터 다시 그린다.
/// 그래서 작은 아이콘을 수십 번 그리거나 섞기 레이어를 여러 번 여는 줄이 화면에 많으면 스크롤이 끊긴다.
///
/// 이 위젯은 다시 그리기 경계(repaint boundary)라서, 안쪽이 바뀔 때만(아이콘을 다 받았을 때,
/// 애니메이션이 움직일 때) 다시 굽는다. 스크롤만 할 때는 굽지 않고 구워 둔 한 장을 그대로 쓴다.
/// 마우스·누르기는 안쪽 위젯이 그대로 받는다.
///
/// 안쪽에 또 다른 다시 그리기 경계가 있으면 그 부분이 바뀐 것을 알 수 없으므로 쓰지 않는다.
class RasterSnapshot extends SingleChildRenderObjectWidget {
  const RasterSnapshot({super.key, required Widget super.child});

  @override
  RenderRasterSnapshot createRenderObject(BuildContext context) =>
      RenderRasterSnapshot(devicePixelRatio: MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderRasterSnapshot renderObject) {
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderRasterSnapshot extends RenderProxyBox {
  RenderRasterSnapshot({required double devicePixelRatio})
    // ignore: prefer_initializing_formals
    : _devicePixelRatio = devicePixelRatio;

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// 몇 번 구웠는지 (테스트에서 스크롤 중에 다시 굽지 않는지 본다).
  @visibleForTesting
  int bakeCount = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || size.isEmpty) return;

    // 안쪽에 다시 그리기 경계(투명도 애니메이션 등)가 있으면, 그 부분이 바뀌어도 이 위젯은 다시 그려지지 않아
    // 구워 둔 그림이 옛 모습으로 굳는다. 그럴 때는 굽지 않고 그냥 그린다 (느려도 틀리지 않게).
    if (_hasInnerBoundary(child)) {
      context.paintChild(child, offset);
      return;
    }

    // 안쪽을 따로 레이어에 그려서 한 장으로 굽는다.
    final layer = OffsetLayer();
    final inner = PaintingContext(layer, Offset.zero & size);
    inner.paintChild(child, Offset.zero);
    // ignore: invalid_use_of_protected_member
    inner.stopRecordingIfNeeded();
    if (!layer.supportsRasterization()) {
      // 굽지 못하는 내용(플랫폼 뷰)이면 그냥 그린다.
      layer.dispose();
      context.paintChild(child, offset);
      return;
    }
    final image = layer.toImageSync(Offset.zero & size, pixelRatio: _devicePixelRatio);
    layer.dispose();
    bakeCount++;

    context.canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      offset & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    // 그린 그림(picture)이 이 그림을 따로 붙잡고 있으므로 여기서 놓아도 된다.
    // 다시 붙었을 때(스크롤해서 돌아왔을 때) 다시 굽지 않고 그 picture를 그대로 쓴다.
    image.dispose();
  }

  static bool _hasInnerBoundary(RenderObject node) {
    var found = false;
    void visit(RenderObject child) {
      if (found) return;
      if (child.isRepaintBoundary) {
        found = true;
        return;
      }
      child.visitChildren(visit);
    }

    node.visitChildren(visit);
    return found || node.isRepaintBoundary;
  }
}

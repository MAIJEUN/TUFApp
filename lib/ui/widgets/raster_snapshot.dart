import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Bakes expensive content (rows of dozens of overlapping icons, ringed tags) into one image
/// and draws only that image while scrolling.
///
/// The app's renderer (Impeller) redraws unchanged content from scratch every frame,
/// so many rows drawing dozens of small icons or opening blend layers make scrolling stutter.
///
/// This widget is a repaint boundary and only re-bakes when its content changes (icons finished loading,
/// animations running). Plain scrolling reuses the baked image. Pointer input still reaches the child.
///
/// It falls back to normal painting when the child contains another
/// repaint boundary, since changes there can't be detected.
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

  /// Number of bakes (tests check that scrolling doesn't re-bake).
  @visibleForTesting
  int bakeCount = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || size.isEmpty) return;

    // A repaint boundary inside (an opacity animation, etc.) can change without repainting this widget,
    // which would freeze the baked image in an old state. Paint normally then (slower, but correct).
    if (_hasInnerBoundary(child)) {
      context.paintChild(child, offset);
      return;
    }

    // Paint the child into its own layer and bake it into one image.
    final layer = OffsetLayer();
    final inner = PaintingContext(layer, Offset.zero & size);
    inner.paintChild(child, Offset.zero);
    // ignore: invalid_use_of_protected_member
    inner.stopRecordingIfNeeded();
    if (!layer.supportsRasterization()) {
      // Paint normally if the content can't be rasterized (platform views).
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
    // The recorded picture holds its own reference to the image, so it can be released here.
    // When reattached (scrolled back into view), that picture is reused without re-baking.
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

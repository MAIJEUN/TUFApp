import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/models/difficulty.dart';
import '../theme.dart';
import 'common.dart';

/// TUF 웹의 DifficultySlider를 옮긴 난이도 범위 슬라이더.
/// 난이도 색 그라데이션 트랙 위에 난이도 아이콘 노브 두 개로 범위를 고른다.
///
/// - 끄는 중에는 노브가 손을 바로 따라오고, 놓았을 때 [onChanged]를 한 번 호출한다 (검색도 한 번만).
/// - 밖에서 값이 바뀌면(초기화 등) 노브와 선택 범위가 부드럽게 이동한다.
class DifficultySlider extends StatefulWidget {
  const DifficultySlider({
    super.key,
    required this.difficulties,
    required this.lower,
    required this.upper,
    required this.onChanged,
  });

  final List<Difficulty> difficulties;
  final int lower;
  final int upper;
  final void Function(int lower, int upper) onChanged;

  @override
  State<DifficultySlider> createState() => _DifficultySliderState();
}

class _DifficultySliderState extends State<DifficultySlider> {
  static const side = 24.0;
  static const trackTop = 40.0;
  static const trackHeight = 12.0;
  static const _knobSize = 40.0;
  static const _labelWidth = 140.0;
  static const _height = 92.0;

  static const _moveDuration = Duration(milliseconds: 260);
  static const _moveCurve = Curves.easeOutCubic;

  late int _lower = _clamp(widget.lower);
  late int _upper = _clamp(widget.upper);

  /// 0: 처음 잡은 노브가 [_lower], 1: [_upper], null: 끄는 중 아님
  int? _dragKnob;

  int get _maxIndex => max(0, widget.difficulties.length - 1);

  int _clamp(int index) => index.clamp(0, _maxIndex);

  @override
  void didUpdateWidget(DifficultySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragKnob == null) {
      _lower = _clamp(widget.lower);
      _upper = _clamp(widget.upper);
    }
  }

  static double xAt(double index, int count, double width) {
    final usable = max(0.0, width - side * 2);
    return count <= 1 ? side : side + usable * index / (count - 1);
  }

  int _indexAt(double x, double width) {
    final count = widget.difficulties.length;
    if (count <= 1) return 0;
    final usable = max(1.0, width - side * 2);
    return (((x - side) / usable).clamp(0.0, 1.0) * (count - 1)).round();
  }

  void _onPointerDown(PointerDownEvent event, double width) {
    if (widget.difficulties.isEmpty) return;
    if (event.kind == PointerDeviceKind.mouse && (event.buttons & kPrimaryMouseButton) == 0) return;

    // 웹과 같이 누른 위치에서 더 가까운 노브를 움직인다.
    final index = _indexAt(event.localPosition.dx, width);
    setState(() {
      _dragKnob = (_lower - index).abs() <= (_upper - index).abs() ? 0 : 1;
      _moveDragged(index);
    });
  }

  void _onPointerMove(PointerMoveEvent event, double width) {
    if (_dragKnob == null) return;
    final index = _indexAt(event.localPosition.dx, width);
    if ((_dragKnob == 0 ? _lower : _upper) != index) setState(() => _moveDragged(index));
  }

  void _moveDragged(int index) {
    if (_dragKnob == 0) {
      _lower = index;
    } else {
      _upper = index;
    }
  }

  /// 놓았을 때 순서를 바로잡고 알린다. 노브는 서로 넘어갈 수 있다.
  void _commit() {
    if (_dragKnob == null) return;
    setState(() {
      _dragKnob = null;
      final low = min(_lower, _upper);
      final high = max(_lower, _upper);
      _lower = low;
      _upper = high;
    });
    if (_lower != widget.lower || _upper != widget.upper) widget.onChanged(_lower, _upper);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.difficulties;
    if (list.isEmpty) return const SizedBox(height: _height);

    final colors = [for (final d in list) parseHexColor(d.color) ?? Colors.grey];
    final dragging = _dragKnob != null;
    final duration = dragging ? Duration.zero : _moveDuration;

    // 끄는 노브가 현재 낮은 쪽인지 (노브가 서로 넘어가면 바뀐다)
    final draggingLow = dragging && ((_dragKnob == 0) == (_lower <= _upper));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return MouseRegion(
          cursor: dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.click,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _onPointerDown(e, width),
            onPointerMove: (e) => _onPointerMove(e, width),
            onPointerUp: (_) => _commit(),
            onPointerCancel: (_) => _commit(),
            child: SizedBox(
              width: width,
              height: _height,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: min(_lower, _upper).toDouble()),
                duration: duration,
                curve: _moveCurve,
                builder: (context, low, _) => TweenAnimationBuilder<double>(
                  tween: Tween(end: max(_lower, _upper).toDouble()),
                  duration: duration,
                  curve: _moveCurve,
                  builder: (context, high, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TrackPainter(colors: colors, low: low, high: high),
                        ),
                      ),
                      ..._knob(context, list, colors, low, width, active: draggingLow),
                      ..._knob(context, list, colors, high, width, active: dragging && !draggingLow),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _knob(
    BuildContext context,
    List<Difficulty> list,
    List<Color> colors,
    double position,
    double width, {
    required bool active,
  }) {
    final index = position.round().clamp(0, list.length - 1);
    final difficulty = list[index];
    final color = colors[index];
    final x = xAt(position, list.length, width);

    // "GQ0 (G1~G4)" → 위에 "GQ0", 아래에 "(G1~G4)"
    final words = difficulty.name.split(' ');
    final glow = _glowColor(difficulty, color);

    return [
      Positioned(
        left: x - _labelWidth / 2,
        top: trackTop + 30,
        width: _labelWidth,
        child: IgnorePointer(
          child: Text(
            words.length > 1 ? words.sublist(1).join(' ') : '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.2, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ),
      Positioned(
        left: x - _knobSize / 2,
        top: trackTop + trackHeight / 2 - _knobSize / 2,
        child: IgnorePointer(
          child: AnimatedScale(
            scale: active ? 1.15 : 1,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: active ? 10 : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: NetworkIcon(difficulty.icon, size: _knobSize),
            ),
          ),
        ),
      ),
      Positioned(
        left: x - _labelWidth / 2,
        top: 0,
        width: _labelWidth,
        child: IgnorePointer(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              fontSize: 17.6,
              fontWeight: FontWeight.w800,
              color: color,
              shadows: [
                const Shadow(color: Colors.black, blurRadius: 2),
                const Shadow(color: Colors.black, offset: Offset(0, 1), blurRadius: 2),
                Shadow(color: glow, blurRadius: 12),
                Shadow(color: glow, blurRadius: 12),
              ],
            ),
            child: Text(words.first, textAlign: TextAlign.center),
          ),
        ),
      ),
    ];
  }

  /// 웹과 같이 U14 이상과 Q 난이도는 흰색으로 빛나게 한다.
  static Color _glowColor(Difficulty difficulty, Color color) {
    final name = difficulty.name;
    if (name.startsWith('U')) {
      final number = int.tryParse(name.substring(1));
      if (number != null && number > 13) return Colors.white;
    }
    if (name.startsWith('Q')) return Colors.white;
    return color;
  }
}

/// 전체 트랙은 흐리게, 고른 범위는 선명하게 + 은은한 빛으로 그린다.
/// [low]/[high]는 애니메이션 중 소수가 될 수 있다.
class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.colors, required this.low, required this.high});

  final List<Color> colors;
  final double low;
  final double high;

  @override
  void paint(Canvas canvas, Size size) {
    final count = colors.length;
    if (count < 2) return;

    const side = _DifficultySliderState.side;
    const top = _DifficultySliderState.trackTop;
    const height = _DifficultySliderState.trackHeight;
    final usable = max(0.0, size.width - side * 2);

    final trackRect = Rect.fromLTWH(side, top, usable, height);
    canvas.saveLayer(trackRect.inflate(2), Paint()..color = Colors.white.withValues(alpha: 0.28));
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(6)),
      Paint()..shader = LinearGradient(colors: colors).createShader(trackRect),
    );
    canvas.restore();

    final left = _DifficultySliderState.xAt(low, count, size.width);
    final right = _DifficultySliderState.xAt(high, count, size.width);
    if (right - left < 1) return;

    final rangeRect = Rect.fromLTRB(left, top - 4, right, top + height + 4);
    final range = RRect.fromRectAndRadius(rangeRect, const Radius.circular(12));
    canvas.drawRRect(
      range,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(range, Paint()..shader = _rangeGradient().createShader(rangeRect));
  }

  /// 범위 안에 들어가는 난이도 색으로 그라데이션을 만든다. 끝이 소수여도 위치를 맞춘다.
  LinearGradient _rangeGradient() {
    final first = low.floor();
    final last = min(colors.length - 1, high.ceil());
    final span = high - low;

    final stops = <double>[];
    final rangeColors = <Color>[];
    for (var i = first; i <= last; i++) {
      stops.add(((i - low) / span).clamp(0.0, 1.0));
      rangeColors.add(colors[i]);
    }
    if (rangeColors.length < 2) return LinearGradient(colors: [rangeColors.first, rangeColors.first]);
    return LinearGradient(colors: rangeColors, stops: stops);
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) =>
      oldDelegate.low != low || oldDelegate.high != high || !listEquals(oldDelegate.colors, colors);
}

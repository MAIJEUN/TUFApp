import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/ui/widgets/smooth_scroll.dart';

/// Wheel scrolling glides instead of jumping and continues smoothly across repeated ticks.
void main() {
  late SmoothScrollController controller;

  Future<void> pump(WidgetTester tester) async {
    controller = SmoothScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SmoothScrollbar(
          controller: controller,
          builder: (context, behavior) => ScrollConfiguration(
            behavior: behavior,
            child: ListView.builder(
              controller: controller,
              itemCount: 200,
              itemBuilder: (context, index) => SizedBox(height: 50, child: Text('$index')),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final center = tester.getCenter(find.byType(ListView));
    tester.binding.handlePointerEvent(PointerScrollEvent(position: center, scrollDelta: Offset(0, dy)));
  }

  testWidgets('한 번 굴리면 부드럽게 가서 멈춘다', (tester) async {
    await pump(tester);
    await wheel(tester, 100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final early = controller.offset;
    expect(early, greaterThan(0));
    expect(early, lessThan(100), reason: '한 번에 뛰지 않는다');

    await tester.pumpAndSettle();
    expect(controller.offset, 100);
  });

  testWidgets('연달아 굴리면 속도가 끊기지 않고 목표가 더해진다', (tester) async {
    await pump(tester);
    var last = 0.0;
    for (var i = 0; i < 5; i++) {
      await wheel(tester, 100);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, greaterThanOrEqualTo(last), reason: '뒤로 가거나 멈칫하지 않는다');
        last = controller.offset;
      }
    }
    await tester.pumpAndSettle();
    expect(controller.offset, 500);
  });

  testWidgets('끝을 넘어가지 않는다', (tester) async {
    await pump(tester);
    await wheel(tester, -300);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/ui/widgets/hover_tip.dart';
import 'package:tufapp/ui/widgets/slide_overflow.dart';
import 'package:tufapp/ui/widgets/smooth_scroll.dart';

/// 마우스를 올려 둔 채로 빠르게 스크롤해도 툴팁에서 오류가 나지 않아야 한다.
void main() {
  testWidgets('마우스를 올린 채 빠르게 스크롤해도 오류가 없다', (tester) async {
    final controller = SmoothScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SmoothScrollbar(
          controller: controller,
          builder: (context, behavior) => ScrollConfiguration(
            behavior: behavior,
            child: ListView.builder(
              controller: controller,
              itemCount: 500,
              itemBuilder: (context, index) => SizedBox(
                height: 60,
                child: Row(
                  children: [
                    for (var i = 0; i < 6; i++)
                      SizedBox(
                        width: 100,
                        child: HoverTip(
                          message: 'tip $index/$i',
                          child: SlideOverflow(child: slidingText('아주 긴 글자 $index $i 가나다라마바사아')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(250, 300));
    addTearDown(mouse.removePointer);
    await tester.pump();

    for (var round = 0; round < 3; round++) {
      for (var i = 0; i < 40; i++) {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(position: const Offset(250, 300), scrollDelta: Offset(0, round.isEven ? 300 : -300)),
        );
        await mouse.moveBy(Offset(i.isEven ? 3 : -3, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    }
    await mouse.moveTo(const Offset(900, 900));
    await tester.pumpAndSettle();
  });

  testWidgets('마우스를 올리고 잠시 있으면 뜨고, 치우면 사라진다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: HoverTip(message: '클리어 3명', child: SizedBox(width: 40, height: 40)),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.byType(HoverTip)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('클리어 3명'), findsNothing, reason: '바로 뜨지는 않는다');
    await tester.pump(HoverTip.delay);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('클리어 3명'), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('클리어 3명'), findsNothing);
  });
}

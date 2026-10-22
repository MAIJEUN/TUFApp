import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/ui/widgets/slide_overflow.dart';

/// 목록에 수백 개가 놓이는 위젯이라 평소에는 가볍게 그리고,
/// 마우스를 올렸을 때만 끝까지 흘러갔다가 다시 돌아온다.
void main() {
  Future<void> pump(WidgetTester tester, {double width = 100}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 24,
              child: SlideOverflow(child: slidingText('아주 긴 제작자 이름 1KOSAHEDR4 | 1KOSAHEDR4')),
            ),
          ),
        ),
      ),
    );
  }

  RenderFadeEdges edges(WidgetTester tester) => tester.renderObject<RenderFadeEdges>(find.byType(FadeEdges));

  /// 마우스를 위젯 위로 올린다.
  Future<TestGesture> hover(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(SlideOverflow)));
    // 마우스가 들어왔는지는 프레임이 끝난 뒤에 확인되고, 흐르기 시작하는 건 그다음 프레임이다.
    await tester.pump();
    await tester.pump();
    return mouse;
  }

  testWidgets('글자는 세로로 잘리지 않게 그대로 두고 가로로만 처리한다', (tester) async {
    await pump(tester);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.overflow, TextOverflow.clip, reason: 'fade를 쓰면 세로로도 흐려진다');
    expect(text.softWrap, isFalse);
  });

  testWidgets('넘치는 만큼을 재고, 평소에는 움직이지 않는다', (tester) async {
    await pump(tester);
    expect(edges(tester).overflow, greaterThan(0));
    expect(edges(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('마우스를 올리면 끝까지 가서 마우스를 치울 때까지 멈춰 있다', (tester) async {
    await pump(tester);
    final distance = edges(tester).overflow;
    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(edges(tester).offset, greaterThan(0), reason: '바로 움직이기 시작한다');

    await tester.pump(const Duration(seconds: 8));
    expect(edges(tester).offset, distance, reason: '끝까지 간다');

    await tester.pump(const Duration(seconds: 8));
    expect(edges(tester).offset, distance, reason: '마우스가 그대로면 돌아오지 않는다');
    expect(tester.hasRunningAnimations, isFalse, reason: '멈춰 있는 동안은 프레임을 그리지 않는다');

    await mouse.moveTo(const Offset(700, 700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(edges(tester).offset, 0, reason: '치우면 돌아온다');
  });

  testWidgets('다른 변화가 없어도 마우스를 올리면 바로 움직인다', (tester) async {
    await pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(SlideOverflow)));
    // 마우스만 옮기고 프레임을 따로 요청하지 않는다.
    expect(tester.binding.hasScheduledFrame, isTrue, reason: '움직이기 시작하면 스스로 프레임을 요청한다');
    // 첫 프레임은 시작 시각만 정한다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(edges(tester).offset, greaterThan(0));
    await mouse.moveTo(const Offset(700, 700));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('마우스를 치우면 제자리로 돌아온다', (tester) async {
    await pump(tester);
    final mouse = await hover(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(edges(tester).offset, greaterThan(0));

    await mouse.moveTo(const Offset(500, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(edges(tester).offset, 0);
  });

  testWidgets('다 들어가면 흐르지 않는다', (tester) async {
    await pump(tester, width: 600);
    expect(edges(tester).overflow, 0);

    final mouse = await hover(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(edges(tester).offset, 0);
    await mouse.moveTo(const Offset(700, 700));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('따로 레이어를 쓰는 자식(나타나는 중인 아이콘 등)이 있어도 가장자리를 지울 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 80,
              height: 24,
              child: SlideOverflow(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 10; i++)
                      // 반투명하게 나타나는 중인 아이콘처럼 자기 레이어를 가진다.
                      RepaintBoundary(
                        child: Opacity(opacity: 0.5, child: Container(width: 20, height: 20, color: Colors.red)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull, reason: '가만히 있을 때 (오른쪽만 지움)');

    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(edges(tester).offset, greaterThan(0));
    expect(tester.takeException(), isNull, reason: '흐르는 중 (양쪽을 지움)');
    await mouse.moveTo(const Offset(700, 700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Row처럼 폭을 좁히면 터지는 자식도 담을 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 80,
              height: 24,
              child: SlideOverflow(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (var i = 0; i < 10; i++) const SizedBox(width: 20, height: 20)],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: '가로로 넘쳐도 오류가 나면 안 된다');
    expect(edges(tester).overflow, 120, reason: '20 * 10 - 80');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/ui/widgets/motion.dart';

/// No animation may be left behind when animate turns false mid-appearance and the widget is removed right away.
/// (Library rows have animate true only on the first build and false afterwards.)
void main() {
  Widget page({required bool show, required bool animate}) => MaterialApp(
    home: Scaffold(
      body: show ? Appear(key: const ValueKey('row'), animate: animate, child: const Text('row')) : const SizedBox(),
    ),
  );

  testWidgets('나타나는 중에 animate가 꺼지고 사라져도 오류가 없다', (tester) async {
    await tester.pumpWidget(page(show: true, animate: true));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(page(show: true, animate: false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('row'), findsOneWidget);

    await tester.pumpWidget(page(show: false, animate: false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('처음부터 animate가 꺼져 있으면 바로 보인다', (tester) async {
    await tester.pumpWidget(page(show: true, animate: false));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('row'), findsOneWidget);
  });
}

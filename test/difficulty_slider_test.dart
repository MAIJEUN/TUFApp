import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/models/difficulty.dart';
import 'package:tufapp/ui/widgets/difficulty_slider.dart';

void main() {
  // Width 600 with 24 padding on each side → x of difficulty i = 24 + 138 * i
  final difficulties = [for (var i = 0; i < 5; i++) Difficulty(id: i, name: 'P$i', color: '#808080')];

  Future<List<(int, int)>> pumpSlider(WidgetTester tester, {int lower = 0, int upper = 4}) async {
    final calls = <(int, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: DifficultySlider(
                difficulties: difficulties,
                lower: lower,
                upper: upper,
                onChanged: (lo, hi) => calls.add((lo, hi)),
              ),
            ),
          ),
        ),
      ),
    );
    return calls;
  }

  testWidgets('끄는 동안에는 알리지 않고, 놓을 때 한 번만 알린다', (tester) async {
    final calls = await pumpSlider(tester);

    final gesture = await tester.startGesture(const Offset(24, 46));
    await gesture.moveTo(const Offset(162, 46));
    await gesture.moveTo(const Offset(300, 46));
    await tester.pump();
    expect(calls, isEmpty);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, [(2, 4)]);
  });

  testWidgets('노브가 서로 넘어가면 놓을 때 순서를 바로잡는다', (tester) async {
    final calls = await pumpSlider(tester, lower: 1, upper: 2);

    final gesture = await tester.startGesture(const Offset(162, 46)); // knob 1
    await gesture.moveTo(const Offset(576, 46)); // to position 4
    await gesture.up();
    await tester.pumpAndSettle();

    expect(calls, [(2, 4)]);
  });

  testWidgets('제자리에서 눌렀다 떼면 알리지 않는다', (tester) async {
    final calls = await pumpSlider(tester);

    await tester.tapAt(const Offset(576, 46));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
  });
}

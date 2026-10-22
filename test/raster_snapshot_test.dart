import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/ui/widgets/raster_snapshot.dart';

void main() {
  testWidgets('스크롤만 하면 다시 굽지 않고, 안쪽이 바뀌면 다시 굽는다', (tester) async {
    final color = ValueNotifier(Colors.red);
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: [
            RasterSnapshot(
              child: ValueListenableBuilder(
                valueListenable: color,
                builder: (context, value, _) => Container(height: 40, color: value),
              ),
            ),
            for (var i = 0; i < 30; i++) SizedBox(height: 40, child: Text('row $i')),
          ],
        ),
      ),
    );
    final render = tester.renderObject<RenderRasterSnapshot>(find.byType(RasterSnapshot));
    expect(render.bakeCount, 1);

    controller.jumpTo(20);
    await tester.pump();
    controller.jumpTo(5);
    await tester.pump();
    expect(render.bakeCount, 1, reason: '자리만 바뀌면 구워 둔 그림을 그대로 쓴다');

    color.value = Colors.blue;
    await tester.pump();
    expect(render.bakeCount, 2, reason: '안쪽이 바뀌면 다시 굽는다');
  });

  testWidgets('안쪽 위젯은 그대로 누를 수 있다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RasterSnapshot(
            child: TextButton(onPressed: () => taps++, child: const Text('누르기')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('누르기'));
    expect(taps, 1);
  });

  testWidgets('안쪽에 따로 그려지는 투명도 애니메이션이 있으면 굽지 않는다 (옛 모습으로 굳지 않게)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: RasterSnapshot(
            child: AnimatedOpacity(
              opacity: 0.5,
              duration: Duration(milliseconds: 100),
              child: SizedBox(width: 20, height: 20, child: ColoredBox(color: Colors.red)),
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderRasterSnapshot>(find.byType(RasterSnapshot));
    expect(render.bakeCount, 0);
  });
}

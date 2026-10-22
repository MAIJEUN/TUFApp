import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/ui/widgets/side_by_side.dart';

/// Detail page columns: the video fills the right column and the left column stretches to its height.
void main() {
  const width = 700.0;
  Future<void> pump(WidgetTester tester, {required double leftHeight}) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: SideBySide(
            left: SizedBox(key: const Key('left'), height: leftHeight),
            right: (context, videoHeight) => SizedBox(key: const Key('video'), height: videoHeight),
          ),
        ),
      ),
    ),
  );

  testWidgets('영상이 칸을 꽉 채우고 두 칸의 끝이 맞는다', (tester) async {
    await pump(tester, leftHeight: 120);

    final left = tester.getRect(find.byKey(const Key('left')));
    final video = tester.getRect(find.byKey(const Key('video')));

    expect(video.width, moreOrLessEquals((width - 16) * 3 / 5, epsilon: 0.5), reason: '오른쪽 칸을 가로로 꽉 채운다');
    expect(video.width / video.height, moreOrLessEquals(16 / 9, epsilon: 0.01));
    expect(video.right, moreOrLessEquals(width, epsilon: 0.5), reason: '오른쪽 끝에 붙는다');
    expect(video.left, moreOrLessEquals(left.right + 16, epsilon: 0.5), reason: '사이는 간격만 띄운다');
    expect(left.top, moreOrLessEquals(video.top, epsilon: 0.5));
    expect(left.bottom, moreOrLessEquals(video.bottom, epsilon: 0.5), reason: '왼쪽 칸이 영상 높이에 맞춰 늘어난다');
  });

  testWidgets('왼쪽 글이 더 길면 두 칸이 같이 커진다', (tester) async {
    await pump(tester, leftHeight: 600);

    final left = tester.getRect(find.byKey(const Key('left')));
    final video = tester.getRect(find.byKey(const Key('video')));

    expect(left.height, 600);
    expect(video.height, moreOrLessEquals(600, epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });
}

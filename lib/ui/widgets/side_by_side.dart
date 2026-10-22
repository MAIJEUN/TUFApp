import 'package:flutter/material.dart';

/// 자세히 보기 화면의 두 칸: 왼쪽에 글, 오른쪽에 영상.
///
/// 사이트처럼 영상이 오른쪽 칸을 가로로 꽉 채우고(16:9), 왼쪽 칸은 그 높이에 맞춰 늘어난다.
/// 그래서 두 칸의 위아래 끝이 서로 딱 맞는다.
/// (왼쪽 글이 더 길면 두 칸이 같이 커진다.)
class SideBySide extends StatelessWidget {
  const SideBySide({
    super.key,
    required this.left,
    required this.right,
    this.gap = 16,
    this.leftFlex = 2,
    this.rightFlex = 3,
  });

  final Widget left;

  /// 오른쪽 칸을 만든다. [videoHeight]는 그 칸 폭에 16:9로 맞춘 영상 높이.
  final Widget Function(BuildContext context, double videoHeight) right;

  final double gap;
  final int leftFlex;
  final int rightFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rightWidth = (constraints.maxWidth - gap) * rightFlex / (leftFlex + rightFlex);
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: leftFlex, child: left),
            SizedBox(width: gap),
            Expanded(flex: rightFlex, child: right(context, rightWidth * 9 / 16)),
          ],
        ),
      );
    },
  );
}

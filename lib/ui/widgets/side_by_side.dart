import 'package:flutter/material.dart';

/// The two columns of detail pages: text on the left, video on the right.
///
/// Like the website, the video fills the right column's width (16:9) and the left column stretches to its height,
/// so both columns line up at the top and bottom.
/// (If the left text is taller, both grow together.)
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

  /// Builds the right column. [videoHeight] is the 16:9 video height for that column's width.
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

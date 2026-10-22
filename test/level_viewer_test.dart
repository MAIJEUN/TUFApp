import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/ui/pages/level_viewer_page.dart';
import 'package:tufapp/ui/widgets/level_card.dart';

/// Tapping a level card opens the details, which must render even when passes fail to load.
void main() {
  final level = Level.fromJson({
    'id': 11372,
    'song': 'QuomodocunquizE 『CROWN』',
    'artist': 'Camellia (かめりあ)',
    'creator': 'Asansis',
    'diffId': 65,
    'baseScore': 32000,
    'bpm': 320,
    'tilecount': 6305,
    'levelLengthInMs': 205000,
    'clears': 2,
    'likes': 39,
  });

  Future<AppController> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(child: LevelCard(level: level, compact: false)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('카드를 누르면 자세히 보기가 열린다', (tester) async {
    await pump(tester);
    expect(find.byType(LevelViewerPage), findsNothing);

    await tester.tap(find.text('QuomodocunquizE 『CROWN』'));
    await tester.pumpAndSettle();

    expect(find.byType(LevelViewerPage), findsOneWidget);
    expect(find.text('#11372'), findsWidgets);
    expect(find.text('리더보드'), findsOneWidget);
    // Pass summary rows (empty here because the test can't reach the server).
    expect(find.text('최초 클리어'), findsOneWidget);
    expect(find.text('최고 점수'), findsOneWidget);
    expect(find.text('총 클리어 수'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The card inside the details page doesn't open again.
    expect(tester.widget<LevelCard>(find.byType(LevelCard).last).openable, isFalse);
  });

  testWidgets('기록을 불러오지 못하면 다시 시도할 수 있다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('QuomodocunquizE 『CROWN』'));
    await tester.pumpAndSettle();

    expect(find.text('기록을 불러오지 못했어요'), findsOneWidget, reason: '테스트에서는 서버를 부를 수 없다');
    expect(find.text('다시 시도'), findsOneWidget);
  });
}

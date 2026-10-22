import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/l10n.dart';
import 'package:tufapp/core/models/difficulty.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/ui/theme.dart';
import 'package:tufapp/ui/widgets/level_card.dart';
import 'package:tufapp/ui/widgets/raster_snapshot.dart';

/// 카드 안의 줄 높이가 카드 높이를 넘으면 debug 빌드에서 오버플로 오류가 난다.
/// 실제 앱에서 보이는 크기(가로 1152, 카드 폭 약 1100)로 그려서 확인한다.
void main() {
  final level = Level(
    id: 11372,
    song: '777 (Camellia\'s "7,777cc" Remix) (Nerfed | Judgement Limit)',
    artist: 'RoughSketch & Camellia (かめりあ)',
    creator: 'PLORALD & 7 more | Bori & 5 more',
    difficulty: const Difficulty(id: 56, name: 'U16', color: '#191025'),
    baseScore: 32000,
    bpm: 486.06,
    tilecount: 6554,
    levelLengthInMs: 244000,
    dlLink: 'https://api.tuforums.com/cdn/abc',
    tags: [for (var i = 0; i < 10; i++) LevelTag(id: i, name: 'tag$i', color: '#FF0000')],
  );

  Future<void> pumpCard(WidgetTester tester, {required bool compact, double textScale = 1, Level? card}) async {
    // 실제 창 크기. 기본 테스트 화면(800x600)은 카드 한 줄이 들어가지 않는다.
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        controller: AppController(),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: MediaQuery(
              // 테스트 글꼴은 실제 글꼴보다 작다. 키워서 재어 봐야 여유가 있는지 알 수 있다.
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 1100,
                  child: LevelCard(level: card ?? level, compact: compact),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('자세히 보기에서 내용이 카드 높이를 넘지 않는다', (tester) async {
    await pumpCard(tester, compact: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('간략히 보기에서 내용이 카드 높이를 넘지 않는다', (tester) async {
    await pumpCard(tester, compact: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('글자가 커져도 넘치지 않는다', (tester) async {
    await pumpCard(tester, compact: false, textScale: 1.4);
    expect(tester.takeException(), isNull);
    await pumpCard(tester, compact: true, textScale: 1.4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('보기 방식을 바꾸는 중에도 넘치지 않는다', (tester) async {
    await pumpCard(tester, compact: false);
    await pumpCard(tester, compact: true);
    // 카드 높이가 줄어드는 애니메이션 중간
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('받은 횟수가 있어도 받기 단추는 카드 세로 가운데 같은 자리에 있다', (tester) async {
    Rect button() => tester.getRect(find.byType(FilledButton));
    Rect card() => tester.getRect(find.byType(LevelCard));

    await pumpCard(tester, compact: false);
    final without = button();
    expect(without.center.dy, closeTo(card().center.dy, 0.5), reason: '횟수가 없을 때 가운데');

    await pumpCard(
      tester,
      compact: false,
      card: Level(
        id: level.id,
        song: level.song,
        artist: level.artist,
        creator: level.creator,
        difficulty: level.difficulty,
        dlLink: level.dlLink,
        downloadCount: 1434,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(button(), without, reason: '횟수가 있어도 단추는 그대로');
    expect(tester.getRect(find.text('1,434')).top, greaterThanOrEqualTo(button().bottom), reason: '횟수는 단추 아래');
  });

  testWidgets('태그 줄은 한 장으로 구워진다 (안쪽에 따로 그려지는 것이 없다)', (tester) async {
    await pumpCard(
      tester,
      compact: false,
      card: Level(
        id: 1,
        song: 's',
        artist: 'a',
        creator: 'c',
        tags: [
          for (var i = 0; i < 6; i++)
            LevelTag(id: i, name: 'tag$i', color: '#FF0000', isCommunity: i.isEven, score: 0.5),
        ],
      ),
    );
    final snapshot = tester.renderObject<RenderRasterSnapshot>(find.byType(RasterSnapshot));
    expect(snapshot.bakeCount, greaterThan(0), reason: '굽지 못하고 그냥 그리면 스크롤이 무거워진다');
  });

  // 웹 levelcard.css: --arc-center 45deg, --rotation-offset: 90deg / count
  test('큐레이션 아이콘 각도는 웹과 같게 45도를 가운데로 90/개수씩 벌린다', () {
    expect(curationArcAngles(0), isEmpty);
    expect(curationArcAngles(1), [45]);
    expect(curationArcAngles(2), [22.5, 67.5]);
    expect(curationArcAngles(3), [15, 45, 75]);
    expect(curationArcAngles(4), [11.25, 33.75, 56.25, 78.75]);
  });
  testWidgets('영어로도 카드 높이를 넘지 않는다', (tester) async {
    appLanguage = AppLanguage.en;
    addTearDown(() => appLanguage = AppLanguage.ko);
    await pumpCard(tester, compact: false, textScale: 1.4);
    expect(tester.takeException(), isNull);
    expect(find.text('Download'), findsOneWidget);
    await pumpCard(tester, compact: true, textScale: 1.4);
    expect(tester.takeException(), isNull);
  });
}

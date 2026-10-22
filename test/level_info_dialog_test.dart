import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/ui/widgets/level_info_dialog.dart';

/// '전체 정보' 창: 레벨의 모든 값과 만든 사람들이 보여야 한다.
void main() {
  final level = Level.fromJson({
    'id': 263,
    'song': 'Camellia(かめりあ) 230+BPM 100ksub special mix [1hr]',
    'artist': 'かめりあ (Camellia)',
    'diffId': 56,
    'difficulty': {'id': 56, 'name': 'U16', 'baseScore': 13750},
    'bpm': 230,
    'tilecount': 35208,
    'levelLengthInMs': 3220000,
    'clears': 3,
    'uniqueClears': 2,
    'likes': 12,
    'createdAt': '2021-09-11T13:00:12.000Z',
    'team': 'Team Camellia',
    'aliases': [
      {'field': 'artist', 'alias': 'cametek'},
      {'field': 'artist', 'alias': 'かめりあ'},
    ],
    'tags': [
      {'id': 1, 'name': 'Chart'},
    ],
    'levelCredits': [
      {
        'role': 'charter',
        'sortOrder': 0,
        'creator': {'name': 'PLORALD', 'creatorAliases': []},
      },
      {
        'role': 'charter',
        'sortOrder': 1,
        'creator': {
          'name': 'Purple0702',
          'creatorAliases': [
            {'name': 'Twilight Skylines'},
          ],
        },
      },
      {
        'role': 'vfxer',
        'sortOrder': 0,
        'creator': {'name': 'Bori', 'creatorAliases': []},
      },
    ],
  });

  test('별칭과 제작자의 다른 이름을 읽는다', () {
    expect([for (final alias in level.aliases) '${alias.field}: ${alias.alias}'], ['artist: cametek', 'artist: かめりあ']);
    expect(level.createdAt?.toUtc().year, 2021);
    expect(level.credits.firstWhere((c) => c.creatorName == 'Purple0702').creatorAliases, ['Twilight Skylines']);
  });

  testWidgets('모든 정보와 만든 사람들이 보인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController();
    addTearDown(app.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: LevelInfoDialog(level: level)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 사이트와 같은 항목만 보여준다: 팀, 난이도, 기반 점수, 별칭, 만든 사람.
    expect(find.text('Team Camellia'), findsOneWidget);
    expect(find.text('U16'), findsOneWidget);
    expect(find.text('13,750 PP'), findsOneWidget, reason: '따로 정해진 점수가 없으면 난이도의 기본 점수');
    expect(find.text('artist: cametek, artist: かめりあ'), findsOneWidget, reason: '별칭');
    // 카드에 이미 있는 값은 다시 적지 않는다.
    for (final label in ['번호', '길이', '타일 수', 'BPM', '클리어', '좋아요', '태그']) {
      expect(find.text(label), findsNothing, reason: '$label 은(는) 빼고 보여준다');
    }
    // 채보와 이펙트를 나눠서 보여준다.
    expect(find.text('채보'), findsOneWidget);
    expect(find.text('이펙트'), findsOneWidget);
    expect(find.text('PLORALD'), findsOneWidget);
    expect(find.text('Purple0702 (Twilight Skylines)'), findsOneWidget);
    expect(find.text('Bori'), findsOneWidget);
  });
}

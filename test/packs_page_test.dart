import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/l10n.dart';
import 'package:tufapp/core/models/pack.dart';
import 'package:tufapp/ui/pages/packs_page.dart';

/// The pack list and pack contents render without errors, and folders expand and collapse.
void main() {
  Map<String, dynamic> level(int id, String song) => {
    'id': id,
    'song': song,
    'artist': 'Artist',
    'diffId': 16,
    'dlLink': 'https://cdn.tuforums.com/zips/$id',
  };

  final pack = LevelPack.fromJson({
    'id': 'abc',
    'name': 'AWC Original Levels',
    'levelCount': 3,
    'favoritesCount': 59,
    'isPinned': true,
    'packOwner': {'nickname': 'star4th'},
    'packItems': [
      {'referencedLevel': level(1, 'Valkyrius:0')},
      {'referencedLevel': level(2, 'Oyasmy')},
    ],
  });

  final detail = LevelPackDetail.fromJson({
    'id': 'abc',
    'name': 'AWC Original Levels',
    'levelCount': 3,
    'items': [
      {
        'id': 1,
        'type': 'folder',
        'name': 'AWC 2023',
        'sortOrder': 0,
        'children': [
          {'id': 10, 'type': 'level', 'sortOrder': 0, 'referencedLevel': level(1, 'Valkyrius:0')},
          {'id': 11, 'type': 'level', 'sortOrder': 1, 'referencedLevel': level(2, 'Oyasmy')},
        ],
      },
      {'id': 20, 'type': 'level', 'sortOrder': 1, 'referencedLevel': level(3, 'Hopeful Restart')},
    ],
  });

  Future<AppController> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController();
    addTearDown(app.dispose);
    app.packs
      ..packs = [pack]
      ..total = 1
      ..hasSearched = true;
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: PacksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('목록 카드에 이름, 개수, 미리보기가 보인다', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('AWC Original Levels'), findsOneWidget);
    expect(find.text('레벨 3개'), findsOneWidget);
    expect(find.text('Oyasmy'), findsOneWidget);
    expect(find.text('+1개 더'), findsOneWidget);
  });

  testWidgets('이름이 길어도 카드 높이를 넘지 않는다', (tester) async {
    final app = await pump(tester);
    app.packs.packs = [
      LevelPack.fromJson({
        'id': 'long',
        'name': 'Practice charts from TUF Resource with a very very long name that wraps',
        'levelCount': 14,
        'packOwner': {'nickname': 'TEO_72'},
        'packItems': [
          {'referencedLevel': level(1, 'Power Trip')},
          {'referencedLevel': level(2, 'Mad Piano Party II')},
          {'referencedLevel': level(3, 'ALL MY FELLAS')},
        ],
      }),
    ];
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          // Must not overflow with a larger text scale.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.15)),
            child: child!,
          ),
          home: const Scaffold(body: PacksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('+11개 더'), findsOneWidget, reason: '제목 미리보기 3개를 뺀 나머지 전부');
  });

  testWidgets('그 팩을 받는 동안 카드 위 막대가 진행률을 보여준다', (tester) async {
    final app = await pump(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing, reason: '받지 않을 때는 강조 줄');

    final items = [for (final entry in detail.allLevels) (level: entry.level, folder: 'AWC')];
    final job = PackDownload(scope: 'abc', label: 'AWC', items: items, packId: 'abc');
    job.finishedIds.add(items.first.level.id);
    app.packs.download = job;
    // Make the pack list rebuild (as when a download starts). Expanding and collapsing doesn't search again.
    app.packs.toggleFolder(-1);
    await tester.pump(const Duration(milliseconds: 300));

    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(1 / 3, 0.01), reason: '3개 중 1개');

    // This card is unaffected while another pack downloads.
    app.packs.download = PackDownload(scope: 'x', label: 'x', items: items, packId: 'other');
    app.packs.toggleFolder(-1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  test('진행률은 지금 받는 레벨의 진행까지 더한다', () {
    final items = [for (final entry in detail.allLevels) (level: entry.level, folder: '')];
    final job = PackDownload(scope: 'abc', label: 'AWC', items: items)
      ..finishedIds.add(items[0].level.id)
      ..currentLevelId = items[1].level.id;
    expect(job.progress(0.5), closeTo(1.5 / 3, 1e-9));
    expect(job.progress(0), closeTo(1 / 3, 1e-9));
  });

  testWidgets('팩 내용: 폴더를 펼치고 접는다', (tester) async {
    final app = await pump(tester);
    app.packs
      ..openedPack = detail.pack
      ..detail = detail
      ..expanded.add(1);
    app.packs.setAllExpanded(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('AWC 2023'), findsOneWidget);
    expect(find.text('Valkyrius:0'), findsOneWidget);
    expect(find.text('Hopeful Restart'), findsOneWidget);
    expect(find.textContaining('팩 받기'), findsOneWidget);

    await tester.tap(find.text('AWC 2023'));
    await tester.pumpAndSettle();
    expect(find.text('Valkyrius:0'), findsNothing, reason: '접으면 안의 레벨이 사라진다');
    expect(find.text('Hopeful Restart'), findsOneWidget);

    app.packs.close();
    await tester.pumpAndSettle();
    expect(find.text('+1개 더'), findsOneWidget, reason: '목록으로 돌아온다');
  });

  testWidgets('영어로도 목록 카드와 팩 내용이 넘치지 않는다', (tester) async {
    appLanguage = AppLanguage.en;
    addTearDown(() => appLanguage = AppLanguage.ko);
    final app = await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('3 levels'), findsOneWidget);
    expect(find.text('+1 more'), findsOneWidget);

    app.packs
      ..openedPack = detail.pack
      ..detail = detail;
    app.packs.setAllExpanded(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Download pack'), findsOneWidget);
    expect(find.text('Collapse all'), findsOneWidget);
  });
}

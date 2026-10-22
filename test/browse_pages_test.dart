import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/l10n.dart';
import 'package:tufapp/core/models/browse.dart';
import 'package:tufapp/core/models/difficulty.dart';
import 'package:tufapp/core/models/facet.dart';
import 'package:tufapp/core/models/profile.dart';
import 'package:tufapp/core/models/search_models.dart';
import 'package:tufapp/core/tuf_api_client.dart';
import 'package:tufapp/ui/pages/clears_page.dart';
import 'package:tufapp/ui/pages/creators_page.dart';
import 'package:tufapp/ui/pages/leaderboard_page.dart';

/// Renders the passes, leaderboard and creators pages against a fake server returning real responses (2026-10).
void main() {
  String fixture(String name) => File('test/fixtures/$name.json').readAsStringSync();

  late List<Uri> requested;

  /// The last request to [path] (ignoring others like video thumbnails).
  Uri last(String path) => requested.lastWhere((uri) => uri.path == path);
  Iterable<Uri> to(String path) => requested.where((uri) => uri.path == path);

  Future<AppController> pump(WidgetTester tester, Widget page, {Size size = const Size(1280, 900)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    requested = [];
    final client = MockClient((request) async {
      requested.add(request.url);
      final body = switch (request.url.path) {
        '/v3/players/leaderboard' => fixture('leaderboard'),
        '/v3/creators/leaderboard' => fixture('creators'),
        '/v2/database/passes' => fixture('clears'),
        '/v2/database/passes/byId/66795' => jsonEncode({
          'count': 1,
          'results': [(jsonDecode(fixture('clears'))['results'] as List).first],
        }),
        _ => null,
      };
      return body == null
          ? http.Response('{}', 404)
          : http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json'});
    });
    final app = AppController(api: TufApiClient(client: client));
    addTearDown(app.dispose);
    app.levels.catalog = DifficultyCatalog(
      (jsonDecode(fixture('difficulties')) as List).cast<Map<String, dynamic>>().map(Difficulty.fromJson),
    );
    app.levels.curationCatalog = FacetCatalog(
      (jsonDecode(fixture('curation_types')) as List).cast<Map<String, dynamic>>().map(FacetItem.fromJson).toList(),
    );

    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: page),
        ),
      ),
    );
    await settle(tester);
    return app;
  }

  group('제작자', () {
    testWidgets('순위, 이름, 인증 상태, 레벨 수를 보여준다', (tester) async {
      final app = await pump(tester, const CreatorsPage());
      app.creators.ensureLoaded();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('제작자 2,493명'), findsOneWidget);
      expect(find.text('Nephrolepis'), findsOneWidget);
      expect(find.textContaining('@nephrolepis'), findsOneWidget);
      expect(find.text('허가'), findsWidgets, reason: '인증 상태');
      expect(find.text('310'), findsOneWidget, reason: '정렬 기준(총 레벨) 칸');
      expect(find.text('3,835'), findsOneWidget, reason: '모든 레벨 클리어 수');
      expect(find.text('#1'), findsNothing, reason: '제작자 목록에는 순위가 없다 (웹과 같다)');
      final query = to('/v3/creators/leaderboard').first.queryParameters;
      expect(query['sortBy'], 'chartsTotal');
      expect(query['order'], 'desc');
    });

    testWidgets('인증 상태와 큐레이션 유형으로 거른다', (tester) async {
      final app = await pump(tester, const CreatorsPage());
      app.creators.ensureLoaded();
      await settle(tester);

      app.creators.setVerification(CreatorVerification.pending);
      app.creators.toggleCuration(17);
      await settle(tester);
      final query = last('/v3/creators/leaderboard').queryParameters;
      expect(jsonDecode(query['filters']!), {'verificationStatus': 'pending'});
      expect(jsonDecode(query['facetQuery']!)['curationTypes']['ids'], [17]);
      expect(app.creators.activeFilterCount, 2);

      app.creators.resetFilters();
      await settle(tester);
      expect(last('/v3/creators/leaderboard').queryParameters.containsKey('filters'), isFalse);
      expect(last('/v3/creators/leaderboard').queryParameters.containsKey('facetQuery'), isFalse);
    });

    testWidgets('필터를 열어도 좁은 창에서 넘치지 않는다', (tester) async {
      final app = await pump(tester, const CreatorsPage(), size: const Size(900, 900));
      app.creators.ensureLoaded();
      app.creators.toggleFilterOpen();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('큐레이션 유형'), findsOneWidget);
    });

    test('이름으로 정렬하면 레벨 수를 강조하고, 나머지 둘을 함께 보여준다', () {
      expect(CreatorRow.primaryFor(CreatorSort.name), CreatorSort.chartsTotal);
      expect(CreatorRow.secondaryFor(CreatorSort.chartsTotal), [
        CreatorSort.totalChartClears,
        CreatorSort.totalChartLikes,
      ]);
      expect(CreatorRow.secondaryFor(CreatorSort.totalChartClears), [CreatorSort.totalChartLikes]);
    });
  });

  group('리더보드', () {
    testWidgets('순위, 이름, 랭크 점수를 보여준다', (tester) async {
      final app = await pump(tester, const LeaderboardPage());
      app.leaderboard.ensureLoaded();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('플레이어 3,505명'), findsOneWidget);
      expect(find.text('Jipper'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('460,778.52'), findsOneWidget, reason: '정렬 기준(랭크 점수) 칸');
      expect(find.text('Kekman301'), findsOneWidget);
      expect(
        to('/v3/players/leaderboard').first.queryParameters,
        containsPair('flagMode', 'hide'),
        reason: '정지된 플레이어는 뺀다',
      );
    });

    testWidgets('정렬을 바꾸면 그 기준으로 다시 받는다', (tester) async {
      final app = await pump(tester, const LeaderboardPage());
      app.leaderboard.ensureLoaded();
      await settle(tester);

      app.leaderboard.setSort(LeaderboardSort.topDiff);
      await settle(tester);
      expect(last('/v3/players/leaderboard').queryParameters['sortBy'], 'topDiff');
      expect(find.text('최고 난이도'), findsWidgets);
      expect(find.text('U16'), findsWidgets, reason: '난이도 기준은 이름으로');

      app.leaderboard.toggleOrder();
      await settle(tester);
      expect(last('/v3/players/leaderboard').queryParameters['order'], 'asc');
    });

    testWidgets('좁은 창에서도 넘치지 않는다', (tester) async {
      final app = await pump(tester, const LeaderboardPage(), size: const Size(900, 700));
      app.leaderboard.ensureLoaded();
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('클리어', () {
    testWidgets('곡, 플레이어, 점수를 보여주고 PGU 범위로 묻는다', (tester) async {
      final app = await pump(tester, const ClearsPage());
      app.clears.ensureLoaded();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('클리어 61,143개'), findsOneWidget);
      expect(find.text('sirack'), findsOneWidget);
      expect(find.text('FallenEra'), findsOneWidget);
      expect(find.text('97.30'), findsOneWidget);

      // The first batch (the screen isn't full, so the next batch is requested too).
      final query = to('/v2/database/passes').first.queryParameters;
      expect(query['sort'], 'RECENT_DESC');
      expect(query['minDiff'], 'P1');
      expect(query['maxDiff'], 'U20');
      expect(query['deletedFilter'], 'hide');
    });

    testWidgets('필터를 바꾸면 그 조건으로 다시 받는다', (tester) async {
      final app = await pump(tester, const ClearsPage());
      app.clears.ensureLoaded();
      await settle(tester);

      app.clears.setKeyCount(KeyCountFilter.k12);
      app.clears.toggleSpecial('Unranked');
      app.clears.toggleSpecial('Censored');
      await settle(tester);
      final uri = last('/v2/database/passes');
      expect(uri.queryParameters['keyFlag'], '12k');
      expect(uri.queryParametersAll['specialDifficulties'], ['Unranked', 'Censored']);
      expect(app.clears.activeFilterCount, 2);

      app.clears.resetFilters();
      await settle(tester);
      expect(last('/v2/database/passes').queryParameters['keyFlag'], 'all');
      expect(last('/v2/database/passes').queryParametersAll['specialDifficulties'], isNull);
    });

    testWidgets('"#번호"로 기록 하나를 찾는다', (tester) async {
      final app = await pump(tester, const ClearsPage());
      app.clears.ensureLoaded();
      await settle(tester);

      app.clears.setQuery('#66795');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(to('/v2/database/passes/byId/66795'), hasLength(1));
      expect(find.text('클리어 1개'), findsOneWidget);
      expect(find.text('sirack'), findsOneWidget);
    });

    testWidgets('필터를 열어도 좁은 창에서 넘치지 않는다', (tester) async {
      final app = await pump(tester, const ClearsPage(), size: const Size(900, 900));
      app.clears.ensureLoaded();
      app.clears.toggleFilterOpen();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('게임 버전'), findsOneWidget);
    });
  });

  test('세 칸 중 정렬 기준이 아닌 둘을 함께 보여준다', () {
    expect(LeaderboardRow.secondaryFor(LeaderboardSort.rankedScore), [
      LeaderboardSort.totalScoreV2,
      LeaderboardSort.averageXacc,
    ]);
    expect(LeaderboardRow.secondaryFor(LeaderboardSort.wfScore), [
      LeaderboardSort.rankedScore,
      LeaderboardSort.averageXacc,
    ]);
    expect(LeaderboardRow.formatValue(LeaderboardSort.totalPasses, 252), '252');
  });

  group('영어', () {
    setUp(() => appLanguage = AppLanguage.en);
    tearDown(() => appLanguage = AppLanguage.ko);

    for (final width in [900.0, 1280.0]) {
      testWidgets('세 화면이 영어로 보이고, 필터를 열어도 넘치지 않는다 (폭 $width)', (tester) async {
        var app = await pump(tester, const ClearsPage(), size: Size(width, 900));
        app.clears.ensureLoaded();
        app.clears.toggleFilterOpen();
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Passes'), findsOneWidget);
        expect(find.text('Key count'), findsWidgets);

        app = await pump(tester, const LeaderboardPage(), size: Size(width, 900));
        app.leaderboard.ensureLoaded();
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Leaderboard'), findsOneWidget);
        expect(find.text('Ranked Score'), findsWidgets);

        app = await pump(tester, const CreatorsPage(), size: Size(width, 900));
        app.creators.ensureLoaded();
        app.creators.toggleFilterOpen();
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Verification status'), findsOneWidget);
        expect(find.text('Allowed'), findsWidgets);
      });
    }
  });
}

/// Fake responses arrive immediately, but wait for images and animations to finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

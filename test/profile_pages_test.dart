import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/l10n.dart';
import 'package:tufapp/core/models/difficulty.dart';
import 'package:tufapp/core/models/facet.dart';
import 'package:tufapp/core/models/search_models.dart';
import 'package:tufapp/core/tuf_api_client.dart';
import 'package:tufapp/ui/pages/profile/creator_profile_page.dart';
import 'package:tufapp/ui/pages/profile/player_profile_page.dart';

/// 실제 응답(2026-10)을 돌려주는 가짜 서버로 플레이어·제작자 페이지를 그린다.
void main() {
  String fixture(String name) => File('test/fixtures/$name.json').readAsStringSync();

  /// 요청한 주소에 맞는 응답. 없는 것은 404.
  final routes = <String, String Function()>{
    '/v3/players/25/profile': () => fixture('player_25_profile'),
    '/v3/players/25/passes': () => fixture('player_25_passes'),
    '/v3/players/25/rank-history': () => fixture('player_25_rank_history'),
    '/v3/creators/180/profile': () => fixture('creator_180_profile'),
    '/v2/database/levels': () => jsonEncode({'results': [], 'total': 0, 'hasMore': false}),
  };

  Future<AppController> pump(WidgetTester tester, Widget page, {Size size = const Size(1280, 900)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.path);
      final body = routes[request.url.path];
      return body == null
          ? http.Response('{}', 404)
          : http.Response.bytes(utf8.encode(body()), 200, headers: {'content-type': 'application/json'});
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
        child: MaterialApp(theme: ThemeData.dark(), home: page),
      ),
    );
    // 응답은 가짜라 바로 오지만, 그림·애니메이션이 끝날 때까지 기다린다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return app;
  }

  /// 페이지는 보이는 만큼만 그리므로, [finder]가 나올 때까지 아래로 끈다.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final page = find.byType(Scrollable).first;
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await tester.drag(page, const Offset(0, -250));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  testWidgets('플레이어 페이지: 머리글과 사이트 기본 순서의 모듈', (tester) async {
    await tester.runAsync(() async {});
    await pump(tester, const PlayerProfilePage(playerId: 25));

    final error = tester.takeException();
    if (error is FlutterError) debugPrint(error.toStringDeep());
    expect(error, isNull, reason: "넘치거나 깨지지 않는다");
    expect(find.text('Jipper'), findsWidgets);
    expect(find.textContaining('@jipper1214'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget, reason: '순위 (금색)');
    expect(find.textContaining('ID 25'), findsOneWidget);
    expect(find.textContaining('팔로워 171명'), findsOneWidget);
    expect(find.text('460,778.52'), findsWidgets, reason: '랭크 점수');

    // 모듈: 소개는 비어 있어서 빠진다.
    for (final title in ['토너먼트', '점수 상세', '난이도별 클리어', '순위 변화', '점수']) {
      await scrollTo(tester, find.text(title));
    }
    expect(find.text('내 소개'), findsNothing);

    // 기록 목록은 페이지 맨 아래에 이어 붙는다. 랭크에 보탠 점수가 초록 칸으로.
    await scrollTo(tester, find.text('326개 클리어'));
    await scrollTo(tester, find.text('QuomodocunquizE 『CROWN』'));
    expect(find.text('+67,016.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 창에서도 넘치지 않는다', (tester) async {
    await pump(tester, const PlayerProfilePage(playerId: 25), size: const Size(900, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('제작자 페이지: 인증 상태, 큐레이션 아이콘, 레벨 모듈', (tester) async {
    await pump(tester, const CreatorProfilePage(creatorId: 180));

    expect(tester.takeException(), isNull);
    expect(find.text('Jipper'), findsWidgets);
    expect(find.text('대기 중'), findsOneWidget, reason: '인증 상태');
    expect(find.textContaining('ID 180'), findsOneWidget);
    expect(find.text('모든 레벨'), findsOneWidget);
    await scrollTo(tester, find.text('난이도별 레벨'));
    await scrollTo(tester, find.text('레벨'));
    expect(find.text('#1'), findsNothing, reason: '제작자에게는 순위 칸이 없다');
  });

  testWidgets('없는 플레이어는 다시 시도할 수 있다', (tester) async {
    await pump(tester, const PlayerProfilePage(playerId: 999999));
    expect(find.text('페이지를 열지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
  group('영어', () {
    setUp(() => appLanguage = AppLanguage.en);
    tearDown(() => appLanguage = AppLanguage.ko);

    for (final width in [900.0, 1280.0]) {
      testWidgets('플레이어 페이지가 영어로 보이고 넘치지 않는다 (폭 $width)', (tester) async {
        await pump(tester, const PlayerProfilePage(playerId: 25), size: Size(width, 900));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('171 followers'), findsOneWidget);
        for (final title in ['Tournaments', 'Score breakdown', 'Clears by difficulty', 'Rank over time', 'Scores']) {
          await scrollTo(tester, find.text(title));
          expect(tester.takeException(), isNull, reason: title);
        }
        await scrollTo(tester, find.text('326 passes'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('제작자 페이지가 영어로 보이고 넘치지 않는다 (폭 $width)', (tester) async {
        await pump(tester, const CreatorProfilePage(creatorId: 180), size: Size(width, 900));
        expect(tester.takeException(), isNull);
        expect(find.text('Pending'), findsOneWidget);
        await scrollTo(tester, find.text('Levels by difficulty'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

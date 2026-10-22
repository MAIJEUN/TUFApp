import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/l10n.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/core/models/pass.dart';
import 'package:tufapp/core/tuf_api_client.dart';
import 'package:tufapp/ui/pages/pass_viewer_page.dart';

/// Pass page: score, judgements and flags must be shown.
void main() {
  final level = Level.fromJson({
    'id': 11372,
    'song': 'QuomodocunquizE 『CROWN』',
    'artist': 'Camellia (かめりあ)',
    'diffId': 65,
  });

  final pass = LevelPass.fromJson({
    'id': 44528,
    'playerId': 25,
    'scoreV2': 67016,
    'accuracy': 0.9883255813953488,
    'speed': 1,
    'feelingRating': 'U16',
    'vidUploadTime': '2026-05-05T09:03:05.000Z',
    'isWorldsFirst': true,
    'is16K': true,
    'isAdofaiV2': true,
    'player': {'name': 'Jipper', 'country': 'KR'},
    'judgements': {
      'earlyDouble': 9,
      'earlySingle': 36,
      'ePerfect': 40,
      'perfect': 6275,
      'lPerfect': 50,
      'lateSingle': 40,
      'lateDouble': 0,
    },
  });

  testWidgets('점수, 판정, 표시가 보인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController();
    addTearDown(app.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: PassViewerPage(level: level, pass: pass),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Jipper의 클리어'), findsOneWidget);
    expect(find.text('67,016.00'), findsOneWidget);
    expect(find.text('98.83%'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    // There is a feeling rating; without an expected rating that row is left out entirely.
    expect(find.text('U16'), findsOneWidget);
    expect(find.text('체감 난이도'), findsOneWidget);
    expect(find.text('예상 난이도'), findsNothing);
    expect(find.text('없음'), findsNothing);
    // Judgements: same values in the same places as the website.
    expect(find.text('6,275'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    // Flags.
    expect(find.text('WF'), findsOneWidget);
    expect(find.text('16키'), findsOneWidget);
    expect(find.text('v2'), findsOneWidget);
    // The video title is shown inside the player, so it isn't repeated.
    expect(find.text('세계 최초 클리어'), findsNothing);
  });

  testWidgets('3.4.0 X-Perfect 기록은 판정 아홉 칸과 새 표시를 보여준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController();
    addTearDown(app.dispose);

    // Real pass #66676 (level #650).
    final xPerfect = LevelPass.fromJson({
      'id': 66676,
      'playerId': 7,
      'scoreV2': 1234.5,
      'accuracy': 0.9888383378829239,
      'adofaiVersion': 3,
      'isXPerfectMode': true,
      'keyCount': 8,
      'isWorldsFirstPP': true,
      'submissionSource': 'auto_submission',
      'player': {'name': 'someone', 'country': 'KR'},
      'judgements': {
        'earlyDouble': 5,
        'earlySingle': 17,
        'ePerfect': 12,
        'perfectMinus': 121,
        'perfect': 2919,
        'perfectPlus': 167,
        'lPerfect': 40,
        'lateSingle': 16,
        'lateDouble': 0,
      },
    });

    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: PassViewerPage(level: level, pass: xPerfect),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '칸이 늘어나도 넘치지 않는다');
    for (final label in ['정확−', '정확', '정확+']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('121'), findsOneWidget);
    expect(find.text('2,919'), findsOneWidget);
    expect(find.text('167'), findsOneWidget);
    // The center Perfect is white (distinct from the green Perfect−/Perfect+).
    final perfect = tester.widget<Text>(find.text('2,919'));
    expect(perfect.style?.color, const Color(0xFFFFFFFF));
    // New flags (same names as the website).
    for (final flag in ['WF PP', '자동 제출', '8키', 'X-Perfect']) {
      expect(find.text(flag), findsOneWidget, reason: flag);
    }
    expect(find.text('<3.4.0'), findsNothing, reason: '3.4.0 이후 기록');
    expect(find.text('v2'), findsNothing);
  });

  testWidgets('점수와 플레이어를 모두 받지 못하면 불러오는 중에 머물지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController(api: TufApiClient(client: MockClient((_) async => http.Response('{}', 500))));
    addTearDown(app.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: PassViewerPage(level: level, pass: pass),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('점수 불러오는 중...'), findsNothing);
    expect(find.text('점수를 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('영어로 보인다', (tester) async {
    appLanguage = AppLanguage.en;
    addTearDown(() => appLanguage = AppLanguage.ko);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController();
    addTearDown(app.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: PassViewerPage(level: level, pass: pass),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Jipper's pass"), findsOneWidget);
    expect(find.text('Feeling rating'), findsOneWidget);
    expect(find.text('Judgements'), findsOneWidget);
    expect(find.text('16K'), findsOneWidget);
  });
}

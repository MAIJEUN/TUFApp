import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/models/pass.dart';
import 'package:tufapp/ui/widgets/common.dart';

/// 리더보드에 쓰는 기록 읽기와 요약.
void main() {
  Map<String, dynamic> pass(
    int id,
    String player,
    double score, {
    double accuracy = 0.9,
    double speed = 1,
    String? date,
  }) => {
    'id': id,
    'scoreV2': score,
    'accuracy': accuracy,
    'speed': speed,
    'vidUploadTime': date,
    'playerId': 25,
    'vidTitle': '세계 최초 클리어',
    'isAdofaiV2': true,
    'isWorldsFirst': id == 1,
    'is16K': true,
    'player': {'name': player, 'country': 'KR', 'pfp': null},
    'judgements': {
      'earlyDouble': 9,
      'earlySingle': 36,
      'ePerfect': 40,
      'perfect': 6275,
      'lPerfect': 50,
      'lateSingle': 40,
      'lateDouble': 0,
    },
  };

  test('기록 하나를 읽는다', () {
    final result = LevelPass.fromJson(pass(1, 'Jipper', 67016, accuracy: 0.9883, date: '2026-05-05T09:03:05.000Z'));

    expect(result.playerName, 'Jipper');
    expect(result.country, 'KR');
    expect(result.score, 67016);
    expect(result.isWorldsFirst, isTrue);
    expect(result.is16K, isTrue);
    expect(result.clearedAt?.toUtc().year, 2026);
    expect(
      [for (final (_, v) in result.judgements!.ordered(xPerfect: false)) v],
      [9, 36, 40, 6275, 50, 40, 0],
      reason: '이른 판정부터 늦은 판정 순서',
    );
    expect(result.playerId, 25);
    expect(result.videoTitle, '세계 최초 클리어');
    expect(result.era, AdofaiEra.v2, reason: '버전 번호가 없는 예전 기록은 isAdofaiV2로 정한다');
    expect(result.showsXPerfect, isFalse);
    expect(result.keyCountLabel, '16키');
    expect(result.expectedRating, isNull);
  });

  // 실제 기록 (#650, 2026-10): 3.4.0의 X-Perfect 판정으로 낸 8키 기록.
  final xPerfectJson = {
    'id': 66676,
    'scoreV2': 1234.5,
    'accuracy': 0.9888383378829239,
    'playerId': 7,
    'adofaiVersion': 3,
    'isAdofaiV2': false,
    'isXPerfectMode': true,
    'keyCount': 8,
    'is16K': false,
    'submissionSource': 'video',
    'isWorldsFirstPP': true,
    'player': {
      'name': 'someone',
      'pfp': 'https://cdn.discordapp.com/avatars/1/a.png',
      'user': {'avatarUrl': 'https://api.tuforums.com/cdn/images/profile/abc/original', 'avatarIsGif': false},
    },
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
  };

  test('3.4.0의 X-Perfect 판정을 읽는다', () {
    final result = LevelPass.fromJson(xPerfectJson);

    expect(result.era, AdofaiEra.latest);
    expect(result.showsXPerfect, isTrue);
    expect(
      [for (final (judgement, value) in result.judgements!.ordered(xPerfect: true)) '${judgement.label} $value'],
      ['너무 빠름 5', '빠름! 17', '빠름 12', '정확− 121', '정확 2919', '정확+ 167', '느림 40', '느림! 16', '너무 느림 0'],
    );
    expect(result.keyCountLabel, '8키', reason: '키 수가 있으면 12K/16K 대신 그 수를 쓴다');
    expect(result.isWorldsFirstPP, isTrue);
    expect(result.isAutoSubmitted, isFalse);
    expect(result.isPureXPerfect, isFalse);
    // 사이트처럼 TUF에 올린 사진을 먼저 쓰고, 디스코드 사진은 대신 쓸 주소로 둔다. 작게 보여서 중간 크기를 받는다.
    expect(result.playerAvatar, 'https://api.tuforums.com/cdn/images/profile/abc/medium');
    expect(result.playerAvatarFallback, 'https://cdn.discordapp.com/avatars/1/a.png');
  });

  test('X-Perfect가 아니어도 정확−/정확+ 값이 있으면 보여준다', () {
    final result = LevelPass.fromJson({...xPerfectJson, 'isXPerfectMode': false});
    expect(result.showsXPerfect, isTrue);
  });

  test('퓨어 X-퍼펙트와 퓨어 퍼펙트를 가른다', () {
    final pureX = LevelPass.fromJson({
      ...xPerfectJson,
      'accuracy': 1,
      'judgements': {'perfect': 500},
    });
    expect(pureX.isPureXPerfect, isTrue);
    expect(pureX.isPurePerfect, isFalse);

    // 실제 기록 #66712: 정확도 100%지만 정확−/정확+가 섞여 있다.
    final pure = LevelPass.fromJson({
      ...xPerfectJson,
      'accuracy': 1,
      'judgements': {'perfectMinus': 25, 'perfect': 536, 'perfectPlus': 18},
    });
    expect(pure.isPureXPerfect, isFalse);
    expect(pure.isPurePerfect, isTrue);
  });

  test('움직이는 프로필 사진은 후원 중일 때만 쓴다', () {
    final player = {
      'name': 'a',
      'user': {'avatarUrl': 'https://api.tuforums.com/cdn/images/profile/x/original_animated', 'avatarIsGif': true},
    };
    expect(
      AvatarUrls.of(player).primary,
      'https://api.tuforums.com/cdn/images/profile/x/original_static',
      reason: '크기를 바꾸는 규칙은 사이트와 같아서 _animated가 붙은 주소는 크기를 그대로 둔다',
    );

    final supporter = {
      'name': 'b',
      'user': {
        'avatarUrl': 'https://api.tuforums.com/cdn/images/profile/x/original_animated',
        'avatarIsGif': true,
        'tufStellarSubscriptionExpiresAt': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
      },
    };
    expect(AvatarUrls.of(supporter).primary, 'https://api.tuforums.com/cdn/images/profile/x/original_animated');
  });

  test('최초 클리어와 최고 기록을 뽑고, 리더보드는 사람마다 가장 좋은 기록만 남긴다', () {
    final summary = LevelPassSummary.of([
      for (final json in [
        pass(1, 'Jipper', 67016, accuracy: 0.9883, date: '2026-05-05T00:00:00.000Z'),
        pass(2, 'xnGD', 49822, accuracy: 0.9795, speed: 1.5, date: '2026-06-10T00:00:00.000Z'),
        pass(3, 'xnGD', 52000, accuracy: 0.97, date: '2026-07-01T00:00:00.000Z'),
      ])
        LevelPass.fromJson(json),
    ]);

    expect(summary.firstClear?.playerName, 'Jipper');
    expect(summary.bestScore?.score, 67016);
    expect(summary.bestSpeed?.speed, 1.5);
    expect(summary.bestAccuracy?.playerName, 'Jipper');
    expect(summary.totalClears, 3);
    expect(summary.uniquePlayers, 2);
    expect(
      [for (final p in summary.leaderboard) (p.playerName, p.score)],
      [('Jipper', 67016.0), ('xnGD', 52000.0)],
      reason: '점수 높은 순, xnGD는 더 좋은 기록만',
    );
  });

  test('기록을 낸 사람의 점수와 순위를 읽는다', () {
    final player = PlayerProfile.fromJson({
      'id': 25,
      'name': 'Jipper',
      'country': 'KR',
      'pfp': 'https://example.com/a.png',
      'stats': {
        'rankedScore': 458228.0488196168,
        'rankedScoreRank': 1,
        'averageXacc': 0.9963867672137254,
        'totalPasses': 246,
        'worldsFirstCount': 81,
        'topDiff': {'name': 'U16'},
      },
    });

    expect(player.name, 'Jipper');
    expect(formatScore(player.rankedScore), '458,228.05', reason: '웹에 보이는 값과 같게');
    expect(player.rank, 1);
    expect(player.topDifficulty, 'U16');
    expect(player.totalPasses, 246);
    expect(player.worldsFirstCount, 81);
  });

  test('기록이 없으면 빈 요약', () {
    final summary = LevelPassSummary.of([]);
    expect(summary.firstClear, isNull);
    expect(summary.totalClears, 0);
    expect(summary.leaderboard, isEmpty);
  });

  test('점수·정확도·속도·날짜 표시', () {
    expect(formatScore(67016), '67,016.00');
    expect(formatAccuracy(0.988325), '98.83%');
    expect(formatSpeed(1), '1');
    expect(formatSpeed(1.25), '1.25');
    expect(formatDate(DateTime(2026, 5, 5)), '2026년 5월 5일');
    expect(formatDate(null), '');
  });
}

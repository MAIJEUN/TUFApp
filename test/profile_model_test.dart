import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/models/profile.dart';

/// Reads player and creator page data from real responses (2026-10, Jipper).
void main() {
  Map<String, dynamic> fixture(String name) =>
      jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

  test('플레이어 페이지', () {
    final player = PlayerProfileDetail.fromJson(fixture('player_25_profile'));

    expect(player.name, 'Jipper');
    expect(player.handle, 'jipper1214');
    expect(player.country, 'KR');
    expect(player.rank, 1);
    expect(player.highestRank?.rank, 1);
    expect(player.followerCount, 171);
    expect(player.score(PlayerScoreKey.rankedScore), closeTo(460778.52, 0.01));
    expect(player.score(PlayerScoreKey.averageXacc), closeTo(0.997, 0.001));
    expect(player.creatorId, 180, reason: '같은 사람의 제작자 페이지');
    expect(player.topScores[44528], 67016, reason: '랭크 점수에 들어간 기록');
    expect(player.bio.isEmpty, isTrue);
    expect(player.banner.imageUrl, isNull, reason: '기본 배너');
    expect(player.placements, hasLength(8));
    expect(player.placements.first.tournamentName, 'ADOFAI World Championship 2024');
    expect(player.placements.first.seriesName, 'Adofai World Championship');
    // Without a saved layout, the website's default order.
    expect(
      [for (final module in player.modules.layoutFor(player: true)) module.type],
      ['bio', 'tournaments', 'scoreBreakdown', 'difficulty', 'rankHistory', 'scores'],
    );
    expect((player.funFacts['counts'] as Map)['totalPasses'], 326);
  });

  test('제작자 페이지', () {
    final creator = CreatorProfileDetail.fromJson(fixture('creator_180_profile'));

    expect(creator.name, 'Jipper');
    expect(creator.handle, 'jipper1214');
    expect(creator.verification, CreatorVerification.pending);
    expect(creator.chartsTotal, 10);
    expect(creator.totalChartClears, 96);
    expect(creator.curationTypeCounts, {16: 3, 17: 1, 20: 2, 21: 1});
    expect(creator.playerId, 25, reason: '같은 사람의 플레이어 페이지');
    expect(creator.followerCount, 11);
    expect(
      [for (final module in creator.modules.layoutFor(player: false)) module.type],
      ['bio', 'tournaments', 'difficulty', 'charts'],
    );
  });

  test('기록 목록과 순위 변화', () {
    final passes = fixture('player_25_passes');
    final entries = (passes['passes'] as List).cast<Map<String, dynamic>>().map(PlayerPassEntry.fromJson).toList();
    expect(entries.first.pass.id, 44528);
    expect(entries.first.level.song, 'QuomodocunquizE 『CROWN』');
    expect(entries.first.level.diffId, 56);
    expect(entries.first.level.creatorDisplay, 'Asansis');

    final history = (fixture('player_25_rank_history')['series'] as List)
        .cast<Map<String, dynamic>>()
        .map(RankHistoryPoint.fromJson)
        .toList();
    expect(history.first.rankedRank, 15);
    expect(history.first.date, DateTime.utc(2022, 11, 30));
  });

  test('저장한 배치를 따르고, 기록 모듈은 빠져 있어도 붙인다', () {
    final modules = ProfileModules.fromJson({
      'profileModules': {
        'modules': [
          {'id': 'a', 'type': 'favorite'},
          {'id': 'b', 'type': 'bio'},
          {'id': 'c', 'type': 'bio'},
          {'id': 'd', 'type': 'charts'},
        ],
      },
    });
    expect([for (final m in modules.layoutFor(player: true)) m.type], ['favorite', 'bio', 'scores']);
    expect([for (final m in modules.layoutFor(player: false)) m.type], ['favorite', 'bio', 'charts']);
  });

  test('후원이 끝난 꾸민 소개는 글로 바뀐다', () {
    final json = {
      'bioCanvas': {
        'blocks': [
          {
            'id': '1',
            'type': 'text',
            'data': {'heading': '안녕', 'body': '반가워요'},
          },
          {
            'id': '2',
            'type': 'link',
            'data': {'label': '유튜브', 'url': 'https://youtube.com/@a'},
          },
          {'id': '3', 'type': 'image', 'data': {}},
        ],
      },
      'bioCanvasImageAssets': {
        '3': {'assetId': 'x', 'url': 'https://example.com/a.png'},
      },
    };
    expect(ProfileBio.fromJson(json, stellar: true).blocks, hasLength(3));
    expect(ProfileBio.fromJson(json, stellar: false).text, '안녕\n반가워요\n\n유튜브 (https://youtube.com/@a)');
  });
}

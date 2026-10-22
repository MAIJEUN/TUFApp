import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/models/difficulty.dart';
import 'package:tufapp/core/models/facet.dart';
import 'package:tufapp/core/models/profile.dart';
import 'package:tufapp/core/models/search_models.dart';
import 'package:tufapp/core/profile_stats.dart';

/// Values must match the website (Jipper's profile, 2026-10, checked on the website).
void main() {
  Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

  final catalog = DifficultyCatalog(
    (fixture('difficulties') as List).cast<Map<String, dynamic>>().map(Difficulty.fromJson),
  );
  final curations = FacetCatalog(
    (fixture('curation_types') as List).cast<Map<String, dynamic>>().map(FacetItem.fromJson).toList(),
  );
  final player = PlayerProfileDetail.fromJson(fixture('player_25_profile') as Map<String, dynamic>);
  final creator = CreatorProfileDetail.fromJson(fixture('creator_180_profile') as Map<String, dynamic>);

  test('플레이어 머리글 아이콘: P20 · G20 · U16 · GQ4 · UQ3과 그 횟수', () {
    final slots = playerIconSlots(player, catalog);
    expect([for (final slot in slots) slot.letter], ['P', 'G', 'U', 'GQ', 'UQ']);
    expect([for (final slot in slots) slot.badge], [3, 11, 3, 5, 15], reason: '사이트 머리글의 작은 숫자');
    expect(slots.every((slot) => slot.iconUrl != null), isTrue);
  });

  test('제작자 머리글 아이콘: 큐레이션 유형 묶음마다 하나씩', () {
    final slots = creatorIconSlots(creator, curations);
    // 3 C0, 1 C1, 2 V0, 1 V1 → C1 and V1 first, then the rest.
    expect([for (final slot in slots) slot.letter], ['C1', 'V1', 'C0', 'V0']);
    expect([for (final slot in slots) slot.badge], [1, 1, 3, 2]);
  });

  test('통계 묶음', () {
    final groups = playerStatGroups(player, catalog);
    expect([for (final group in groups) group.label], ['점수', '클리어 수', '판정', '클리어한 레벨', '기록', '활동', '클리어한 난이도 수']);
    final scores = groups.first.rows;
    expect(scores.first.value, '460,778.52');
    expect(scores.last.value, '99.70%');
    final extremes = groups.firstWhere((group) => group.label == '기록').rows;
    expect(extremes.first.passId, 2858, reason: '첫 클리어로 가는 단추');

    expect(creatorStatGroups(creator, catalog), isNotEmpty);
  });

  test('난이도 그래프: PGU가 빈칸 없이 이어지고, 레벨 그래프는 특수 난이도도 넣는다', () {
    final bars = difficultyBars(
      player.funFacts['clearsByDifficultyNoDupes'] as Map<String, dynamic>,
      catalog,
      levels: false,
    );
    expect(bars.first.label, 'P1');
    expect(bars.last.label, 'U20');
    expect(bars.length, 60);

    final levelBars = difficultyBars(const {}, catalog, levels: true);
    expect(levelBars.first.label, '0', reason: 'Unranked가 맨 앞');
    expect(levelBars.map((bar) => bar.label), contains('∞'));
  });

  test('정확도는 100%에 가까우면 9를 이어서 보여준다', () {
    expect(formatAccuracyRatio(0.985196), '98.52%');
    expect(formatAccuracyRatio(0.999962), '99.996%', reason: '반올림하면 100.00%가 되므로 9를 이어서');
    expect(formatAccuracyRatio(0.9999962), '99.9996%');
    expect(formatAccuracyRatio(1), '100%');
    expect(formatPoints(2470828.2260211706), '2,470,828.23');
    expect(formatDurationMs(83983384.99), '23h 19m');
  });
}

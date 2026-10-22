import 'package:flutter/material.dart';

import '../../../app/controllers.dart';
import '../../../core/l10n.dart';
import '../../../core/models/profile.dart';
import '../../../core/profile_stats.dart';
import 'profile_header.dart';
import 'profile_list_view.dart';
import 'profile_lists.dart';
import 'profile_modules.dart';
import 'profile_navigation.dart';
import 'profile_page_frame.dart';

/// 플레이어 페이지 (사이트의 /profile/{id}). 머리글 아래에 사이트에서 정한 순서대로 모듈을 놓고,
/// 모든 기록은 레벨 찾기 목록처럼 맨 아래에 이어 붙인다.
class PlayerProfilePage extends StatelessWidget {
  const PlayerProfilePage({super.key, required this.playerId});

  final int playerId;

  @override
  Widget build(BuildContext context) => ProfilePageFrame<PlayerProfileDetail>(
    load: (context) => AppScope.of(context).api.getPlayerProfile(playerId),
    titleOf: (player) => player.name,
    emptyTitle: tr('기록이 없어요', 'No passes'),
    createList: (api, player) => PlayerPassList(api, player.id),
    listHeader: (context, player, list) => PlayerPassListHeader(list: list as PlayerPassList),
    itemBuilder: (context, player, list, index) {
      final passes = list as PlayerPassList;
      final entry = passes.items[index];
      final id = entry.pass.id;
      // 점수 높은 순으로 볼 때, 랭크 점수에 들어간 마지막 기록 아래에 경계를 긋는다.
      final cutoff =
          passes.sort == PlayerPassSort.score &&
          passes.descending &&
          passes.query.isEmpty &&
          passes.total > player.topScores.length &&
          id == _lowestTopScore(player);
      final card = ProfileScoreCard(
        entry: entry,
        impact: player.topScores[id],
        potentialImpact: player.potentialTopScores[id],
      );
      return cutoff
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                card,
                RankedCutoffNote(score: entry.pass.score),
              ],
            )
          : card;
    },
    builder: (context, player) {
      final app = AppScope.of(context);
      final catalog = app.levels.catalog;
      final facts = player.funFacts;
      final noDupes = facts['clearsByDifficultyNoDupes'] as Map<String, dynamic>?;
      final withDupes = facts['clearsByDifficulty'] as Map<String, dynamic>?;

      return [
        ProfileHeader(
          name: player.name,
          avatar: player.avatar,
          aliases: player.aliases,
          bannerUrl: player.banner.imageUrl,
          handle: player.handle,
          country: player.country,
          rank: player.rank,
          highestRank: player.highestRank,
          profileId: player.id,
          followerCount: player.showFollowerCount ? player.followerCount : null,
          iconSlots: playerIconSlots(player, catalog),
          iconPanelTitle: tr('깬 난이도', 'Difficulties cleared'),
          iconPanel: catalog == null
              ? null
              : (context) =>
                    DifficultyGridPanel(difficulties: catalog.all, clears: playerClearsByDifficulty(player, catalog)),
          stats: [
            StatRow(tr('랭크 점수', 'Ranked Score'), formatPoints(player.score(PlayerScoreKey.rankedScore))),
            StatRow(tr('평균 절대정확도', 'Average X-acc'), formatAccuracyRatio(player.score(PlayerScoreKey.averageXacc))),
            StatRow(tr('총 점수', 'Total Score'), formatPoints(player.score(PlayerScoreKey.totalScoreV2))),
          ],
          statGroups: playerStatGroups(player, catalog),
          onOpenPass: (passId) => ProfileNavigation.openPass(context, passId),
          actions: [
            for (final channel in player.youtubeChannels)
              ProfileAction(
                icon: Icons.smart_display_outlined,
                tooltip: 'YouTube: ${channel.label}',
                onPressed: () => app.openLink(channel.url),
              ),
            if (player.handle case final handle?)
              ProfileAction(
                icon: Icons.inventory_2_outlined,
                tooltip: tr('사용자 팩 보기', "View user's packs"),
                onPressed: () => ProfileNavigation.openPacksOf(context, handle),
              ),
            if (player.creatorId case final creatorId?)
              ProfileAction(
                icon: Icons.handyman_outlined,
                tooltip: tr('제작자 프로필 보기', 'View creator profile'),
                onPressed: () => ProfileNavigation.openCreator(context, creatorId),
              ),
          ],
        ),
        // 내용이 없는 모듈은 사이트처럼 보여주지 않는다. 기록 목록은 맨 아래에 따로 있다.
        for (final module in player.modules.layoutFor(player: true))
          ?switch (module.type) {
            'bio' when !player.bio.isEmpty => BioModule(title: tr('내 소개', 'Bio'), bio: player.bio),
            'tournaments' when TournamentsModule.visible(player.placements, player.placementOrderIds).isNotEmpty =>
              TournamentsModule(placements: player.placements, orderIds: player.placementOrderIds),
            'scoreBreakdown' => ScoreBreakdownModule(player: player),
            'difficulty' when (noDupes ?? withDupes)?.isNotEmpty ?? false => DifficultyModule(
              title: tr('난이도별 클리어', 'Clears by difficulty'),
              counts: noDupes ?? withDupes!,
              countsWithDupes: withDupes ?? noDupes!,
            ),
            'rankHistory' => RankHistoryModule(playerId: player.id),
            'favorite' when player.modules.favorites[module.id]?.isNotEmpty ?? false => FavoritesModule(
              items: player.modules.favorites[module.id]!,
            ),
            _ => null,
          },
      ];
    },
  );

  /// 랭크 점수에 들어간 기록 중 가장 적게 보탠 것.
  static int? _lowestTopScore(PlayerProfileDetail player) {
    MapEntry<int, double>? lowest;
    for (final entry in player.topScores.entries) {
      if (lowest == null || entry.value < lowest.value) lowest = entry;
    }
    return lowest?.key;
  }
}

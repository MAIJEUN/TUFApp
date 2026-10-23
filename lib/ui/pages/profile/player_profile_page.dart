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

/// Player page (the website's /profile/{id}). Modules follow the header in the website's order,
/// and all passes are appended at the bottom like the levels list.
class PlayerProfilePage extends StatelessWidget {
  const PlayerProfilePage({super.key, required this.playerId});

  final int playerId;

  @override
  Widget build(BuildContext context) => ProfilePageFrame<PlayerProfileDetail>(
    load: (context) => AppScope.of(context).api.getPlayerProfile(playerId),
    titleOf: (player) => player.name,
    emptyTitle: l10n.noPasses,
    createList: (api, player) => PlayerPassList(api, player.id),
    listHeader: (context, player, list) => PlayerPassListHeader(list: list as PlayerPassList),
    itemBuilder: (context, player, list, index) {
      final passes = list as PlayerPassList;
      final entry = passes.items[index];
      final id = entry.pass.id;
      // When sorted by score, draw a line below the last pass that counts toward the ranked score.
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
          iconPanelTitle: l10n.difficultiesCleared,
          iconPanel: catalog == null
              ? null
              : (context) =>
                    DifficultyGridPanel(difficulties: catalog.all, clears: playerClearsByDifficulty(player, catalog)),
          stats: [
            StatRow(l10n.rankedScore, formatPoints(player.score(PlayerScoreKey.rankedScore))),
            StatRow(l10n.averageXAcc, formatAccuracyRatio(player.score(PlayerScoreKey.averageXacc))),
            StatRow(l10n.totalScore, formatPoints(player.score(PlayerScoreKey.totalScoreV2))),
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
                tooltip: l10n.viewUsersPacks,
                onPressed: () => ProfileNavigation.openPacksOf(context, handle),
              ),
            if (player.creatorId case final creatorId?)
              ProfileAction(
                icon: Icons.handyman_outlined,
                tooltip: l10n.viewCreatorProfile,
                onPressed: () => ProfileNavigation.openCreator(context, creatorId),
              ),
          ],
        ),
        // Like the website, empty modules are hidden. The pass list sits separately at the bottom.
        for (final module in player.modules.layoutFor(player: true))
          ?switch (module.type) {
            'bio' when !player.bio.isEmpty => BioModule(title: l10n.playerBio, bio: player.bio),
            'tournaments' when TournamentsModule.visible(player.placements, player.placementOrderIds).isNotEmpty =>
              TournamentsModule(placements: player.placements, orderIds: player.placementOrderIds),
            'scoreBreakdown' => ScoreBreakdownModule(player: player),
            'difficulty' when (noDupes ?? withDupes)?.isNotEmpty ?? false => DifficultyModule(
              title: l10n.clearsByDifficulty,
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

  /// The smallest contribution among passes counted in the ranked score.
  static int? _lowestTopScore(PlayerProfileDetail player) {
    MapEntry<int, double>? lowest;
    for (final entry in player.topScores.entries) {
      if (lowest == null || entry.value < lowest.value) lowest = entry;
    }
    return lowest?.key;
  }
}

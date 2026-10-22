import 'package:flutter/material.dart';

import '../../../app/controllers.dart';
import '../../../core/l10n.dart';
import '../../../core/models/profile.dart';
import '../../../core/profile_stats.dart';
import '../../widgets/level_card.dart';
import 'profile_header.dart';
import 'profile_list_view.dart';
import 'profile_lists.dart';
import 'profile_modules.dart';
import 'profile_navigation.dart';
import 'profile_page_frame.dart';

/// Creator page (the website's /creator/{id}). The creator's levels are appended at the bottom like the levels page.
class CreatorProfilePage extends StatelessWidget {
  const CreatorProfilePage({super.key, required this.creatorId});

  final int creatorId;

  /// Color of a verification status.
  static Color verificationColor(CreatorVerification status) => switch (status) {
    CreatorVerification.allowed => const Color(0xFF6BD68A),
    CreatorVerification.conditional => const Color(0xFFFFB74D),
    CreatorVerification.pending => const Color(0xFFFFD54F),
    CreatorVerification.declined => const Color(0xFFFF8A80),
  };

  @override
  Widget build(BuildContext context) => ProfilePageFrame<CreatorProfileDetail>(
    load: (context) => AppScope.of(context).api.getCreatorProfile(creatorId),
    titleOf: (creator) => creator.name,
    emptyTitle: tr('레벨이 없어요', 'No levels'),
    createList: (api, creator) => CreatorLevelList(api, creator.id),
    listHeader: (context, creator, list) => CreatorLevelListHeader(list: list as CreatorLevelList),
    itemBuilder: (context, creator, list, index) =>
        LevelCard(level: (list as CreatorLevelList).items[index], compact: false),
    builder: (context, creator) {
      final app = AppScope.of(context);
      final catalog = app.levels.catalog;
      final curations = app.levels.curationCatalog;
      final slots = creatorIconSlots(creator, curations);
      final levelsByDifficulty = creator.funFacts['levelsByDifficulty'] as Map<String, dynamic>?;

      // Show the expand button only when some curation types don't fit in the header slots.
      final typedCount = creator.curationTypeCounts.values.where((count) => count > 0).length;

      return [
        ProfileHeader(
          name: creator.name,
          avatar: creator.avatar,
          aliases: creator.aliases,
          bannerUrl: creator.banner.imageUrl,
          handle: creator.handle,
          country: creator.country,
          profileId: creator.id,
          followerCount: creator.showFollowerCount ? creator.followerCount : null,
          badge: VerificationBadge(
            label: creator.verification.label,
            color: verificationColor(creator.verification),
            conditions: creator.uploadConditions,
          ),
          iconSlots: slots,
          iconPanelTitle: tr('큐레이션 유형', 'Curation types'),
          iconPanel: curations == null || typedCount <= slots.length
              ? null
              : (context) => CurationPanel(types: curations.all, counts: creator.curationTypeCounts),
          stats: [
            StatRow(tr('모든 레벨', 'Total levels'), formatCount(creator.chartsTotal)),
            StatRow(tr('큐레이션 레벨', 'Curated levels'), formatCount(creator.curatedLevels)),
            StatRow(tr('레벨 클리어 수', 'Total level clears'), formatCount(creator.totalChartClears)),
          ],
          statGroups: creatorStatGroups(creator, catalog),
          actions: [
            for (final channel in creator.youtubeChannels)
              ProfileAction(
                icon: Icons.smart_display_outlined,
                tooltip: 'YouTube: ${channel.label}',
                onPressed: () => app.openLink(channel.url),
              ),
            if (creator.playerId case final playerId?)
              ProfileAction(
                icon: Icons.sports_esports_outlined,
                tooltip: tr('플레이어 프로필 보기', 'View player profile'),
                onPressed: () => ProfileNavigation.openPlayer(context, playerId),
              ),
          ],
        ),
        for (final module in creator.modules.layoutFor(player: false))
          ?switch (module.type) {
            'bio' when !creator.bio.isEmpty => BioModule(title: tr('소개', 'Bio'), bio: creator.bio),
            'tournaments' when TournamentsModule.visible(creator.placements, creator.placementOrderIds).isNotEmpty =>
              TournamentsModule(placements: creator.placements, orderIds: creator.placementOrderIds),
            'difficulty' when levelsByDifficulty?.isNotEmpty ?? false => DifficultyModule(
              title: tr('난이도별 레벨', 'Levels by difficulty'),
              counts: levelsByDifficulty!,
            ),
            'favorite' when creator.modules.favorites[module.id]?.isNotEmpty ?? false => FavoritesModule(
              items: creator.modules.favorites[module.id]!,
            ),
            _ => null,
          },
      ];
    },
  );
}

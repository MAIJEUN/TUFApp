import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/browse.dart';
import '../../core/profile_stats.dart';
import '../widgets/common.dart';
import '../widgets/hover_tip.dart';
import '../widgets/motion.dart';
import '../widgets/slide_overflow.dart';
import 'browse_page.dart';
import 'profile/profile_header.dart';
import 'profile/profile_navigation.dart';

/// tr('리더보드', 'Leaderboard') 화면: 플레이어 순위 (웹의 리더보드).
class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final leaderboard = AppScope.of(context).leaderboard;
    return ListenableBuilder(
      listenable: leaderboard,
      builder: (context, _) => BrowsePage<LeaderboardPlayer>(
        list: leaderboard,
        title: tr('리더보드', 'Leaderboard'),
        subtitle: tr(
          '플레이어 순위를 점수, 클리어 수, 최고 난이도 등으로 보세요.',
          'See player rankings by score, passes, top difficulty, and more.',
        ),
        toolbar: _Toolbar(leaderboard: leaderboard),
        countText: (total) => tr('플레이어 ${formatNumber(total)}명', "${formatNumber(total)} ${plural(total, 'player')}"),
        itemKey: (player) => player.id,
        itemBuilder: (context, player, index) => LeaderboardRow(player: player, sort: leaderboard.sort),
        emptyTitle: tr('찾는 플레이어가 없어요', 'No players found'),
        endText: tr('모든 플레이어를 불러왔어요', 'All players loaded'),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.leaderboard});

  final LeaderboardController leaderboard;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: BrowseSearchBar(
          initialText: leaderboard.query,
          hint: tr('플레이어 이름으로 검색', 'Search by player name'),
          onChanged: leaderboard.setQuery,
        ),
      ),
      const SizedBox(width: 12),
      DropdownMenu<LeaderboardSort>(
        // 고른 항목의 글은 처음 만들 때만 채워지므로, 언어가 바뀌면 새로 만든다.
        key: ValueKey(appLanguage),
        initialSelection: leaderboard.sort,
        label: Text(tr('정렬', 'Sort')),
        width: 220,
        menuHeight: 420,
        onSelected: (value) {
          if (value != null) leaderboard.setSort(value);
        },
        dropdownMenuEntries: [
          for (final sort in LeaderboardSort.values) DropdownMenuEntry(value: sort, label: sort.label),
        ],
      ),
      const SizedBox(width: 8),
      OrderButton(descending: leaderboard.descending, onPressed: leaderboard.toggleOrder),
      const SizedBox(width: 8),
      IconButton(tooltip: tr('새로고침', 'Refresh'), onPressed: leaderboard.reload, icon: const Icon(Icons.refresh)),
    ],
  );
}

/// 순위 한 줄: 순위, 사진, 이름과 국가, 정렬 기준 값(강조)과 대표 값 둘, 최고 난이도.
/// 누르면 그 사람의 플레이어 페이지.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({super.key, required this.player, required this.sort});

  final LeaderboardPlayer player;
  final LeaderboardSort sort;

  /// 정렬 기준 옆에 함께 보여줄 값. 웹처럼 랭크 점수·평균 절대정확도·총 점수 중 둘.
  static List<LeaderboardSort> secondaryFor(LeaderboardSort sort) {
    final rest = [
      LeaderboardSort.rankedScore,
      LeaderboardSort.totalScoreV2,
      LeaderboardSort.averageXacc,
    ].where((key) => key != sort).toList();
    if (rest.length > 2) rest.remove(LeaderboardSort.totalScoreV2);
    return rest;
  }

  static String formatValue(LeaderboardSort sort, double value) {
    if (sort == LeaderboardSort.averageXacc) return formatAccuracyRatio(value);
    if (sort.isCount) return formatNumber(value.round());
    return formatPoints(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final rank = player.rank;
    final top = player.topDifficulty;

    return HoverCard(
      onTap: () => ProfileNavigation.openPlayer(context, player.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              rank > 0 ? '#${formatNumber(rank)}' : '-',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: medalColor(rank) ?? muted,
                fontWeight: rank <= 3 && rank > 0 ? FontWeight.w800 : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ProfileAvatar(avatar: player.avatar, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: SlideOverflow(child: slidingText(player.name, style: theme.textTheme.titleSmall)),
                    ),
                    if (player.country != null) ...[
                      const SizedBox(width: 6),
                      CountryFlag(country: player.country, height: 12),
                    ],
                  ],
                ),
                Text('ID ${player.id}', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 168,
            child: _Stat(player: player, sort: sort, emphasized: true),
          ),
          for (final key in secondaryFor(sort))
            SizedBox(
              width: 132,
              child: _Stat(player: player, sort: key),
            ),
          SizedBox(
            width: 48,
            child: top == null
                ? null
                : HoverTip(
                    message: tr('최고 난이도 ${top.name}', 'Top difficulty ${top.name}'),
                    child: Align(alignment: Alignment.centerRight, child: NetworkIcon(top.icon, size: 32)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 이름과 값 한 칸. 정렬 기준 칸은 클리어 화면의 순위 칩처럼 강조한다.
class _Stat extends StatelessWidget {
  const _Stat({required this.player, required this.sort, this.emphasized = false});

  final LeaderboardPlayer player;
  final LeaderboardSort sort;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final valueStyle = emphasized
        ? theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer)
        : theme.textTheme.bodyMedium;
    final difficulty = player.difficulty(sort);

    final Widget value = sort.isDifficulty
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (difficulty != null) ...[NetworkIcon(difficulty.icon, size: 20), const SizedBox(width: 6)],
              Text(difficulty?.name ?? '-', style: valueStyle),
            ],
          )
        : Text(LeaderboardRow.formatValue(sort, player.value(sort)), maxLines: 1, softWrap: false, style: valueStyle);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          sort.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: emphasized ? theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8) : muted,
          ),
        ),
        value,
      ],
    );

    if (!emphasized) return Padding(padding: const EdgeInsets.only(left: 12), child: content);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );
  }
}

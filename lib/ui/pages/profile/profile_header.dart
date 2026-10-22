import 'package:flutter/material.dart';

import '../../../core/image_cache_store.dart';
import '../../../core/l10n.dart';
import '../../../core/models/difficulty.dart';
import '../../../core/models/facet.dart';
import '../../../core/models/pass.dart';
import '../../../core/profile_stats.dart';
import '../../widgets/common.dart';
import '../../widgets/hover_tip.dart';
import '../../widgets/motion.dart';
import '../../widgets/slide_overflow.dart';
import '../../widgets/smooth_scroll.dart';
import 'profile_section.dart';

/// 플레이어·제작자 페이지 맨 위 카드. 클리어 화면의 사람 카드를 크게 한 모양이다.
/// 사진·이름·계정, 대표 아이콘(최고 난이도 / 큐레이션 유형), 순위, 통계 세 칸과 tr('전체 통계', 'All stats').
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    required this.avatar,
    this.aliases = const [],
    this.bannerUrl,
    this.handle,
    this.country,
    this.rank,
    this.highestRank,
    this.profileId,
    this.followerCount,
    this.badge,
    this.iconSlots = const [],
    this.iconPanelTitle,
    this.iconPanel,
    this.stats = const [],
    this.statGroups = const [],
    this.onOpenPass,
    this.actions = const [],
  });

  final String name;
  final AvatarUrls avatar;

  /// 예전 이름들. 이름에 마우스를 올리면 보인다.
  final List<String> aliases;

  /// 프로필 배너. 있으면 카드 뒤에 흐리게 깐다 (레벨 카드의 영상 썸네일처럼).
  final String? bannerUrl;
  final String? handle;
  final String? country;

  /// 플레이어 순위. null이면 순위 칸이 없다 (제작자).
  final int? rank;
  final ({int rank, DateTime date})? highestRank;
  final int? profileId;
  final int? followerCount;

  /// 이름 옆에 붙는 표시 (제작자 인증 상태).
  final Widget? badge;
  final List<IconSlot> iconSlots;

  /// 아이콘 줄 끝 단추로 여는 창 (모든 난이도 / 모든 큐레이션 유형).
  final String? iconPanelTitle;
  final WidgetBuilder? iconPanel;

  /// 카드 아래 칸에 보이는 대표 통계.
  final List<StatRow> stats;

  /// tr('전체 통계', 'All stats') 창의 내용.
  final List<StatGroup> statGroups;
  final void Function(int passId)? onOpenPass;

  /// 오른쪽 위 단추들 (다른 프로필, 팩 보기 등).
  final List<ProfileAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final rank = this.rank;
    final banner = bannerUrl;
    final panel = iconPanel;
    final subtitle = [
      if (handle case final h?) '@$h',
      if (followerCount case final count?)
        tr('팔로워 ${formatNumber(count)}명', "${formatNumber(count)} ${plural(count, 'follower')}"),
      if (profileId case final id?) 'ID $id',
    ].join('  ·  ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (banner != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: Image(
                  image: DiskCachedImage(banner, maxWidth: 192, blurSigma: 1.5),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileAvatar(avatar: avatar, size: 88),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: HoverTip(
                                  message: aliases.isEmpty
                                      ? ''
                                      : tr('다른 이름: ${aliases.join(', ')}', 'Also known as: ${aliases.join(', ')}'),
                                  child: SlideOverflow(child: slidingText(name, style: theme.textTheme.headlineSmall)),
                                ),
                              ),
                              if (country != null) ...[
                                const SizedBox(width: 10),
                                CountryFlag(country: country, height: 18),
                              ],
                              if (badge case final b?) ...[const SizedBox(width: 10), b],
                            ],
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                          ],
                          if (iconSlots.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                for (final slot in iconSlots) ...[IconSlotView(slot: slot), const SizedBox(width: 8)],
                                if (panel != null)
                                  IconButton(
                                    tooltip: iconPanelTitle ?? tr('모두 보기', 'Show all'),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => showDialog<void>(
                                      context: context,
                                      builder: (context) =>
                                          _PanelDialog(title: iconPanelTitle ?? '', child: panel(context)),
                                    ),
                                    icon: const Icon(Icons.grid_view_rounded),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (rank != null) _RankChip(rank: rank, highest: highestRank),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (index, action) in actions.indexed) ...[
                                if (index > 0) const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: action.tooltip,
                                  onPressed: action.onPressed,
                                  icon: Icon(action.icon),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (final stat in stats) ...[
                        Expanded(
                          child: ProfileTile(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(stat.label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                                const SizedBox(height: 2),
                                Text(stat.value, style: theme.textTheme.titleMedium),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (statGroups.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              ProfileStatsDialog.show(context, title: name, groups: statGroups, onOpenPass: onOpenPass),
                          icon: const Icon(Icons.query_stats),
                          label: Text(tr('전체 통계', 'All stats')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 머리글 오른쪽 위 단추 하나.
class ProfileAction {
  const ProfileAction({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
}

/// 순위 색: 1위 금, 2위 은, 3위 동. 그 밖에는 null (기본 글자색).
Color? medalColor(int rank) => switch (rank) {
  1 => const Color(0xFFF2D06B),
  2 => const Color(0xFFDADADA),
  3 => const Color(0xFFF4A259),
  _ => null,
};

/// "#1" 순위 칩 (클리어 화면의 순위 칩과 같은 모양). 1~3위는 메달 색, 마우스를 올리면 최고 순위.
class _RankChip extends StatelessWidget {
  const _RankChip({required this.rank, this.highest});

  final int rank;
  final ({int rank, DateTime date})? highest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = highest;
    final tip = best == null
        ? tr('랭크 점수 순위', 'Ranked score rank')
        : rank > 0 && rank <= best.rank
        ? tr('지금 최고 순위입니다!', 'At highest rank right now!')
        : tr(
            '최고 순위 #${best.rank} (${formatDate(best.date)})',
            'Highest rank: #${best.rank} (${formatDate(best.date)})',
          );
    return HoverTip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
        child: Text(
          rank > 0 ? '#${formatNumber(rank)}' : tr('순위 없음', 'Unranked'),
          style: theme.textTheme.titleLarge?.copyWith(
            color: medalColor(rank) ?? theme.colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 둥근 프로필 사진. TUF에 올린 사진이 안 열리면 디스코드 사진, 그것도 없으면 사람 모양.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.avatar, required this.size});

  final AvatarUrls avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = avatar.primary ?? avatar.fallback;
    final placeholder = Icon(Icons.person, size: size * 0.6, color: colors.onSurfaceVariant);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surfaceContainerHighest),
      child: url == null
          ? placeholder
          : Image(
              image: DiskCachedImage(url, maxWidth: (size * 2).ceil()),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => switch (avatar.fallback) {
                final fallback? when fallback != url => Image(
                  image: DiskCachedImage(fallback, maxWidth: (size * 2).ceil()),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => placeholder,
                ),
                _ => placeholder,
              },
            ),
    );
  }
}

/// 대표 아이콘 하나와 개수 (오른쪽 아래 작은 숫자).
class IconSlotView extends StatelessWidget {
  const IconSlotView({super.key, required this.slot, this.size = 40});

  final IconSlot slot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = slot.iconUrl;
    return HoverTip(
      message: slot.tooltip ?? '',
      child: SizedBox(
        width: size + 4,
        height: size + 4,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox.square(
              dimension: size,
              child: icon != null
                  ? NetworkIcon(icon, size: size)
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        slot.letter,
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${slot.badge}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 아이콘 줄의 단추로 여는 창.
class _PanelDialog extends StatelessWidget {
  const _PanelDialog({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: child,
    actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('닫기', 'Close')))],
  );
}

/// tr('전체 통계', 'All stats') 창. 레벨 화면의 '전체 정보' 창과 같은 모양이다.
class ProfileStatsDialog extends StatelessWidget {
  const ProfileStatsDialog({super.key, required this.title, required this.groups, this.onOpenPass});

  final String title;
  final List<StatGroup> groups;
  final void Function(int passId)? onOpenPass;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<StatGroup> groups,
    void Function(int passId)? onOpenPass,
  }) => showDialog(
    context: context,
    builder: (context) => ProfileStatsDialog(title: title, groups: groups, onOpenPass: onOpenPass),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('$title의 통계', "$title's stats"), style: theme.textTheme.headlineSmall)),
                  IconButton(
                    tooltip: tr('닫기', 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _DialogScroll(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 24.0;
                      final columns = (constraints.maxWidth / 240).floor().clamp(1, 3);
                      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: 20,
                        children: [
                          for (final group in groups)
                            SizedBox(
                              width: width,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(group.label, style: theme.textTheme.titleSmall),
                                  const SizedBox(height: 6),
                                  for (final row in group.rows)
                                    _StatLine(
                                      row: row,
                                      onOpenPass: onOpenPass,
                                      close: () => Navigator.of(context).pop(),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('닫기', 'Close'))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogScroll extends StatefulWidget {
  const _DialogScroll({required this.child});

  final Widget child;

  @override
  State<_DialogScroll> createState() => _DialogScrollState();
}

class _DialogScrollState extends State<_DialogScroll> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SmoothScrollbar(
    controller: _scroll,
    builder: (context, behavior) => ScrollConfiguration(
      behavior: behavior,
      // 오른쪽에 스크롤 막대 자리를 비워 둔다.
      child: SingleChildScrollView(controller: _scroll, padding: const EdgeInsets.only(right: 16), child: widget.child),
    ),
  );
}

/// "총 클리어 횟수   326" 한 줄. 기록이 있는 줄은 그 클리어로 가는 단추가 붙는다.
class _StatLine extends StatelessWidget {
  const _StatLine({required this.row, this.onOpenPass, required this.close});

  final StatRow row;
  final void Function(int passId)? onOpenPass;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passId = row.passId;
    final open = onOpenPass;
    final value = Text(row.value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          if (row.tooltip case final tip?) HoverTip(message: tip, child: value) else value,
          if (passId != null && open != null)
            IconButton(
              tooltip: tr('클리어 보기', 'View pass'),
              // 단추가 있는 줄도 다른 줄과 높이가 같게 작게 둔다.
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 22),
              iconSize: 16,
              onPressed: () {
                close();
                open(passId);
              },
              icon: const Icon(Icons.open_in_new),
            ),
        ],
      ),
    );
  }
}

/// 모든 난이도 아이콘, 깬 것만 밝게 (아이콘 줄의 단추로 연다).
class DifficultyGridPanel extends StatelessWidget {
  const DifficultyGridPanel({super.key, required this.difficulties, required this.clears});

  final List<Difficulty> difficulties;
  final Map<int, int> clears;

  @override
  Widget build(BuildContext context) {
    final pgu = [
      for (final d in difficulties)
        if (d.type == 'PGU' && d.name != 'Unranked') d,
    ];
    final special = [
      for (final d in difficulties)
        if (d.type == 'SPECIAL' && !const {'Unranked', 'Impossible', 'Qq'}.contains(d.name)) d,
    ];

    Widget grid(List<Difficulty> list) => Wrap(
      children: [
        for (final d in list)
          HoverTip(
            message: tr(
              '${d.name} · ${clears[d.id] ?? 0}회 클리어',
              "${d.name} · ${clears[d.id] ?? 0} ${plural(clears[d.id] ?? 0, 'clear')}",
            ),
            child: Opacity(
              opacity: (clears[d.id] ?? 0) > 0 ? 1 : 0.22,
              child: Padding(padding: const EdgeInsets.all(3), child: NetworkIcon(d.icon, size: 32)),
            ),
          ),
      ],
    );

    return SizedBox(
      width: 10 * 38,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          grid(pgu),
          if (special.isNotEmpty) ...[const Divider(height: 24), grid(special)],
        ],
      ),
    );
  }
}

/// 큐레이션 유형을 묶음별로, 레벨 수와 함께 (제작자 아이콘 줄의 단추로 연다).
class CurationPanel extends StatelessWidget {
  const CurationPanel({super.key, required this.types, required this.counts});

  final List<FacetItem> types;
  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<FacetItem>>{};
    for (final type in types) {
      if ((counts[type.id] ?? 0) <= 0) continue;
      groups.putIfAbsent(type.group ?? tr('기타', 'Other'), () => []).add(type);
    }
    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in groups.entries) ...[
            Text(entry.key, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in entry.value)
                  Chip(avatar: NetworkIcon(type.icon, size: 20), label: Text('${type.name}  ${counts[type.id]}')),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// 제작자 인증 상태 칩 (허가 · 조건 있음 · 대기 중 · 거절). 조건이 있으면 마우스를 올려 볼 수 있다.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.label, required this.color, this.conditions});

  final String label;
  final Color color;
  final String? conditions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = conditions;
    return HoverTip(
      message: text == null || text.isEmpty
          ? tr('레벨 등록 허가 상태', 'Level upload permission')
          : tr('등록 조건: $text', 'Upload conditions: $text'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
            if (text != null && text.isNotEmpty) Icon(Icons.info_outline, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

/// 버튼처럼 쓰는 작은 진행 표시 (데이터를 받는 동안).
class ProfileLoading extends StatelessWidget {
  const ProfileLoading({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(child: CircularProgressIndicator()),
  );
}

/// 접히는 묶음 줄 (토너먼트 시리즈·대회): 꺾쇠, 제목, 개수.
class ProfileGroupRow extends StatelessWidget {
  const ProfileGroupRow({
    super.key,
    required this.title,
    required this.count,
    required this.open,
    required this.onTap,
    this.trailing,
    this.leading,
  });

  final String title;
  final int count;
  final bool open;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: Motion.medium,
            curve: Motion.curve,
            child: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          if (leading case final l?) ...[l, const SizedBox(width: 10)],
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          ),
          ?trailing,
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

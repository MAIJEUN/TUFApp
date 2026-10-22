import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/browse.dart';
import '../../core/models/facet.dart';
import '../../core/models/profile.dart';
import '../../core/profile_stats.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/slide_overflow.dart';
import 'browse_page.dart';
import 'profile/creator_profile_page.dart';
import 'profile/profile_header.dart';
import 'profile/profile_navigation.dart';

/// tr('제작자', 'Creators') 화면: 레벨을 만든 사람들의 목록 (웹의 /creators).
class CreatorsPage extends StatelessWidget {
  const CreatorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final creators = app.creators;
    return ListenableBuilder(
      listenable: Listenable.merge([creators, app.levels]),
      builder: (context, _) => BrowsePage<CreatorListEntry>(
        list: creators,
        title: tr('제작자', 'Creators'),
        subtitle: tr(
          '레벨을 만든 사람들을 레벨 수, 클리어 수, 큐레이션으로 찾아보세요.',
          'Find the people who make levels by level count, clears, and curations.',
        ),
        toolbar: _Toolbar(creators: creators),
        filter: Reveal(
          visible: creators.filterOpen,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _FilterCard(creators: creators, curations: app.levels.curationCatalog),
          ),
        ),
        countText: (total) => tr('제작자 ${formatNumber(total)}명', "${formatNumber(total)} ${plural(total, 'creator')}"),
        itemKey: (creator) => creator.id,
        itemBuilder: (context, creator, index) => CreatorRow(creator: creator, sort: creators.sort),
        emptyTitle: tr('찾는 제작자가 없어요', 'No creators found'),
        endText: tr('모든 제작자를 불러왔어요', 'All creators loaded'),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.creators});

  final CreatorsController creators;

  @override
  Widget build(BuildContext context) {
    final filterCount = creators.activeFilterCount;
    const filterIcon = Icon(Icons.tune);
    return Row(
      children: [
        Expanded(
          child: BrowseSearchBar(
            initialText: creators.query,
            hint: tr('제작자 이름으로 검색 (@계정으로도)', 'Search by creator name (or @account)'),
            onChanged: creators.setQuery,
          ),
        ),
        const SizedBox(width: 12),
        DropdownMenu<CreatorSort>(
          // 고른 항목의 글은 처음 만들 때만 채워지므로, 언어가 바뀌면 새로 만든다.
          key: ValueKey(appLanguage),
          initialSelection: creators.sort,
          label: Text(tr('정렬', 'Sort')),
          width: 220,
          onSelected: (value) {
            if (value != null) creators.setSort(value);
          },
          dropdownMenuEntries: [
            for (final sort in CreatorSort.values) DropdownMenuEntry(value: sort, label: sort.label),
          ],
        ),
        const SizedBox(width: 8),
        OrderButton(descending: creators.descending, onPressed: creators.toggleOrder),
        const SizedBox(width: 8),
        Badge(
          isLabelVisible: filterCount > 0,
          label: Text('$filterCount'),
          child: FadeSwitcher(
            duration: Motion.fast,
            child: creators.filterOpen
                ? FilledButton.tonalIcon(
                    key: const ValueKey('open'),
                    onPressed: creators.toggleFilterOpen,
                    icon: filterIcon,
                    label: Text(tr('필터', 'Filter')),
                  )
                : OutlinedButton.icon(
                    key: const ValueKey('closed'),
                    onPressed: creators.toggleFilterOpen,
                    icon: filterIcon,
                    label: Text(tr('필터', 'Filter')),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 인증 상태와 큐레이션 유형으로 거르기.
class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.creators, required this.curations});

  final CreatorsController creators;
  final FacetCatalog? curations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final groups = <String, List<FacetItem>>{};
    for (final type in curations?.all ?? const <FacetItem>[]) {
      groups.putIfAbsent(type.group ?? tr('기타', 'Other'), () => []).add(type);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('인증 상태', 'Verification status'), style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<CreatorVerification?>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: null, label: Text(tr('모든 상태', 'All statuses'))),
                for (final status in CreatorVerification.values)
                  ButtonSegment(value: status, label: Text(status.label)),
              ],
              selected: {creators.verification},
              onSelectionChanged: (selection) => creators.setVerification(selection.first),
            ),
            if (groups.isNotEmpty) ...[
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('큐레이션 유형', 'Curation types'), style: theme.textTheme.labelLarge),
                        Text(
                          tr('고른 유형의 레벨이 있는 제작자만 보여줍니다.', 'Only shows creators with levels of the chosen types.'),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: false, label: Text(tr('하나라도', 'Any'))),
                      ButtonSegment(value: true, label: Text(tr('모두', 'All'))),
                    ],
                    selected: {creators.curationsMatchAll},
                    onSelectionChanged: (selection) => creators.setCurationsMatchAll(selection.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final entry in groups.entries) ...[
                Text(entry.key, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in entry.value)
                      FilterChip(
                        avatar: NetworkIcon(type.icon, size: 18),
                        label: Text(type.name),
                        selected: creators.curationTypeIds.contains(type.id),
                        onSelected: (_) => creators.toggleCuration(type.id),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: creators.resetFilters,
                icon: const Icon(Icons.refresh),
                label: Text(tr('모두 초기화', 'Reset all')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 제작자 한 줄 (웹의 CreatorCard): 사진, 이름과 인증 상태, 계정, 대표 큐레이션 아이콘,
/// 정렬 기준 값(강조)과 클리어 수·좋아요 수. 누르면 제작자 페이지.
class CreatorRow extends StatelessWidget {
  const CreatorRow({super.key, required this.creator, required this.sort});

  final CreatorListEntry creator;
  final CreatorSort sort;

  /// 대표 큐레이션 아이콘 자리. 개수가 달라도 오른쪽 칸들이 줄마다 같은 자리에 오게 폭을 정해 둔다.
  static const _slotSize = 28.0;
  static const _maxSlots = 5;
  static const _slotsWidth = _maxSlots * (_slotSize + 4) + (_maxSlots - 1) * 6;

  /// 카드 안쪽 폭이 이보다 좁으면 큐레이션 아이콘을 뺀다 (이름 칸이 200 남짓은 남게).
  static const _slotsMinWidth = 960.0;

  /// 이름 정렬이면 이름은 이미 보이므로 레벨 수를 강조한다 (웹과 같다).
  static CreatorSort primaryFor(CreatorSort sort) => sort == CreatorSort.name ? CreatorSort.chartsTotal : sort;

  /// 강조 칸 옆에 함께 보여줄 값. 웹처럼 클리어 수와 좋아요 수 중 강조 칸이 아닌 것.
  static List<CreatorSort> secondaryFor(CreatorSort sort) =>
      [CreatorSort.totalChartClears, CreatorSort.totalChartLikes].where((key) => key != primaryFor(sort)).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final slots = curationIconSlots(
      creator.curationTypeCounts,
      creator.displayCurationTypeIds,
      AppScope.of(context).levels.curationCatalog,
    ).take(_maxSlots).toList();
    final handle = creator.handle;

    return HoverCard(
      onTap: () => ProfileNavigation.openCreator(context, creator.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      // 좁은 창에서는 이름 칸이 너무 좁아지지 않게 큐레이션 아이콘을 뺀다.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSlots = constraints.maxWidth >= _slotsMinWidth;
          return Row(
            children: [
              ProfileAvatar(avatar: creator.avatar, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: SlideOverflow(child: slidingText(creator.name, style: theme.textTheme.titleSmall)),
                        ),
                        const SizedBox(width: 8),
                        VerificationBadge(
                          label: creator.verification.label,
                          color: CreatorProfilePage.verificationColor(creator.verification),
                        ),
                      ],
                    ),
                    Text(
                      [
                        handle == null ? tr('연동된 계정 없음', 'No linked account') : '@$handle',
                        'ID ${creator.id}',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              if (showSlots) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: _slotsWidth,
                  child: Row(
                    spacing: 6,
                    children: [for (final slot in slots) IconSlotView(slot: slot, size: _slotSize)],
                  ),
                ),
              ],
              const SizedBox(width: 12),
              SizedBox(
                width: 168,
                child: _Stat(creator: creator, sort: primaryFor(sort), emphasized: true),
              ),
              for (final key in secondaryFor(sort))
                SizedBox(
                  width: 132,
                  child: _Stat(creator: creator, sort: key),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 이름과 값 한 칸 (리더보드와 같은 모양). 강조 칸은 순위 칩처럼 칠한다.
class _Stat extends StatelessWidget {
  const _Stat({required this.creator, required this.sort, this.emphasized = false});

  final CreatorListEntry creator;
  final CreatorSort sort;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
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
        Text(
          formatNumber(creator.count(sort)),
          maxLines: 1,
          softWrap: false,
          style: emphasized
              ? theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer)
              : theme.textTheme.bodyMedium,
        ),
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

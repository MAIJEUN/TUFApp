import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/browse.dart';
import '../../core/models/pass.dart';
import '../../core/models/profile.dart';
import '../../core/models/search_models.dart';
import '../widgets/common.dart';
import '../widgets/difficulty_slider.dart';
import '../widgets/hover_tip.dart';
import '../widgets/motion.dart';
import '../widgets/pass_row.dart';
import '../widgets/slide_overflow.dart';
import 'browse_page.dart';
import 'profile/profile_header.dart';
import 'profile/profile_navigation.dart';

/// Passes page: every pass on TUF (the website's pass list).
class ClearsPage extends StatelessWidget {
  const ClearsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final clears = app.clears;
    return ListenableBuilder(
      listenable: Listenable.merge([clears, app.levels]),
      builder: (context, _) {
        final catalog = app.levels.catalog;
        return BrowsePage<PlayerPassEntry>(
          list: clears,
          title: tr('클리어', 'Passes'),
          subtitle: tr('모든 플레이어의 클리어 기록을 둘러보세요.', 'Browse passes from every player.'),
          toolbar: _Toolbar(clears: clears),
          filter: catalog == null
              ? null
              : Reveal(
                  visible: clears.filterOpen,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _FilterCard(clears: clears, catalog: catalog),
                  ),
                ),
          countText: (total) =>
              tr('클리어 ${formatNumber(total)}개', "${formatNumber(total)} ${plural(total, 'pass', 'passes')}"),
          itemKey: (entry) => entry.pass.id,
          itemBuilder: (context, entry, index) => ClearRow(entry: entry),
          emptyTitle: tr('찾는 클리어 기록이 없어요', 'No passes found'),
          endText: tr('모든 클리어 기록을 불러왔어요', 'All passes loaded'),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.clears});

  final ClearsController clears;

  @override
  Widget build(BuildContext context) {
    final filterCount = clears.activeFilterCount;
    const filterIcon = Icon(Icons.tune);
    return Row(
      children: [
        Expanded(
          child: BrowseSearchBar(
            initialText: clears.query,
            hint: tr('곡 이름, 플레이어로 검색 (#번호로 기록 찾기)', 'Search by song or player (#id to find a pass)'),
            onChanged: clears.setQuery,
          ),
        ),
        const SizedBox(width: 12),
        DropdownMenu<ClearSort>(
          // The selected label is only filled in on creation, so recreate the menu when the language changes.
          key: ValueKey(appLanguage),
          initialSelection: clears.sort,
          label: Text(tr('정렬', 'Sort')),
          width: 160,
          onSelected: (value) {
            if (value != null) clears.setSort(value);
          },
          dropdownMenuEntries: [for (final sort in ClearSort.values) DropdownMenuEntry(value: sort, label: sort.label)],
        ),
        const SizedBox(width: 8),
        // Random sort has no direction.
        OrderButton(
          descending: clears.descending,
          onPressed: clears.sort == ClearSort.random ? null : clears.toggleOrder,
        ),
        const SizedBox(width: 8),
        Badge(
          isLabelVisible: filterCount > 0,
          label: Text('$filterCount'),
          child: FadeSwitcher(
            duration: Motion.fast,
            child: clears.filterOpen
                ? FilledButton.tonalIcon(
                    key: const ValueKey('open'),
                    onPressed: clears.toggleFilterOpen,
                    icon: filterIcon,
                    label: Text(tr('필터', 'Filter')),
                  )
                : OutlinedButton.icon(
                    key: const ValueKey('closed'),
                    onPressed: clears.toggleFilterOpen,
                    icon: filterIcon,
                    label: Text(tr('필터', 'Filter')),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Difficulty range, special difficulties, key count, world's first and game version.
class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.clears, required this.catalog});

  final ClearsController clears;
  final DifficultyCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('난이도', 'Difficulty'), style: theme.textTheme.titleMedium),
            Text(
              tr('슬라이더를 끌어서 범위를 정하세요.', 'Drag the slider to set the range.'),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            DifficultySlider(
              difficulties: catalog.pgu,
              lower: clears.pguLower ?? 0,
              upper: clears.pguUpper ?? catalog.pgu.length - 1,
              onChanged: clears.setPguRange,
            ),
            if (catalog.special.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(tr('특수 난이도도 보기', 'Include special difficulties'), style: theme.textTheme.labelLarge),
                  for (final difficulty in catalog.special)
                    FilterChip(
                      avatar: NetworkIcon(difficulty.icon, size: 18),
                      label: Text(difficulty.name),
                      selected: clears.specialDifficulties.contains(difficulty.name),
                      onSelected: (_) => clears.toggleSpecial(difficulty.name),
                    ),
                ],
              ),
            ],
            const Divider(height: 32),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _Labeled(
                  label: tr('키 수', 'Key count'),
                  child: _Choice<KeyCountFilter>(
                    values: KeyCountFilter.values,
                    labelOf: (value) => value.label,
                    selected: clears.keyCount,
                    onChanged: clears.setKeyCount,
                  ),
                ),
                _Labeled(
                  label: tr('세계 최초', "World's first"),
                  child: _Choice<WorldsFirstFilter>(
                    values: WorldsFirstFilter.values,
                    labelOf: (value) => value.label,
                    selected: clears.worldsFirst,
                    onChanged: clears.setWorldsFirst,
                  ),
                ),
                _Labeled(
                  label: tr('게임 버전', 'Game version'),
                  child: _Choice<GameVersionFilter>(
                    values: GameVersionFilter.values,
                    labelOf: (value) => value.label,
                    selected: clears.version,
                    onChanged: clears.setVersion,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: clears.resetFilters,
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

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.values, required this.labelOf, required this.selected, required this.onChanged});

  final List<T> values;
  final String Function(T value) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
    showSelectedIcon: false,
    segments: [for (final value in values) ButtonSegment(value: value, label: Text(labelOf(value)))],
    selected: {selected},
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

/// One pass row with song and player ([PassRow] layout).
/// Tapping the row opens the pass; tapping the player opens their page.
class ClearRow extends StatelessWidget {
  const ClearRow({super.key, required this.entry});

  final PlayerPassEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final pass = entry.pass;
    final level = entry.level;
    final hidden = entry.levelHidden;
    final difficulty = app.levels.catalog?.byId(level.diffId) ?? level.difficulty;

    return PassRow(
      pass: pass,
      onTap: () => ProfileNavigation.openPass(context, pass.id),
      videoBackdrop: !hidden,
      leading: PassDifficultyIcon(icon: difficulty?.icon, hidden: hidden),
      // Same order as level cards: "#id - artist" on top, song in the middle.
      top: hidden ? null : ['#${level.id}', if (level.artist.isNotEmpty) level.artist].join(' - '),
      title: SlideOverflow(
        child: slidingText(hidden ? tr('숨겨진 레벨', 'Hidden level') : level.song, style: theme.textTheme.titleMedium),
      ),
      bottomText: hidden ? null : level.creatorDisplay,
      extra: _Player(pass: pass),
    );
  }
}

/// Avatar, name and country. Tapping opens the player page.
class _Player extends StatelessWidget {
  const _Player({required this.pass});

  final LevelPass pass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Align(
        alignment: Alignment.centerLeft,
        child: HoverTip(
          message: tr('플레이어 프로필 보기', 'View player profile'),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => ProfileNavigation.openPlayer(context, pass.playerId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProfileAvatar(
                    avatar: AvatarUrls(primary: pass.playerAvatar, fallback: pass.playerAvatarFallback),
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  // Nothing else goes under the name here, so the flag sits below it.
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SlideOverflow(child: slidingText(pass.playerName, style: theme.textTheme.titleSmall)),
                        if (pass.country != null) ...[
                          const SizedBox(height: 4),
                          CountryFlag(country: pass.country, height: 12),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

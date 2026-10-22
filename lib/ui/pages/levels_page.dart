import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/facet.dart';
import '../../core/models/search_models.dart';
import '../widgets/common.dart';
import '../widgets/difficulty_slider.dart';
import '../widgets/level_card.dart';
import '../widgets/motion.dart';
import '../widgets/smooth_scroll.dart';

/// Content always fills the width inside the centered max width.
Widget _constrain(Widget child) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: pageMaxWidth),
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child),
    ),
  ),
);

Widget _section(Widget child) => SliverToBoxAdapter(child: _constrain(child));

class LevelsPage extends StatefulWidget {
  const LevelsPage({super.key});

  @override
  State<LevelsPage> createState() => _LevelsPageState();
}

class _LevelsPageState extends State<LevelsPage> {
  /// Start loading the next page when this close to the end.
  static const _loadMoreThreshold = 600.0;

  /// On a new search, closer than this animates to the top; farther jumps.
  static const _animateToTopLimit = 1500.0;

  final _scroll = SmoothScrollController();
  final _search = TextEditingController();
  int _lastGeneration = -1;

  /// Incremented when new results arrive; part of the card keys so new results replay the entrance animation.
  int _resultsVersion = 0;
  bool _wasSearching = false;

  /// Cards before this index were already shown, so they are built without the animation.
  int _shownCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < _loadMoreThreshold) AppScope.of(context).levels.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final levels = app.levels;

    // The status message changes often during downloads. Not listening to the app here
    // keeps the whole list from rebuilding on every progress update.
    return ListenableBuilder(
      listenable: levels,
      builder: (context, _) {
        _afterBuild(levels);

        final catalog = levels.catalog;
        return FadeSwitcher(
          duration: Motion.slow,
          child: catalog == null
              ? ListenableBuilder(
                  key: const ValueKey('startup'),
                  listenable: app,
                  builder: (context, _) => _StartupState(error: app.startupError, onRetry: app.initialize),
                )
              : KeyedSubtree(key: const ValueKey('content'), child: _buildContent(levels, catalog)),
        );
      },
    );
  }

  Widget _buildContent(LevelsController levels, DifficultyCatalog catalog) => SmoothScrollbar(
    controller: _scroll,
    builder: (context, behavior) => CustomScrollView(
      controller: _scroll,
      scrollBehavior: behavior,
      slivers: [
        _section(const Padding(padding: EdgeInsets.only(top: 24), child: _Header())),
        _section(
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _Toolbar(levels: levels, searchController: _search),
          ),
        ),
        _section(
          Reveal(
            visible: levels.filterOpen,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _FilterCard(levels: levels, catalog: catalog),
            ),
          ),
        ),
        _section(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: _ResultsHeader(levels: levels),
          ),
        ),
        // Dim the previous results while a new search runs.
        SliverAnimatedOpacity(
          opacity: levels.isSearching && levels.levels.isNotEmpty ? 0.45 : 1,
          duration: Motion.medium,
          sliver: SliverList.builder(
            itemCount: levels.levels.length,
            itemBuilder: (context, index) {
              final level = levels.levels[index];
              final isNew = index >= _shownCount;
              return _constrain(
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Appear(
                    key: ValueKey((_resultsVersion, level.id)),
                    animate: isNew,
                    // Stagger cards that appear together.
                    delay: Duration(milliseconds: 35 * (index - _shownCount).clamp(0, 10)),
                    child: LevelCard(level: level, compact: levels.compact),
                  ),
                ),
              );
            },
          ),
        ),
        _section(_Footer(levels: levels)),
      ],
    ),
  );

  /// Post-build work: prepare animations for new results, sync the search box, scroll
  /// to the top on a new search, and load more if the screen isn't full.
  void _afterBuild(LevelsController levels) {
    final generationChanged = levels.searchGeneration != _lastGeneration;
    _lastGeneration = levels.searchGeneration;

    if (_wasSearching && !levels.isSearching) {
      _resultsVersion++;
      _shownCount = 0;
    }
    _wasSearching = levels.isSearching;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shownCount = levels.levels.length;

      if (_search.text != levels.searchText) {
        _search.value = TextEditingValue(
          text: levels.searchText,
          selection: TextSelection.collapsed(offset: levels.searchText.length),
        );
      }
      if (generationChanged && _scroll.hasClients && _scroll.offset > 0) {
        if (_scroll.offset < _animateToTopLimit) {
          _scroll.animateTo(0, duration: Motion.slow, curve: Motion.curve);
        } else {
          _scroll.jumpTo(0);
        }
      }
      if (levels.hasMore && !levels.isLoadingMore) _maybeLoadMore();
    });
  }
}

class _StartupState extends StatelessWidget {
  const _StartupState({required this.error, required this.onRetry});

  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FadeSwitcher(
      child: error == null
          ? EmptyState(
              key: const ValueKey('loading'),
              icon: const CircularProgressIndicator(),
              title: tr('난이도 정보를 불러오는 중...', 'Loading difficulties...'),
            )
          : EmptyState(
              key: const ValueKey('error'),
              icon: const Icon(Icons.cloud_off),
              title: tr('서버에 연결하지 못했습니다', "Couldn't connect to the server"),
              message: error,
              action: FilledButton(onPressed: onRetry, child: Text(tr('다시 시도', 'Retry'))),
            ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('레벨 찾기', 'Levels'), style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          tr('TUF에 등록된 레벨을 찾아서 바로 받아보세요.', 'Find levels on TUF and download them right away.'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ───────────────────────── Search / sort / filter buttons ─────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.levels, required this.searchController});

  final LevelsController levels;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final filterCount = levels.activeFilterCount;
    const filterIcon = Icon(Icons.tune);

    return Row(
      children: [
        Expanded(
          child: SearchBar(
            controller: searchController,
            hintText: tr('곡 이름, 작곡가, 제작자로 검색', 'Search by song, artist, or creator'),
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
            onChanged: levels.setSearchText,
            onSubmitted: (_) => levels.submitSearch(),
            trailing: [
              // Only this button rebuilds when the search text changes.
              ValueListenableBuilder(
                valueListenable: levels.searchTextNotifier,
                builder: (context, text, _) => FadeSwitcher(
                  scale: true,
                  duration: Motion.fast,
                  child: text.isNotEmpty
                      ? IconButton(
                          key: const ValueKey('clear'),
                          tooltip: tr('검색어 지우기', 'Clear search'),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            searchController.clear();
                            levels.clearSearch();
                          },
                        )
                      : const SizedBox.square(key: ValueKey('empty'), dimension: 40),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        DropdownMenu<SortOption>(
          // Recreate the menu when the sort changes from outside (like a reset) or the language changes.
          key: ValueKey((levels.sort.key, appLanguage)),
          initialSelection: levels.sort,
          label: Text(tr('정렬', 'Sort')),
          width: 180,
          onSelected: (option) {
            if (option != null) levels.setSort(option);
          },
          dropdownMenuEntries: [
            for (final option in sortOptions) DropdownMenuEntry(value: option, label: option.label),
          ],
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: levels.ascending ? tr('오름차순', 'Ascending') : tr('내림차순', 'Descending'),
          onPressed: levels.toggleOrder,
          icon: AnimatedRotation(
            turns: levels.ascending ? 0.5 : 0,
            duration: Motion.medium,
            curve: Motion.curve,
            child: const Icon(Icons.arrow_downward),
          ),
        ),
        const SizedBox(width: 8),
        Badge(
          isLabelVisible: filterCount > 0,
          label: Text('$filterCount'),
          child: FadeSwitcher(
            duration: Motion.fast,
            child: levels.filterOpen
                ? FilledButton.tonalIcon(
                    key: const ValueKey('open'),
                    onPressed: levels.toggleFilterOpen,
                    icon: filterIcon,
                    label: Text(tr('필터', 'Filter')),
                  )
                : OutlinedButton.icon(
                    key: const ValueKey('closed'),
                    onPressed: levels.toggleFilterOpen,
                    icon: filterIcon,
                    label: Text(tr('필터', 'Filter')),
                  ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Filter card ─────────────────────────

class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.levels, required this.catalog});

  /// Width of one picker button; three sit side by side.
  static const _pickerWidth = 168.0;

  final LevelsController levels;
  final DifficultyCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('난이도', 'Difficulty'), style: theme.textTheme.titleMedium),
                      Text(
                        tr('슬라이더를 끌어서 범위를 정하세요.', 'Drag the slider to set the range.'),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                FilterChip(
                  avatar: NetworkIcon(levels.qIconUrl, size: 18),
                  label: Text(tr('Q 난이도 포함', 'Include Q difficulties')),
                  selected: levels.includeQ,
                  onSelected: levels.setIncludeQ,
                ),
              ],
            ),
            const SizedBox(height: 12),
            DifficultySlider(
              difficulties: catalog.pgu,
              lower: levels.pguLower,
              upper: levels.pguUpper,
              onChanged: levels.setPguRange,
            ),
            const SizedBox(height: 8),
            // Three pickers on the left, the Q difficulty slider on the right (when Q is included).
            Row(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: _pickerWidth,
                      child: _SpecialPicker(levels: levels),
                    ),
                    SizedBox(
                      width: _pickerWidth,
                      child: _FacetPicker(
                        label: tr('큐레이션 유형', 'Curation types'),
                        description: tr('큐레이터가 매긴 등급으로 찾습니다.', 'Find by the grades curators gave.'),
                        catalog: levels.curationCatalog,
                        selected: levels.selectedCurationIds,
                        matchAll: levels.curationsMatchAll,
                        onToggle: levels.toggleCuration,
                        onClear: levels.clearCurations,
                        onMatchAllChanged: levels.setCurationsMatchAll,
                        levels: levels,
                      ),
                    ),
                    SizedBox(
                      width: _pickerWidth,
                      child: _FacetPicker(
                        label: tr('태그', 'Tags'),
                        description: tr('레벨에 붙은 태그로 찾습니다.', 'Find by the tags on a level.'),
                        catalog: levels.tagCatalog,
                        selected: levels.selectedTagIds,
                        matchAll: levels.tagsMatchAll,
                        onToggle: levels.toggleTag,
                        onClear: levels.clearTags,
                        onMatchAllChanged: levels.setTagsMatchAll,
                        levels: levels,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Reveal(
                    visible: levels.includeQ,
                    child: DifficultySlider(
                      difficulties: catalog.q,
                      lower: levels.qLower,
                      upper: levels.qUpper,
                      onChanged: levels.setQRange,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Labeled(
                    label: tr('클리어한 레벨', 'Cleared levels'),
                    child: _StateChoice(value: levels.clearedFilter, onChanged: levels.setClearedFilter),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Labeled(
                    label: tr('다운로드 가능', 'Downloadable'),
                    child: _StateChoice(value: levels.availableDlFilter, onChanged: levels.setAvailableDlFilter),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: levels.resetAll,
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
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class _StateChoice extends StatelessWidget {
  const _StateChoice({required this.value, required this.onChanged});

  final FilterState value;
  final ValueChanged<FilterState> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<FilterState>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: FilterState.show, label: Text(tr('전체', 'All'))),
      ButtonSegment(value: FilterState.hide, label: Text(tr('숨기기', 'Hide'))),
      ButtonSegment(value: FilterState.only, label: Text(tr('만 보기', 'Only'))),
    ],
    selected: {value},
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

/// Picker button showing how many items are selected.
class _PickerButton extends StatelessWidget {
  const _PickerButton({required this.label, required this.count, required this.controller});

  final String label;
  final int count;
  final MenuController controller;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => controller.isOpen ? controller.close() : controller.open(),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(40),
      padding: const EdgeInsets.only(left: 16, right: 8),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.curve,
          child: count > 0
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Badge(label: Text('$count')),
                )
              : const SizedBox.shrink(),
        ),
        AnimatedRotation(
          turns: controller.isOpen ? 0.5 : 0,
          duration: Motion.medium,
          curve: Motion.curve,
          child: const Icon(Icons.arrow_drop_down),
        ),
      ],
    ),
  );
}

/// Picker for id-based lists like tags and curation types.
class _FacetPicker extends StatelessWidget {
  const _FacetPicker({
    required this.label,
    required this.description,
    required this.catalog,
    required this.selected,
    required this.matchAll,
    required this.onToggle,
    required this.onClear,
    required this.onMatchAllChanged,
    required this.levels,
  });

  final String label;
  final String description;
  final FacetCatalog? catalog;
  final Set<int> selected;
  final bool matchAll;
  final ValueChanged<int> onToggle;
  final VoidCallback onClear;
  final ValueChanged<bool> onMatchAllChanged;
  final LevelsController levels;

  @override
  Widget build(BuildContext context) {
    final items = catalog;
    if (items == null || items.all.isEmpty) {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
        child: Text(tr('$label 없음', 'No ${label.toLowerCase()}'), maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }

    return MenuAnchor(
      // Listen separately so changes made inside the menu show up immediately.
      menuChildren: [
        ListenableBuilder(
          listenable: levels,
          builder: (context, _) => _FacetPanel(
            title: label,
            description: description,
            catalog: items,
            selected: selected,
            matchAll: matchAll,
            onToggle: onToggle,
            onClear: onClear,
            onMatchAllChanged: onMatchAllChanged,
          ),
        ),
      ],
      builder: (context, controller, _) => _PickerButton(label: label, count: selected.length, controller: controller),
    );
  }
}

class _FacetPanel extends StatelessWidget {
  const _FacetPanel({
    required this.title,
    required this.description,
    required this.catalog,
    required this.selected,
    required this.matchAll,
    required this.onToggle,
    required this.onClear,
    required this.onMatchAllChanged,
  });

  final String title;
  final String description;
  final FacetCatalog catalog;
  final Set<int> selected;
  final bool matchAll;
  final ValueChanged<int> onToggle;
  final VoidCallback onClear;
  final ValueChanged<bool> onMatchAllChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 520,
        // There are many tags, so long lists scroll.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(onPressed: selected.isEmpty ? null : onClear, child: Text(tr('선택 해제', 'Clear'))),
                  ],
                ),
                const SizedBox(height: 8),
                // Only meaningful with several selected.
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('하나라도', 'Any'))),
                    ButtonSegment(value: true, label: Text(tr('모두 포함', 'All'))),
                  ],
                  selected: {matchAll},
                  onSelectionChanged: (value) => onMatchAllChanged(value.first),
                ),
                for (final group in catalog.groups) ...[
                  const SizedBox(height: 12),
                  Text(group.title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in group.items)
                        FilterChip(
                          avatar: NetworkIcon(item.icon, size: 20),
                          label: Text(item.name),
                          selected: selected.contains(item.id),
                          onSelected: (_) => onToggle(item.id),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecialPicker extends StatelessWidget {
  const _SpecialPicker({required this.levels});

  final LevelsController levels;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    // Listen separately so changes made inside the menu show up immediately.
    menuChildren: [
      ListenableBuilder(
        listenable: levels,
        builder: (context, _) => _SpecialPanel(levels: levels),
      ),
    ],
    builder: (context, controller, _) => _PickerButton(
      label: tr('특수 난이도', 'Special difficulties'),
      count: levels.selectedSpecials.length,
      controller: controller,
    ),
  );
}

class _SpecialPanel extends StatelessWidget {
  const _SpecialPanel({required this.levels});

  final LevelsController levels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('특수 난이도', 'Special difficulties'), style: theme.textTheme.titleMedium),
                      Text(
                        tr('선택한 난이도를 결과에 함께 보여줍니다.', 'Selected difficulties are shown in the results too.'),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: levels.toggleAllSpecials,
                  child: Text(
                    levels.selectedSpecials.isEmpty ? tr('전체 선택', 'Select all') : tr('전체 선택 해제', 'Deselect all'),
                  ),
                ),
              ],
            ),
            for (final group in levels.specialGroups) ...[
              const SizedBox(height: 12),
              Text(group.title, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final difficulty in group.items)
                    FilterChip(
                      avatar: NetworkIcon(difficulty.icon, size: 20),
                      label: Text(difficulty.name),
                      selected: levels.selectedSpecials.contains(difficulty.name),
                      onSelected: (_) => levels.toggleSpecial(difficulty.name),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({required this.levels});

  final LevelsController levels;

  @override
  Widget build(BuildContext context) {
    final text = levels.hasSearched
        ? tr('레벨 ${formatNumber(levels.total)}개', "${formatNumber(levels.total)} ${plural(levels.total, 'level')}")
        : '';

    return Row(
      children: [
        FadeSwitcher(
          alignment: Alignment.centerLeft,
          child: Text(text, key: ValueKey(text), style: Theme.of(context).textTheme.titleSmall),
        ),
        AnimatedOpacity(
          opacity: levels.isSearching ? 1 : 0,
          duration: Motion.medium,
          // Merely making it transparent keeps it spinning and repainting every frame while invisible.
          child: TickerMode(
            enabled: levels.isSearching,
            child: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ),
        const Spacer(),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.view_agenda_outlined),
              tooltip: tr('자세히 보기', 'Detailed view'),
            ),
            ButtonSegment(value: true, icon: const Icon(Icons.view_headline), tooltip: tr('간략히 보기', 'Compact view')),
          ],
          selected: {levels.compact},
          onSelectionChanged: (selection) => levels.setCompact(selection.first),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.levels});

  final LevelsController levels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget content;
    if (levels.loadMoreError case final message?) {
      content = LoadMoreError(key: const ValueKey('more-error'), message: message, onRetry: levels.retryLoadMore);
    } else if (levels.isLoadingMore) {
      content = const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (levels.hasSearched && !levels.isSearching && levels.levels.isEmpty) {
      content = Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: const Icon(Icons.search_off),
          title: tr('조건에 맞는 레벨이 없어요', 'No levels match'),
          message: tr('검색어나 필터를 바꿔 보세요.', 'Try a different search or filter.'),
        ),
      );
    } else if (!levels.hasMore && levels.levels.isNotEmpty && !levels.isSearching) {
      content = Padding(
        key: const ValueKey('end'),
        padding: const EdgeInsets.all(16),
        child: Text(
          tr('모든 레벨을 불러왔어요', 'All levels loaded'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    } else {
      content = const SizedBox(key: ValueKey('none'), width: double.infinity);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: AnimatedSize(
        duration: Motion.medium,
        curve: Motion.curve,
        alignment: Alignment.topCenter,
        child: FadeSwitcher(alignment: Alignment.topCenter, child: content),
      ),
    );
  }
}

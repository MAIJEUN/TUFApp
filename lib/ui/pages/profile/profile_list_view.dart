import 'package:flutter/material.dart';

import '../../../app/controllers.dart';
import '../../../app/paged_list.dart';
import '../../../core/l10n.dart';
import '../../../core/models/profile.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import 'profile_lists.dart';
import 'profile_section.dart';
import '../../app_shortcuts.dart';

/// Title and toolbar above a long list, shaped like the levels page toolbar (search, sort, order).
class _ListToolbar extends StatefulWidget {
  const _ListToolbar({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.query,
    required this.onQuery,
    required this.sort,
    required this.ascending,
    required this.onToggleOrder,
    this.extra = const [],
  });

  final String title;
  final String? subtitle;
  final String hint;
  final String query;
  final ValueChanged<String> onQuery;
  final Widget sort;
  final bool ascending;
  final VoidCallback onToggleOrder;
  final List<Widget> extra;

  @override
  State<_ListToolbar> createState() => _ListToolbarState();
}

class _ListToolbarState extends State<_ListToolbar> {
  late final _search = TextEditingController(text: widget.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ProfileSectionHeader(title: widget.title, subtitle: widget.subtitle),
      Row(
        children: [
          Expanded(
            child: SearchBar(
              controller: _search,
              focusNode: PageCommandScope.searchFocusOf(context),
              hintText: widget.hint,
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
              onChanged: widget.onQuery,
              trailing: [
                ListenableBuilder(
                  listenable: _search,
                  builder: (context, _) => FadeSwitcher(
                    scale: true,
                    duration: Motion.fast,
                    child: _search.text.isNotEmpty
                        ? IconButton(
                            key: const ValueKey('clear'),
                            tooltip: l10n.clearSearch,
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              widget.onQuery('');
                            },
                          )
                        : const SizedBox.square(key: ValueKey('empty'), dimension: 40),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          widget.sort,
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: widget.ascending ? l10n.ascending : l10n.descending,
            onPressed: widget.onToggleOrder,
            icon: AnimatedRotation(
              turns: widget.ascending ? 0.5 : 0,
              duration: Motion.medium,
              curve: Motion.curve,
              child: const Icon(Icons.arrow_downward),
            ),
          ),
          for (final widget in widget.extra) ...[const SizedBox(width: 8), widget],
        ],
      ),
      const SizedBox(height: 12),
    ],
  );
}

/// Title and toolbar of a player's pass list.
class PlayerPassListHeader extends StatelessWidget {
  const PlayerPassListHeader({super.key, required this.list});

  final PlayerPassList list;

  @override
  Widget build(BuildContext context) => _ListToolbar(
    title: l10n.scores,
    subtitle: list.loading && list.items.isEmpty ? null : l10n.playerPassCount(list.total),
    hint: l10n.searchBySongOrArtist,
    query: list.query,
    onQuery: list.setQuery,
    sort: DropdownMenu<PlayerPassSort>(
      // The selected label is only filled in on creation, so recreate the menu when the language changes.
      key: ValueKey(appLanguage),
      initialSelection: list.sort,
      label: Text(l10n.sort),
      width: 160,
      onSelected: (value) {
        if (value != null) list.setSort(value);
      },
      dropdownMenuEntries: [
        for (final sort in PlayerPassSort.values) DropdownMenuEntry(value: sort, label: sort.label),
      ],
    ),
    ascending: !list.descending,
    onToggleOrder: list.toggleOrder,
    extra: [FilterChip(label: Text(l10n.hideReclears), selected: list.hideReclears, onSelected: list.setHideReclears)],
  );
}

/// Title and toolbar of a creator's level list.
class CreatorLevelListHeader extends StatelessWidget {
  const CreatorLevelListHeader({super.key, required this.list});

  final CreatorLevelList list;

  @override
  Widget build(BuildContext context) => _ListToolbar(
    title: l10n.levelsSection,
    subtitle: list.loading && list.items.isEmpty ? null : l10n.creatorLevelCount(list.total),
    hint: l10n.searchThisCreatorsLevels,
    query: list.query,
    onQuery: list.setQuery,
    sort: DropdownMenu<SortOption>(
      // The selected label is only filled in on creation, so recreate the menu when the language changes.
      key: ValueKey(appLanguage),
      initialSelection: list.sort,
      label: Text(l10n.sort),
      width: 180,
      onSelected: (option) {
        if (option != null) list.setSort(option);
      },
      dropdownMenuEntries: [for (final option in sortOptions) DropdownMenuEntry(value: option, label: option.label)],
    ),
    ascending: list.ascending,
    onToggleOrder: list.toggleOrder,
  );
}

/// Bottom of a long list: loading, error or empty.
class ProfileListFooter extends StatelessWidget {
  const ProfileListFooter({super.key, required this.list, required this.emptyTitle});

  final PagedList<Object> list;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (list.error case final message? when list.items.isEmpty) {
      content = Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(
          icon: const Icon(Icons.cloud_off),
          title: l10n.couldntLoadTheList,
          message: message,
          action: FilledButton(onPressed: list.reload, child: Text(l10n.retry)),
        ),
      );
    } else if (list.loadMoreError case final message?) {
      content = LoadMoreError(key: const ValueKey('more-error'), message: message, onRetry: list.retryLoadMore);
    } else if (list.loading || list.loadingMore) {
      content = const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (list.items.isEmpty) {
      content = Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(icon: const Icon(Icons.search_off), title: emptyTitle),
      );
    } else {
      content = const SizedBox(key: ValueKey('none'), width: double.infinity);
    }
    return FadeSwitcher(alignment: Alignment.topCenter, child: content);
  }
}

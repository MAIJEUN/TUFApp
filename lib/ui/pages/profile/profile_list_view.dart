import 'package:flutter/material.dart';

import '../../../app/controllers.dart';
import '../../../app/paged_list.dart';
import '../../../core/l10n.dart';
import '../../../core/models/profile.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import 'profile_lists.dart';
import 'profile_section.dart';

/// 긴 목록 위의 제목 줄과 도구 줄. 레벨 찾기 화면의 도구 줄(검색 · 정렬 · 순서)과 같은 모양이다.
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
                            tooltip: tr('검색어 지우기', 'Clear search'),
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
            tooltip: widget.ascending ? tr('오름차순', 'Ascending') : tr('내림차순', 'Descending'),
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

/// 플레이어 기록 목록의 제목과 도구 줄.
class PlayerPassListHeader extends StatelessWidget {
  const PlayerPassListHeader({super.key, required this.list});

  final PlayerPassList list;

  @override
  Widget build(BuildContext context) => _ListToolbar(
    title: tr('점수', 'Scores'),
    subtitle: list.loading && list.items.isEmpty
        ? null
        : tr('${formatNumber(list.total)}개 클리어', "${formatNumber(list.total)} ${plural(list.total, 'pass', 'passes')}"),
    hint: tr('곡 이름, 작곡가로 검색', 'Search by song or artist'),
    query: list.query,
    onQuery: list.setQuery,
    sort: DropdownMenu<PlayerPassSort>(
      // 고른 항목의 글은 처음 만들 때만 채워지므로, 언어가 바뀌면 새로 만든다.
      key: ValueKey(appLanguage),
      initialSelection: list.sort,
      label: Text(tr('정렬', 'Sort')),
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
    extra: [
      FilterChip(
        label: Text(tr('재클리어 숨기기', 'Hide reclears')),
        selected: list.hideReclears,
        onSelected: list.setHideReclears,
      ),
    ],
  );
}

/// 제작자 레벨 목록의 제목과 도구 줄.
class CreatorLevelListHeader extends StatelessWidget {
  const CreatorLevelListHeader({super.key, required this.list});

  final CreatorLevelList list;

  @override
  Widget build(BuildContext context) => _ListToolbar(
    title: tr('레벨', 'Levels'),
    subtitle: list.loading && list.items.isEmpty
        ? null
        : tr('${formatNumber(list.total)}개', "${formatNumber(list.total)} ${plural(list.total, 'level')}"),
    hint: tr('이 제작자의 레벨 검색', "Search this creator's levels"),
    query: list.query,
    onQuery: list.setQuery,
    sort: DropdownMenu<SortOption>(
      // 고른 항목의 글은 처음 만들 때만 채워지므로, 언어가 바뀌면 새로 만든다.
      key: ValueKey(appLanguage),
      initialSelection: list.sort,
      label: Text(tr('정렬', 'Sort')),
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

/// 긴 목록 맨 아래: 불러오는 중, 실패, 비어 있음.
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
          title: tr('목록을 불러오지 못했어요', "Couldn't load the list"),
          message: message,
          action: FilledButton(onPressed: list.reload, child: Text(tr('다시 시도', 'Retry'))),
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

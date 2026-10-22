import 'package:flutter/material.dart';

import '../../app/paged_list.dart';
import '../../core/l10n.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/smooth_scroll.dart';

/// Fills the width inside the centered max width (same as the levels page).
Widget browseConstrain(Widget child) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: pageMaxWidth),
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child),
    ),
  ),
);

Widget _section(Widget child) => SliverToBoxAdapter(child: browseConstrain(child));

/// Scaffold for an infinite list page, shaped like the levels page:
/// title, toolbar, (filters), result count, list, footer.
class BrowsePage<T> extends StatefulWidget {
  const BrowsePage({
    super.key,
    required this.list,
    required this.title,
    required this.subtitle,
    required this.toolbar,
    required this.countText,
    required this.itemBuilder,
    required this.itemKey,
    required this.emptyTitle,
    required this.endText,
    this.filter,
  });

  final PagedList<T> list;
  final String title;
  final String subtitle;
  final Widget toolbar;

  /// Filter card that expands below the toolbar.
  final Widget? filter;

  /// Result count text, like "63,029 passes".
  final String Function(int total) countText;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Object Function(T item) itemKey;
  final String emptyTitle;
  final String endText;

  @override
  State<BrowsePage<T>> createState() => _BrowsePageState<T>();
}

class _BrowsePageState<T> extends State<BrowsePage<T>> {
  static const _loadMoreThreshold = 600.0;
  static const _animateToTopLimit = 1500.0;

  final _scroll = SmoothScrollController();
  int _generation = -1;

  /// Rows before this index were already shown, so they are built without the entrance animation.
  int _shownCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < _loadMoreThreshold) widget.list.loadMore();
  }

  /// Scrolls to the top on a new search and loads more if the list doesn't fill the screen.
  void _afterBuild(PagedList<T> list) {
    final generationChanged = list.generation != _generation;
    _generation = list.generation;
    if (generationChanged) _shownCount = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!list.loading) _shownCount = list.items.length;
      if (generationChanged && _scroll.hasClients && _scroll.offset > 0) {
        if (_scroll.offset < _animateToTopLimit) {
          _scroll.animateTo(0, duration: Motion.slow, curve: Motion.curve);
        } else {
          _scroll.jumpTo(0);
        }
      }
      if (list.hasMore && !list.loadingMore && !list.loading) _maybeLoadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = widget.list;

    return ListenableBuilder(
      listenable: list,
      builder: (context, _) {
        _afterBuild(list);
        final searching = list.loading && list.items.isNotEmpty;
        final countText = list.loading && list.items.isEmpty ? '' : widget.countText(list.total);

        return SmoothScrollbar(
          controller: _scroll,
          builder: (context, behavior) => CustomScrollView(
            controller: _scroll,
            scrollBehavior: behavior,
            slivers: [
              _section(
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              _section(Padding(padding: const EdgeInsets.only(top: 16), child: widget.toolbar)),
              if (widget.filter case final filter?) _section(filter),
              _section(
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Row(
                    children: [
                      FadeSwitcher(
                        alignment: Alignment.centerLeft,
                        child: Text(countText, key: ValueKey(countText), style: theme.textTheme.titleSmall),
                      ),
                      AnimatedOpacity(
                        opacity: list.loading ? 1 : 0,
                        duration: Motion.medium,
                        child: TickerMode(
                          enabled: list.loading,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Dim the previous results while a new search runs.
              SliverAnimatedOpacity(
                opacity: searching ? 0.45 : 1,
                duration: Motion.medium,
                sliver: SliverList.builder(
                  itemCount: list.items.length,
                  itemBuilder: (context, index) {
                    final item = list.items[index];
                    final isNew = index >= _shownCount;
                    return browseConstrain(
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Appear(
                          key: ValueKey((list.generation, widget.itemKey(item))),
                          animate: isNew,
                          delay: Duration(milliseconds: 35 * (index - _shownCount).clamp(0, 10)),
                          child: widget.itemBuilder(context, item, index),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _section(_Footer(list: list, emptyTitle: widget.emptyTitle, endText: widget.endText)),
            ],
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.list, required this.emptyTitle, required this.endText});

  final PagedList<Object?> list;
  final String emptyTitle;
  final String endText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget content;
    if (list.error case final error? when list.items.isEmpty) {
      content = Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: const Icon(Icons.cloud_off),
          title: tr('목록을 불러오지 못했어요', "Couldn't load the list"),
          message: error,
          action: FilledButton(onPressed: list.reload, child: Text(tr('다시 시도', 'Retry'))),
        ),
      );
    } else if (list.loadMoreError case final message?) {
      content = LoadMoreError(key: const ValueKey('more-error'), message: message, onRetry: list.retryLoadMore);
    } else if (list.loadingMore || (list.loading && list.items.isEmpty)) {
      content = const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!list.loading && list.items.isEmpty) {
      content = Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: const Icon(Icons.search_off),
          title: emptyTitle,
          message: tr('다른 조건으로 찾아보세요.', 'Try different filters.'),
        ),
      );
    } else if (!list.hasMore && !list.loading) {
      content = Padding(
        key: const ValueKey('end'),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(endText, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    } else {
      content = const SizedBox(key: ValueKey('none'), width: double.infinity);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      child: AnimatedSize(
        duration: Motion.medium,
        curve: Motion.curve,
        alignment: Alignment.topCenter,
        child: FadeSwitcher(alignment: Alignment.topCenter, child: content),
      ),
    );
  }
}

/// Search box, the same as on the levels and packs pages.
class BrowseSearchBar extends StatefulWidget {
  const BrowseSearchBar({super.key, required this.initialText, required this.hint, required this.onChanged});

  final String initialText;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<BrowseSearchBar> createState() => _BrowseSearchBarState();
}

class _BrowseSearchBarState extends State<BrowseSearchBar> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SearchBar(
    controller: _controller,
    hintText: widget.hint,
    leading: const Icon(Icons.search),
    elevation: const WidgetStatePropertyAll(0),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    onChanged: widget.onChanged,
    trailing: [
      ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => FadeSwitcher(
          scale: true,
          duration: Motion.fast,
          child: _controller.text.isNotEmpty
              ? IconButton(
                  key: const ValueKey('clear'),
                  tooltip: tr('검색어 지우기', 'Clear search'),
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                )
              : const SizedBox.square(key: ValueKey('empty'), dimension: 40),
        ),
      ),
    ],
  );
}

/// Toggles ascending/descending order.
class OrderButton extends StatelessWidget {
  const OrderButton({super.key, required this.descending, required this.onPressed});

  final bool descending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: descending ? tr('내림차순', 'Descending') : tr('오름차순', 'Ascending'),
    onPressed: onPressed,
    icon: AnimatedRotation(
      turns: descending ? 0 : 0.5,
      duration: Motion.medium,
      curve: Motion.curve,
      child: const Icon(Icons.arrow_downward),
    ),
  );
}

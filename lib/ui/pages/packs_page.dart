import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/pack.dart';
import '../widgets/common.dart';
import '../widgets/hover_tip.dart';
import '../widgets/level_card.dart';
import '../widgets/motion.dart';
import '../widgets/raster_snapshot.dart';
import '../widgets/slide_overflow.dart';
import '../widgets/smooth_scroll.dart';

/// 다른 페이지와 같은 폭으로 가운데 정렬한다.
const _maxWidth = pageMaxWidth;
const _gutter = 24.0;

Widget _constrain(Widget child) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: _maxWidth),
    child: SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _gutter),
        child: child,
      ),
    ),
  ),
);

Widget _section(Widget child) => SliverToBoxAdapter(child: _constrain(child));

/// 슬리버를 [_maxWidth] 안에 가운데 놓는다 (격자처럼 _constrain으로 감쌀 수 없는 것).
Widget _centeredSliver(Widget sliver) => SliverLayoutBuilder(
  builder: (context, constraints) {
    final side = max(_gutter, (constraints.crossAxisExtent - _maxWidth) / 2 + _gutter);
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: side),
      sliver: sliver,
    );
  },
);

/// 커뮤니티 레벨 팩. 목록에서 팩을 누르면 그 위로 팩 내용이 열린다.
class PacksPage extends StatefulWidget {
  const PacksPage({super.key});

  @override
  State<PacksPage> createState() => _PacksPageState();
}

class _PacksPageState extends State<PacksPage> {
  @override
  Widget build(BuildContext context) {
    final packs = AppScope.of(context).packs;

    return ListenableBuilder(
      listenable: packs,
      builder: (context, _) {
        final opened = packs.openedPack != null;
        return Stack(
          fit: StackFit.expand,
          children: [
            // 목록은 그대로 살려 둬서 돌아왔을 때 스크롤 위치가 유지된다.
            Offstage(
              offstage: opened,
              child: TickerMode(
                enabled: !opened,
                child: _PackList(packs: packs),
              ),
            ),
            FadeSwitcher(
              child: opened
                  ? _PackDetailView(key: ValueKey(packs.openedPack!.id), packs: packs)
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── 팩 목록 ─────────────────────────

class _PackList extends StatefulWidget {
  const _PackList({required this.packs});

  final PacksController packs;

  @override
  State<_PackList> createState() => _PackListState();
}

class _PackListState extends State<_PackList> {
  static const _loadMoreThreshold = 600.0;

  final _scroll = SmoothScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = widget.packs.query;
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < _loadMoreThreshold) widget.packs.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final packs = widget.packs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && packs.hasMore && !packs.isLoadingMore && !packs.isSearching) _maybeLoadMore();
      // 다른 화면에서 검색어를 정하고 왔으면 (프로필의 '사용자 팩 보기') 검색창도 맞춘다.
      if (mounted && _search.text != packs.query) _search.text = packs.query;
    });

    return SmoothScrollbar(
      controller: _scroll,
      builder: (context, behavior) => CustomScrollView(
        controller: _scroll,
        scrollBehavior: behavior,
        slivers: [
          _section(const Padding(padding: EdgeInsets.only(top: 24), child: _ListHeader())),
          _section(
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _ListToolbar(packs: packs, searchController: _search),
            ),
          ),
          _section(
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              child: _ListResultsHeader(packs: packs),
            ),
          ),
          _centeredSliver(
            SliverAnimatedOpacity(
              opacity: packs.isSearching && packs.packs.isNotEmpty ? 0.45 : 1,
              duration: Motion.medium,
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  mainAxisExtent: _PackCard.height,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: packs.packs.length,
                itemBuilder: (context, index) {
                  final pack = packs.packs[index];
                  return _PackCard(key: ValueKey(pack.id), pack: pack, onOpen: () => packs.open(pack));
                },
              ),
            ),
          ),
          _section(_ListFooter(packs: packs)),
        ],
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('레벨 팩', 'Level Packs'), style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          tr(
            '커뮤니티에서 만든 레벨 팩을 둘러보고, 폴더 구조 그대로 한 번에 받아보세요.',
            'Browse level packs made by the community and download them in one go, folders and all.',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ListToolbar extends StatelessWidget {
  const _ListToolbar({required this.packs, required this.searchController});

  final PacksController packs;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SearchBar(
          controller: searchController,
          hintText: tr('팩 이름으로 검색', 'Search by pack name'),
          leading: const Icon(Icons.search),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          onChanged: packs.setQuery,
          onSubmitted: (_) => packs.search(),
          trailing: [
            FadeSwitcher(
              scale: true,
              duration: Motion.fast,
              child: packs.query.isNotEmpty
                  ? IconButton(
                      key: const ValueKey('clear'),
                      tooltip: tr('검색어 지우기', 'Clear search'),
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        searchController.clear();
                        packs.setQuery('');
                        packs.search();
                      },
                    )
                  : const SizedBox.square(key: ValueKey('empty'), dimension: 40),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      DropdownMenu<PackSort>(
        // 고른 항목의 글은 처음 만들 때만 채워지므로, 언어가 바뀌면 새로 만든다.
        key: ValueKey(appLanguage),
        initialSelection: packs.sort,
        label: Text(tr('정렬', 'Sort')),
        width: 160,
        onSelected: (value) {
          if (value != null) packs.setSort(value);
        },
        dropdownMenuEntries: [for (final sort in PackSort.values) DropdownMenuEntry(value: sort, label: sort.label)],
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: packs.descending ? tr('내림차순', 'Descending') : tr('오름차순', 'Ascending'),
        onPressed: packs.toggleOrder,
        icon: AnimatedRotation(
          turns: packs.descending ? 0 : 0.5,
          duration: Motion.medium,
          curve: Motion.curve,
          child: const Icon(Icons.arrow_downward),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(tooltip: tr('새로고침', 'Refresh'), onPressed: packs.search, icon: const Icon(Icons.refresh)),
    ],
  );
}

class _ListResultsHeader extends StatelessWidget {
  const _ListResultsHeader({required this.packs});

  final PacksController packs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = packs.hasSearched
        ? tr('팩 ${formatNumber(packs.total)}개', "${formatNumber(packs.total)} ${plural(packs.total, 'pack')}")
        : '';

    return Row(
      children: [
        FadeSwitcher(
          alignment: Alignment.centerLeft,
          child: Text(text, key: ValueKey(text), style: theme.textTheme.titleSmall),
        ),
        AnimatedOpacity(
          opacity: packs.isSearching ? 1 : 0,
          duration: Motion.medium,
          child: TickerMode(
            enabled: packs.isSearching,
            child: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.packs});

  final PacksController packs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget content;
    if (packs.error case final error?) {
      content = Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: const Icon(Icons.cloud_off),
          title: tr('팩을 불러오지 못했어요', "Couldn't load packs"),
          message: error,
          action: FilledButton(onPressed: packs.search, child: Text(tr('다시 시도', 'Retry'))),
        ),
      );
    } else if (packs.loadMoreError case final message?) {
      content = LoadMoreError(key: const ValueKey('more-error'), message: message, onRetry: packs.retryLoadMore);
    } else if (packs.isLoadingMore || (!packs.hasSearched && packs.isSearching)) {
      content = const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (packs.hasSearched && !packs.isSearching && packs.packs.isEmpty) {
      content = Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: const Icon(Icons.search_off),
          title: tr('찾는 팩이 없어요', 'No packs found'),
          message: tr('다른 이름으로 검색해 보세요.', 'Try searching for a different name.'),
        ),
      );
    } else if (!packs.hasMore && packs.packs.isNotEmpty && !packs.isSearching) {
      content = Padding(
        key: const ValueKey('end'),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            tr('모든 팩을 불러왔어요', 'All packs loaded'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
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

/// 팩 목록의 카드 한 칸. 위쪽에 강조색 줄을 두르고, 앞쪽 레벨 몇 개를 미리 보여준다.
class _PackCard extends StatelessWidget {
  const _PackCard({super.key, required this.pack, required this.onOpen});

  static const height = 268.0;
  static const _previewCount = 3;

  final LevelPack pack;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = AppScope.of(context).levels.catalog;
    final int more = pack.levelCount - min(pack.preview.length, _previewCount);

    return HoverCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      background: (context, hovered) => Align(
        alignment: Alignment.topCenter,
        child: _PackCardBar(pack: pack, hovered: hovered),
      ),
      child: SizedBox(
        height: height - 30,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PackIcon(url: pack.iconUrl, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 한 줄로 두고 넘치면 흘러가게 한다 (두 줄이면 카드 높이를 넘는다).
                      SizedBox(
                        height: 26,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SlideOverflow(child: slidingText(pack.name, style: theme.textTheme.titleMedium)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _LevelCountLine(pack: pack),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Likes(count: pack.favoritesCount),
              ],
            ),
            const SizedBox(height: 10),
            _OwnerLine(owner: pack.owner),
            const SizedBox(height: 10),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            for (final level in pack.preview.take(_previewCount))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _PreviewRow(song: level.song, icon: catalog?.byId(level.diffId)?.icon),
              ),
            const Spacer(),
            if (more > 0) _MoreLevels(pack: pack, previewCount: _previewCount, more: more),
          ],
        ),
      ),
    );
  }
}

/// 제목까지 보여준 미리보기 뒤의 레벨들. 난이도 아이콘을 겹쳐 한 줄로 늘어놓고, 끝에 "+N개 더"를 붙인다.
///
/// - N은 제목 미리보기를 뺀 나머지 레벨 전부다 (아이콘으로 보인 것도 포함).
/// - 아이콘은 "+N개 더" 글자 바로 앞까지 들어가는 만큼 그린다. 자리가 모자라면 뒤쪽 레벨은 아이콘 없이 N에만 들어간다.
///
/// 목록 응답에는 앞쪽 레벨 몇 개만 오므로, 카드가 보일 때 팩 내용을 받아서 채운다.
class _MoreLevels extends StatelessWidget {
  const _MoreLevels({required this.pack, required this.previewCount, required this.more});

  static const _iconSize = 20.0;

  /// 아이콘이 겹치는 간격 (아이콘 폭보다 좁게 두어 겹친다).
  static const _step = 13.0;

  /// 아이콘 줄과 글자 사이.
  static const _gap = 8.0;

  /// 자리에 들어가는 개수보다 더 그릴 개수. 이만큼이 흐려지면서 잘린다.
  static const _overflowIcons = 3;

  final LevelPack pack;
  final int previewCount;
  final int more;

  @override
  Widget build(BuildContext context) {
    final packs = AppScope.of(context).packs;
    final catalog = AppScope.of(context).levels.catalog;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    // 겹친 아이콘이 수십 개라 그리기가 비싸다. 한 장으로 구워 두고 스크롤할 때는 그것만 그린다.
    return SizedBox(
      height: 24,
      child: RasterSnapshot(
        child: FutureBuilder<LevelPackDetail?>(
          initialData: packs.cachedDetail(pack.id),
          future: packs.detailFor(pack.id),
          builder: (context, snapshot) {
            final detail = snapshot.data;
            // 미리보기에 이미 나온 레벨은 빼고, 팩 안 순서대로.
            final shownIds = {for (final level in pack.preview.take(previewCount)) level.id};
            final icons = [
              if (detail != null)
                for (final entry in detail.allLevels)
                  if (!shownIds.contains(entry.level.id)) catalog?.byId(entry.level.diffId)?.icon,
            ];

            final label = tr('+$more개 더', '+$more more');
            return LayoutBuilder(
              builder: (context, constraints) {
                // 글자가 실제로 차지하는 폭을 재서, 아이콘이 그 바로 앞까지 오게 한다.
                final painter = TextPainter(
                  text: TextSpan(text: label, style: textStyle),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final room = constraints.maxWidth - painter.width - _gap;
                painter.dispose();
                final fit = room < _iconSize ? 0 : ((room - _iconSize) / _step).floor() + 1;
                // 자리보다 조금 더 그려서, 넘칠 때 오른쪽 끝이 흐려지며 이어지는 느낌을 준다.
                final count = min(icons.length, fit + _overflowIcons);

                return Row(
                  children: [
                    // 아이콘이 없을 때도 자리를 두어야, 내용이 도착했을 때 나타나는 애니메이션을 줄 수 있다.
                    _IconStrip(
                      icons: icons.take(count).toList(),
                      size: _iconSize,
                      step: _step,
                      maxWidth: max(0.0, room),
                    ),
                    // 글자는 항상 오른쪽 끝에 붙인다.
                    const Spacer(),
                    Text(label, style: textStyle),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 팩 카드 위쪽의 강조 줄. 그 팩을 받는 동안에는 진행 막대가 된다 (폴더만 받아도).
class _PackCardBar extends StatelessWidget {
  const _PackCardBar({required this.pack, required this.hovered});

  final LevelPack pack;
  final bool hovered;

  /// 받는 동안에는 조금 두껍게 해서 눈에 띄게 한다.
  static const _height = 3.0;
  static const _activeHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final color = Theme.of(context).colorScheme.primary;
    final download = app.packs.download;

    if (download == null || download.packId != pack.id || download.finished) {
      return AnimatedContainer(
        duration: Motion.fast,
        height: _height,
        color: color.withValues(alpha: hovered ? 1 : 0.55),
      );
    }

    // 지금 받는 레벨이 바뀌면 그 레벨의 진행률을 새로 듣는다.
    // 받기 작업은 레벨을 시작한 다음에 생기므로 받기 목록도 함께 듣는다.
    return ListenableBuilder(
      listenable: Listenable.merge([download, app.installs]),
      builder: (context, _) {
        final current = download.currentLevelId;
        final job = current == null ? null : app.installs.jobFor(current);
        return ListenableBuilder(
          listenable: job ?? download,
          builder: (context, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: download.progress(job?.fraction ?? 0)),
            duration: const Duration(milliseconds: 200),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: _activeHeight,
              color: color,
              backgroundColor: color.withValues(alpha: 0.2),
            ),
          ),
        );
      },
    );
  }
}

/// 겹쳐 늘어놓은 난이도 아이콘들.
///
/// 팩 내용이 도착해서 아이콘이 처음 생길 때 왼쪽부터 하나씩 살짝 커지며 나타난다.
/// 이미 받아 둔 팩이라 처음부터 아이콘이 있으면 애니메이션 없이 바로 보인다.
/// [maxWidth]를 넘치면 다른 넘치는 내용들처럼 오른쪽 끝이 흐려진다 (움직이지는 않는다).
class _IconStrip extends StatefulWidget {
  const _IconStrip({required this.icons, required this.size, required this.step, required this.maxWidth});

  final List<String?> icons;
  final double size;
  final double step;
  final double maxWidth;

  @override
  State<_IconStrip> createState() => _IconStripState();
}

class _IconStripState extends State<_IconStrip> with SingleTickerProviderStateMixin {
  /// 아이콘 하나가 나타나는 시간과, 다음 아이콘이 따라 나오는 간격.
  static const _each = Duration(milliseconds: 260);
  static const _stagger = Duration(milliseconds: 22);

  /// 처음부터 아이콘이 있었으면 끝난 상태(1)로 시작한다.
  /// initState에서 만들어야 한다. 처음 쓸 때 만들면(late), 비어 있는 동안에는 한 번도 쓰이지 않다가
  /// 아이콘이 생긴 순간에야 만들어져서 '처음부터 있었다'고 잘못 판단하고 애니메이션을 건너뛴다.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: widget.icons.isEmpty ? 0 : 1);
  }

  bool _preparing = false;

  @override
  void didUpdateWidget(_IconStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 비어 있다가 아이콘이 생기면 한 번 나타나게 한다.
    if (widget.icons.isNotEmpty && _controller.value == 0 && !_controller.isAnimating && !_preparing) {
      _appear();
    }
  }

  /// 아이콘 그림을 먼저 다 불러온 뒤에 나타나기 시작한다.
  /// (그림이 준비되기 전에 움직이면 빈칸만 커지다가 그림이 한꺼번에 툭 생긴다.)
  Future<void> _appear() async {
    _preparing = true;
    await NetworkIcon.precache(context, widget.icons, _StackedIcon.iconSize(widget.size));
    _preparing = false;
    if (!mounted) return;
    _controller.duration = _each + _stagger * (widget.icons.length - 1);
    await _controller.forward().orCancel.catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icons = widget.icons;
    if (icons.isEmpty) return const SizedBox.shrink();

    final totalMs = (_each + _stagger * (icons.length - 1)).inMilliseconds;
    final full = widget.size + (icons.length - 1) * widget.step;

    return SizedBox(
      // 다 들어가면 그만큼만, 넘치면 자리만큼만 차지한다. 넘치는 쪽 끝은 FadeEdges가 흐리게 지운다.
      width: min(full, widget.maxWidth),
      height: widget.size,
      child: FadeEdges(
        child: SizedBox(
          width: full,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Stack(
              children: [
                for (var i = 0; i < icons.length; i++)
                  Positioned(
                    left: i * widget.step,
                    child: _appearing(
                      Interval(
                        (_stagger.inMilliseconds * i) / totalMs,
                        (_stagger.inMilliseconds * i + _each.inMilliseconds) / totalMs,
                      ).transform(_controller.value),
                      (opacity) => _StackedIcon(url: icons[i], size: widget.size, opacity: opacity),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [t]가 0→1로 가는 동안 투명했다가 살짝 커지며 나타난다. 다 나타나면 아무것도 덧씌우지 않는다.
  /// 투명도는 레이어(Opacity) 대신 아이콘을 그릴 때 바로 입힌다 (이 줄은 한 장으로 구워 두기 때문).
  static Widget _appearing(double t, Widget Function(double opacity) icon) {
    if (t >= 1) return icon(1);
    if (t <= 0) return const SizedBox.shrink();
    return Transform.scale(
      scale: 0.6 + 0.4 * Curves.easeOutBack.transform(t),
      child: icon(Curves.easeOut.transform(t)),
    );
  }
}

/// 겹친 아이콘 하나. 뒤 아이콘과 구분되게 카드 색 테두리를 두른다.
class _StackedIcon extends StatelessWidget {
  const _StackedIcon({required this.url, required this.size, this.opacity = 1});

  /// 테두리를 뺀 아이콘 크기. 미리 불러 둘 때도 같은 크기를 써야 같은 그림을 쓴다.
  static double iconSize(double size) => size - 3;

  final String? url;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final back = Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: opacity);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: back,
        border: Border.all(color: back, width: 1.5),
      ),
      child: NetworkIcon(url, size: iconSize(size), opacity: opacity),
    );
  }
}

class _LevelCountLine extends StatelessWidget {
  const _LevelCountLine({required this.pack});

  final LevelPack pack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Text(
          tr(
            '레벨 ${formatNumber(pack.levelCount)}개',
            "${formatNumber(pack.levelCount)} ${plural(pack.levelCount, 'level')}",
          ),
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        if (pack.isPinned) ...[
          const SizedBox(width: 6),
          HoverTip(
            message: tr('고정된 팩', 'Pinned pack'),
            child: _PinIcon(Icons.push_pin_outlined, size: 16, color: muted),
          ),
        ],
      ],
    );
  }
}

class _Likes extends StatelessWidget {
  const _Likes({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return HoverTip(
      message: tr('좋아요 ${formatNumber(count)}개', "${formatNumber(count)} ${plural(count, 'like')}"),
      child: Column(
        children: [
          Icon(Icons.favorite_border, size: 22, color: muted),
          const SizedBox(height: 2),
          Text(formatNumber(count), style: theme.textTheme.labelMedium?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

class _OwnerLine extends StatelessWidget {
  const _OwnerLine({required this.owner});

  final PackOwner? owner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = owner?.name ?? tr('알 수 없음', 'Unknown');
    return Row(
      children: [
        _Avatar(url: owner?.avatarUrl, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: SlideOverflow(child: slidingText(name, style: theme.textTheme.bodyMedium)),
        ),
      ],
    );
  }
}

/// 미리보기 레벨 한 줄: 난이도 아이콘과 곡 이름.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.song, required this.icon});

  final String song;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          NetworkIcon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SlideOverflow(child: slidingText(song, style: theme.textTheme.bodySmall)),
          ),
        ],
      ),
    );
  }
}

/// 팩 아이콘. 없으면 상자 모양을 대신 둔다.
class _PackIcon extends StatelessWidget {
  const _PackIcon({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Container(
        width: size,
        height: size,
        color: colors.surfaceContainerHighest,
        child: url == null
            ? Icon(Icons.inventory_2_outlined, size: size * 0.5, color: colors.onSurfaceVariant)
            : NetworkIcon(url, size: size),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: colors.surfaceContainerHighest,
        child: url == null
            ? Icon(Icons.person, size: size * 0.7, color: colors.onSurfaceVariant)
            : NetworkIcon(url, size: size),
      ),
    );
  }
}

// ───────────────────────── 팩 내용 ─────────────────────────

/// 폴더 구조를 한 줄씩 늘어놓은 것.
///
/// 접힌 폴더 안의 줄도 목록에 그대로 두고 [visible]만 끈다. 그래야 줄 순서가 바뀌지 않아서
/// 폴더를 열고 닫을 때 줄마다 부드럽게 펼쳐지고 접힌다 (접혀 있는 줄은 아무것도 만들지 않는다).
sealed class _Row {
  const _Row(this.depth, {required this.visible});

  final int depth;
  final bool visible;
}

class _FolderRow extends _Row {
  const _FolderRow(this.folder, super.depth, {required super.visible});

  final PackFolder folder;
}

class _LevelRow extends _Row {
  const _LevelRow(this.entry, super.depth, {required super.visible});

  final PackLevelEntry entry;
}

List<_Row> _flatten(List<PackNode> nodes, Set<int> expanded, {int depth = 0, bool visible = true}) => [
  for (final node in nodes)
    ...switch (node) {
      PackFolder() => [
        _FolderRow(node, depth, visible: visible),
        ..._flatten(node.children, expanded, depth: depth + 1, visible: visible && expanded.contains(node.id)),
      ],
      PackLevelEntry() => [_LevelRow(node, depth, visible: visible)],
    },
];

class _PackDetailView extends StatefulWidget {
  const _PackDetailView({super.key, required this.packs});

  final PacksController packs;

  @override
  State<_PackDetailView> createState() => _PackDetailViewState();
}

class _PackDetailViewState extends State<_PackDetailView> {
  /// 폴더 안 한 단계마다 들여 쓰는 폭.
  static const _indent = 28.0;

  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final packs = widget.packs;
    final pack = packs.openedPack!;
    final detail = packs.detail;

    return ListenableBuilder(
      // 받은 레벨이 바뀌면 tr('받기', 'Download') 버튼에 적힌 개수도 바뀐다.
      listenable: app.installs,
      builder: (context, _) {
        final rows = detail == null ? const <_Row>[] : _flatten(detail.items, packs.expanded);

        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SmoothScrollbar(
            controller: _scroll,
            builder: (context, behavior) => CustomScrollView(
              controller: _scroll,
              scrollBehavior: behavior,
              slivers: [
                _section(
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: packs.close,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(tr('팩 목록', 'All packs')),
                      ),
                    ),
                  ),
                ),
                _section(
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _DetailHeader(packs: packs, pack: pack, detail: detail),
                  ),
                ),
                if (detail != null)
                  _section(
                    Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: _ItemsHeader(packs: packs, detail: detail),
                    ),
                  ),
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return Reveal(
                      key: ValueKey(_keyOf(row)),
                      visible: row.visible,
                      duration: Motion.medium,
                      child: _constrain(
                        Padding(
                          padding: EdgeInsets.only(left: row.depth * _indent, bottom: 8),
                          child: switch (row) {
                            _FolderRow(:final folder) => _FolderHeader(packs: packs, pack: pack, folder: folder),
                            _LevelRow(:final entry) => LevelCard(level: entry.level, compact: app.levels.compact),
                          },
                        ),
                      ),
                    );
                  },
                ),
                _section(_DetailFooter(packs: packs)),
              ],
            ),
          ),
        );
      },
    );
  }

  static Object _keyOf(_Row row) => switch (row) {
    _FolderRow(:final folder) => ('folder', folder.id),
    _LevelRow(:final entry) => ('level', entry.id),
  };
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.packs, required this.pack, required this.detail});

  final PacksController packs;
  final LevelPack pack;
  final LevelPackDetail? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final detail = this.detail;
    final toDownload = detail == null ? const <PackDownloadItem>[] : packs.downloadItems(pack, detail.items);

    // 모서리가 둥근 상자에는 한쪽 테두리만 줄 수 없어서, 위쪽 강조 줄은 따로 겹쳐 그린다.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: theme.colorScheme.surfaceContainerLow,
        foregroundDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colorScheme.primary, width: 3)),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _PackIcon(url: pack.iconUrl, size: 96),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: SlideOverflow(child: slidingText(pack.name, style: theme.textTheme.headlineSmall)),
                      ),
                      if (pack.isPinned) ...[
                        const SizedBox(width: 8),
                        HoverTip(
                          message: tr('고정된 팩', 'Pinned pack'),
                          child: _PinIcon(Icons.push_pin_outlined, color: muted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Avatar(url: pack.owner?.avatarUrl, size: 24),
                      const SizedBox(width: 8),
                      Flexible(
                        child: SlideOverflow(
                          child: slidingText(
                            pack.owner?.name ?? tr('알 수 없음', 'Unknown'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.library_music_outlined, size: 16, color: muted),
                      const SizedBox(width: 4),
                      Text(
                        tr(
                          '레벨 ${formatNumber(pack.levelCount)}개',
                          "${formatNumber(pack.levelCount)} ${plural(pack.levelCount, 'level')}",
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.favorite_border, size: 16, color: muted),
                      const SizedBox(width: 4),
                      Text(
                        formatNumber(pack.favoritesCount),
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    ],
                  ),
                  if (pack.description case final description? when description.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description.trim(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            _PackDownloadButton(
              packs: packs,
              scope: pack.id,
              label: pack.name,
              items: toDownload,
              idleText: detail == null
                  ? tr('팩 받기', 'Download pack')
                  : tr('팩 받기 (${toDownload.length}개)', 'Download pack (${toDownload.length})'),
              filled: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader({required this.packs, required this.detail});

  final PacksController packs;
  final LevelPackDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFolders = detail.items.any((node) => node is PackFolder);
    final allExpanded = packs.allExpanded;

    return Row(
      children: [
        Text(tr('항목', 'Items'), style: theme.textTheme.titleLarge),
        const Spacer(),
        if (hasFolders)
          TextButton.icon(
            onPressed: () => packs.setAllExpanded(!allExpanded),
            icon: Icon(allExpanded ? Icons.unfold_less : Icons.unfold_more),
            label: Text(allExpanded ? tr('모두 접기', 'Collapse all') : tr('모두 펼치기', 'Expand all')),
          ),
      ],
    );
  }
}

/// 폴더 한 줄. 누르면 펼치고 접는다. 폴더째 받을 수도 있다.
class _FolderHeader extends StatelessWidget {
  const _FolderHeader({required this.packs, required this.pack, required this.folder});

  final PacksController packs;
  final LevelPack pack;
  final PackFolder folder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final open = packs.expanded.contains(folder.id);
    final levelCount = folder.allLevels.length;
    final toDownload = packs.downloadItems(pack, [folder], path: packs.folderPathOf(folder));

    return HoverCard(
      onTap: () => packs.toggleFolder(folder.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          AnimatedRotation(
            turns: open ? 0 : -0.25,
            duration: Motion.medium,
            curve: Motion.curve,
            child: Icon(Icons.expand_more, color: muted),
          ),
          const SizedBox(width: 8),
          Icon(open ? Icons.folder_open : Icons.folder, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SlideOverflow(child: slidingText(folder.name, style: theme.textTheme.titleMedium)),
                Text(
                  tr(
                    '${folder.children.length}개 항목 · 레벨 $levelCount개',
                    "${folder.children.length} ${plural(folder.children.length, 'item')} · $levelCount ${plural(levelCount, 'level')}",
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PackDownloadButton(
            packs: packs,
            scope: folder.id,
            label: folder.name,
            items: toDownload,
            idleText: tr('폴더 받기 (${toDownload.length}개)', 'Download folder (${toDownload.length})'),
            filled: false,
            doneText: levelCount == 0 ? tr('빈 폴더', 'Empty folder') : tr('모두 받음', 'All downloaded'),
          ),
        ],
      ),
    );
  }
}

/// 여러 레벨을 받기 전에 어디에 몇 개를 받는지 알려준다.
Future<void> _confirmDownload(
  BuildContext context,
  PacksController packs,
  Object scope,
  String label,
  List<PackDownloadItem> items,
) async {
  final folder = items.first.folder;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr("'$label' 받기", "Download '$label'")),
      content: Text(
        tr(
          '아직 받지 않은 레벨 ${items.length}개를 차례로 받습니다.\n'
              "레벨 관리의 '${folder.split('/').first}' 폴더 안에 팩과 같은 폴더 구조로 저장돼요.\n"
              '이미 받은 레벨은 건너뛰고 원래 자리에 그대로 둡니다.',
          "Downloads the ${items.length} ${plural(items.length, 'level')} you don't have yet, one by one.\n"
              "They're saved in the '${folder.split('/').first}' folder of the library, in the same folder layout as the pack.\n"
              'Levels you already have are skipped and stay where they are.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('취소', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('받기', 'Download'))),
      ],
    ),
  );
  if (ok ?? false) await packs.startDownload(scope, label, items);
}

/// 팩·폴더 받기 버튼. 받는 동안에는 레벨 목록의 받기 버튼처럼 그 자리에서 진행률로 바뀐다.
class _PackDownloadButton extends StatelessWidget {
  const _PackDownloadButton({
    required this.packs,
    required this.scope,
    required this.label,
    required this.items,
    required this.idleText,
    required this.filled,
    this.doneText,
  });

  /// 버튼과 진행률이 같은 폭을 써서 바뀔 때 옆 요소가 밀리지 않는다.
  static const width = 200.0;

  final PacksController packs;
  final Object scope;
  final String label;
  final List<PackDownloadItem> items;
  final String idleText;
  final bool filled;

  /// 받을 레벨이 없을 때 적는 말. 없으면 '모두 받음'.
  final String? doneText;

  @override
  Widget build(BuildContext context) {
    final download = packs.download;
    // 팩을 받을 때는 안의 폴더 버튼들도 자기 몫의 진행률로 바뀐다.
    final active = download != null && download.isActiveFor(scope);

    return SizedBox(
      width: width,
      child: FadeSwitcher(
        duration: Motion.fast,
        alignment: Alignment.centerRight,
        child: active ? _progress(context, download) : _button(context),
      ),
    );
  }

  Widget _button(BuildContext context) {
    final onPressed = packs.isDownloading || items.isEmpty
        ? null
        : () => _confirmDownload(context, packs, scope, label, items);
    final text = Text(
      items.isEmpty ? doneText ?? tr('모두 받음', 'All downloaded') : idleText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final icon = Icon(items.isEmpty ? Icons.check : Icons.download, size: 18);

    return filled
        ? FilledButton.icon(key: const ValueKey('button'), onPressed: onPressed, icon: icon, label: text)
        : OutlinedButton.icon(key: const ValueKey('button'), onPressed: onPressed, icon: icon, label: text);
  }

  Widget _progress(BuildContext context, PackDownload download) {
    final theme = Theme.of(context);
    final job = download.currentLevelId == null ? null : AppScope.of(context).installs.jobFor(download.currentLevelId!);

    return ListenableBuilder(
      key: const ValueKey('progress'),
      listenable: Listenable.merge([download, ?job]),
      builder: (context, _) {
        // 이 버튼이 맡은 레벨만 센다 (폴더 버튼이면 그 폴더 안의 것).
        final ids = download.levelsFor(scope) ?? const <int>[];
        final total = max(1, ids.length);
        final finished = ids.where(download.finishedIds.contains).length;
        final failedCount = ids.where(download.failedIds.contains).length;
        final isCurrent = ids.contains(download.currentLevelId);

        // 지금 받는 레벨의 진행률까지 더해서 막대가 계단처럼 뛰지 않게 한다.
        final current = isCurrent ? (job?.fraction ?? 0) : 0.0;
        final value = ((finished + current) / total).clamp(0.0, 1.0);
        final failed = failedCount > 0 ? tr(' · 실패 $failedCount', ' · $failedCount failed') : '';
        final state = isCurrent ? job?.shortText ?? tr('준비 중', 'Preparing') : tr('대기 중', 'Waiting');

        return Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: value),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, value, _) => LinearProgressIndicator(value: value),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    download.cancelled ? tr('멈추는 중', 'Stopping') : '$finished/${ids.length}$failed · $state',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('멈추기', 'Stop'),
              visualDensity: VisualDensity.compact,
              onPressed: download.cancelled ? null : packs.cancelDownload,
              icon: const Icon(Icons.close),
            ),
          ],
        );
      },
    );
  }
}

class _DetailFooter extends StatelessWidget {
  const _DetailFooter({required this.packs});

  final PacksController packs;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (packs.detailError case final error?) {
      content = Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: const Icon(Icons.cloud_off),
          title: tr('팩 내용을 불러오지 못했어요', "Couldn't load the pack contents"),
          message: error,
          action: FilledButton(onPressed: packs.reloadDetail, child: Text(tr('다시 시도', 'Retry'))),
        ),
      );
    } else if (packs.isLoadingDetail) {
      content = const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (packs.detail?.items.isEmpty ?? false) {
      content = Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(icon: const Icon(Icons.inventory_2_outlined), title: tr('비어 있는 팩이에요', 'This pack is empty')),
      );
    } else {
      content = const SizedBox(key: ValueKey('none'), width: double.infinity);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: FadeSwitcher(alignment: Alignment.topCenter, child: content),
    );
  }
}

/// 고정된 팩 표시. 똑바로 세우면 작은 크기에서 글자처럼 보여서 웹처럼 비스듬히 눕힌다.
class _PinIcon extends StatelessWidget {
  const _PinIcon(this.icon, {this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: 0.6,
    child: Icon(icon, size: size, color: color),
  );
}

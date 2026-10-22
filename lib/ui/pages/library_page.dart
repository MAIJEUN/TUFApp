import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/library_organizer.dart';
import '../widgets/common.dart';
import '../widgets/hover_tip.dart';
import '../widgets/motion.dart';
import '../widgets/slide_overflow.dart';
import '../widgets/smooth_scroll.dart';

/// 가운데 정렬된 최대 폭 안에서 내용이 항상 가로를 꽉 채우게 한다.
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

/// 받은 레벨을 폴더째 관리하는 화면. 윈도우 탐색기처럼 다룰 수 있다.
///
/// - 한 번 누르면 선택(Ctrl 토글, Shift 범위), 두 번 누르면 열기
/// - 끌어서 폴더나 위 경로로 옮기기
/// - 오른쪽 클릭 메뉴, F2(이름 변경) / Delete(삭제) / Backspace(위로) / Ctrl+A(모두 선택) / Esc(선택 해제)
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _scroll = SmoothScrollController();
  final _focus = FocusNode(debugLabel: 'library');

  /// 이미 보여준 항목. 새로 생긴 것만 나타나는 애니메이션을 준다.
  final _shownPaths = <String>{};

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(LibraryController library, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final selected = library.selectedEntries;
    final control = HardwareKeyboard.instance.isControlPressed;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        library.clearSelection();
      case LogicalKeyboardKey.backspace:
        library.goUp();
      case LogicalKeyboardKey.keyA when control:
        library.selectAll();
      case LogicalKeyboardKey.f2 when selected.length == 1:
        _rename(context, library, selected.single);
      case LogicalKeyboardKey.delete when selected.isNotEmpty:
        _deleteMany(context, library, selected);
      case LogicalKeyboardKey.enter when selected.length == 1:
        _open(library, selected.single);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _open(LibraryController library, LibraryEntry entry) {
    if (entry is FolderEntry) {
      library.openPath(entry.relativePath);
    } else {
      library.openFolderPath(entry.relativePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final library = app.library;

    return ListenableBuilder(
      // app.levels는 검색할 때마다 알림이 와서 여기서는 듣지 않는다.
      listenable: Listenable.merge([library, app.installs]),
      builder: (context, _) {
        final entries = library.entries;
        final firstShow = _shownPaths.isEmpty;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _shownPaths
            ..clear()
            ..addAll(entries.map((entry) => entry.relativePath));
        });

        return Focus(
          focusNode: _focus,
          onKeyEvent: (node, event) => _onKey(library, event),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // 빈 곳을 누르면 선택을 풀고 키보드 입력을 이 화면이 받는다.
            onTap: () {
              _focus.requestFocus();
              library.clearSelection();
            },
            onSecondaryTapUp: (details) => _showFolderMenu(context, library, details.globalPosition),
            child: Stack(
              children: [
                SmoothScrollbar(
                  controller: _scroll,
                  builder: (context, behavior) => CustomScrollView(
                    controller: _scroll,
                    scrollBehavior: behavior,
                    slivers: [
                      _section(
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: _Header(library: library),
                        ),
                      ),
                      _section(
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _Toolbar(library: library),
                        ),
                      ),
                      _section(const SizedBox(height: 12)),
                      _section(
                        Reveal(
                          visible: library.contents?.isEmpty ?? false,
                          child: _EmptyFolder(
                            atRoot: library.currentPath.isEmpty,
                            onBrowse: () => app.setPage(AppPage.levels),
                            onCreateFolder: () => _createFolder(context, library),
                          ),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _constrain(
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Appear(
                                key: ValueKey(entry.relativePath),
                                animate: !_shownPaths.contains(entry.relativePath),
                                delay: firstShow ? Duration(milliseconds: 30 * index.clamp(0, 10)) : Duration.zero,
                                child: _EntryRow(
                                  entry: entry,
                                  library: library,
                                  focus: _focus,
                                  onOpen: () => _open(library, entry),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // 떠 있는 선택 막대에 마지막 항목이 가리지 않도록 넉넉히 둔다.
                      _section(const SizedBox(height: 88)),
                    ],
                  ),
                ),
                // 목록 위에 떠 있어서 나타나고 사라져도 항목이 밀리지 않는다.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: ValueListenableBuilder(
                    valueListenable: library.selectionRevision,
                    builder: (context, _, _) => _FloatingSelectionBar(
                      visible: library.selection.isNotEmpty,
                      child: _constrain(_SelectionBar(library: library)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── 항목 한 줄 ─────────────────────────

/// 선택·드래그·오른쪽 클릭을 붙인 한 줄. 폴더면 여기에 떨어뜨려 옮길 수도 있다.
class _EntryRow extends StatefulWidget {
  const _EntryRow({required this.entry, required this.library, required this.focus, required this.onOpen});

  final LibraryEntry entry;
  final LibraryController library;
  final FocusNode focus;
  final VoidCallback onOpen;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _dropTarget = false;

  bool get _selected => widget.library.selection.contains(widget.entry.relativePath);

  /// 마지막으로 그렸을 때의 선택 상태.
  late bool _wasSelected = _selected;

  @override
  void initState() {
    super.initState();
    widget.library.selectionRevision.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(_EntryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      oldWidget.library.selectionRevision.removeListener(_onSelectionChanged);
      widget.library.selectionRevision.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.library.selectionRevision.removeListener(_onSelectionChanged);
    super.dispose();
  }

  /// 선택이 바뀌어도 화면 전체를 다시 그리지 않고, 상태가 바뀐 줄만 다시 그린다.
  /// 선택된 줄은 끌고 갈 묶음이 달라지므로 함께 다시 그린다.
  void _onSelectionChanged() {
    final selected = _selected;
    if (selected == _wasSelected && !selected) return;
    setState(() {});
  }

  /// 이미 골라 둔 여러 항목 중 하나를 눌렀을 때, 끌지 않고 떼면 그것 하나만 남긴다.
  bool _collapseOnTap = false;

  void _handleTap() {
    widget.focus.requestFocus();
    widget.library.select(
      widget.entry,
      toggle: HardwareKeyboard.instance.isControlPressed,
      range: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  /// 탐색기처럼 누르는 순간 고른다.
  /// (onTap은 두 번 누르기인지 확인하느라 한참 늦게 불린다.)
  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    final modified = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
    // 골라 둔 묶음을 그대로 끌고 갈 수 있게, 묶음 안을 누르면 뗄 때까지 기다린다.
    _collapseOnTap = _selected && !modified;
    if (_collapseOnTap) {
      widget.focus.requestFocus();
      return;
    }
    _handleTap();
  }

  void _handleDelayedTap() {
    if (!_collapseOnTap) return;
    _collapseOnTap = false;
    widget.library.select(widget.entry);
  }

  /// 폴더에만 떨어뜨릴 수 있고, 자기 자신이나 이미 그 안에 있는 항목은 받지 않는다.
  bool _accepts(List<LibraryEntry> dragged) {
    final entry = widget.entry;
    if (entry is! FolderEntry) return false;
    return dragged.every(
      (item) =>
          item.relativePath != entry.relativePath &&
          !entry.relativePath.startsWith('${item.relativePath}/') &&
          !item.relativePath.startsWith('${entry.relativePath}/'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _wasSelected = _selected;
    final row = Listener(
      onPointerDown: _handlePointerDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleDelayedTap,
        onDoubleTap: () {
          _collapseOnTap = false;
          widget.onOpen();
        },
        onSecondaryTapUp: (details) {
          if (!_selected) _handleTap();
          _showEntryMenu(context, widget.library, widget.entry, details.globalPosition);
        },
        child: _EntryCard(entry: widget.entry, selected: selected, highlighted: _dropTarget, library: widget.library),
      ),
    );

    final draggable = Draggable<List<LibraryEntry>>(
      data: widget.library.dragGroupFor(widget.entry),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(entries: widget.library.dragGroupFor(widget.entry)),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );

    if (widget.entry is! FolderEntry) return draggable;

    return DragTarget<List<LibraryEntry>>(
      onWillAcceptWithDetails: (details) {
        final ok = _accepts(details.data);
        if (ok && !_dropTarget) setState(() => _dropTarget = true);
        return ok;
      },
      onLeave: (_) => setState(() => _dropTarget = false),
      onAcceptWithDetails: (details) {
        setState(() => _dropTarget = false);
        widget.library.moveEntries(details.data, widget.entry.relativePath);
      },
      builder: (context, candidate, rejected) => draggable,
    );
  }
}

/// 끌고 다닐 때 마우스를 따라다니는 작은 표시.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.entries});

  final List<LibraryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = entries.length == 1
        ? entries.single.name
        : tr('${entries.length}개 항목', "${entries.length} ${plural(entries.length, 'item')}");

    return Transform.translate(
      offset: const Offset(12, 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drive_file_move_outline, size: 18, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 실제로 그려지는 카드. 선택되면 테두리와 배경이 바뀌고, 드롭 대상이면 강조된다.
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.selected, required this.highlighted, required this.library});

  final LibraryEntry entry;
  final bool selected;
  final bool highlighted;
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = switch (entry) {
      FolderEntry() => _FolderContent(folder: entry as FolderEntry),
      LevelEntry() => _LevelContent(entry: entry as LevelEntry),
      ExternalLevelEntry() => _ExternalLevelContent(entry: entry as ExternalLevelEntry),
    };

    return AnimatedContainer(
      duration: Motion.fast,
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.secondaryContainer
            : selected
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted
              ? colors.secondary
              : selected
              ? colors.primary
              : colors.outlineVariant.withValues(alpha: 0),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: content),
          _EntryMenuButton(entry: entry, library: library),
        ],
      ),
    );
  }
}

class _FolderContent extends StatelessWidget {
  const _FolderContent({required this.folder});

  final FolderEntry folder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = folder.isEmpty
        ? tr('비어 있음', 'Empty')
        : [
            if (folder.folderCount > 0)
              tr(
                '폴더 ${formatNumber(folder.folderCount)}개',
                "${formatNumber(folder.folderCount)} ${plural(folder.folderCount, 'folder')}",
              ),
            if (folder.levelCount > 0)
              tr(
                '레벨 ${formatNumber(folder.levelCount)}개',
                "${formatNumber(folder.levelCount)} ${plural(folder.levelCount, 'level')}",
              ),
          ].join('  ·  ');

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // 팩째 받은 폴더는 팩 아이콘으로 보여준다.
          if (folder.iconUrl case final icon?)
            SizedBox.square(
              dimension: 36,
              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: NetworkIcon(icon, size: 36)),
            )
          else
            Icon(Icons.folder, size: 36, color: theme.colorScheme.secondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  child: SlideOverflow(child: slidingText(folder.name, style: theme.textTheme.titleMedium)),
                ),
                Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExternalLevelContent extends StatelessWidget {
  const _ExternalLevelContent({required this.entry});

  final ExternalLevelEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Icon(Icons.music_note_outlined, size: 36, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  child: SlideOverflow(child: slidingText(entry.name, style: theme.textTheme.titleMedium)),
                ),
                Text(
                  tr('직접 넣은 레벨 (앱 목록에는 없어요)', "Added manually (not in the app's list)"),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelContent extends StatelessWidget {
  const _LevelContent({required this.entry});

  final LevelEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppScope.of(context);
    final item = entry.level;
    final update = app.library.updateFor(item.levelId);
    final job = app.installs.jobFor(item.levelId);
    final difficulty = app.difficultyNamed(item.difficulty);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Row(
      children: [
        HoverTip(
          message: item.difficulty ?? '?',
          // 난이도 목록이 아직 안 왔을 수 있다. 오면 아이콘만 다시 그린다.
          child: difficulty != null
              ? NetworkIcon(difficulty.icon, size: 44)
              : ListenableBuilder(
                  listenable: app.levels,
                  builder: (context, _) => NetworkIcon(app.difficultyNamed(item.difficulty)?.icon, size: 44),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: SizedBox(
                      height: 24,
                      child: SlideOverflow(child: slidingText(item.song, style: theme.textTheme.titleMedium)),
                    ),
                  ),
                  AnimatedSize(
                    duration: Motion.medium,
                    curve: Motion.curve,
                    child: update != null
                        ? Appear(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Chip(
                                label: Text(tr('업데이트 있음', 'Update available')),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              SizedBox(
                height: 20,
                child: SlideOverflow(
                  child: slidingText(
                    [
                      item.artist,
                      item.creator,
                      '#${item.levelId}',
                    ].whereType<String>().where((s) => s.isNotEmpty).join('  ·  '),
                    style: mutedStyle,
                  ),
                ),
              ),
              Text(
                tr(
                  '${formatBytes(item.sizeBytes)}  ·  ${_formatDate(item.installedAt)}에 받음',
                  '${formatBytes(item.sizeBytes)}  ·  downloaded ${_formatDate(item.installedAt)}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.curve,
          child: FadeSwitcher(
            scale: true,
            alignment: Alignment.centerRight,
            child: job != null
                ? SizedBox(
                    key: const ValueKey('job'),
                    width: 160,
                    child: JobProgressIndicator(job: job),
                  )
                : update != null
                ? FilledButton.tonal(
                    key: const ValueKey('update'),
                    onPressed: () => app.installs.install(update),
                    child: Text(tr('업데이트', 'Update')),
                  )
                : const SizedBox.shrink(key: ValueKey('none')),
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _EntryMenuButton extends StatelessWidget {
  const _EntryMenuButton({required this.entry, required this.library});

  final LibraryEntry entry;
  final LibraryController library;

  @override
  Widget build(BuildContext context) => HoverTip(
    message: tr('더 보기', 'More'),
    child: Builder(
      builder: (context) => IconButton(
        onPressed: () {
          final box = context.findRenderObject() as RenderBox?;
          final position = box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
          _showEntryMenu(context, library, entry, position);
        },
        icon: const Icon(Icons.more_vert),
      ),
    ),
  );
}

// ───────────────────────── 머리말 / 도구 모음 ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = library.installedCount;
    final checking = library.isCheckingUpdates;
    final summary = count == 0
        ? tr(
            '받아 둔 레벨을 폴더로 정리하고 업데이트를 확인할 수 있어요.',
            'Organize your downloaded levels into folders and check for updates.',
          )
        : tr(
            '레벨 ${formatNumber(count)}개  ·  ${formatBytes(library.totalSize)}',
            "${formatNumber(count)} ${plural(count, 'level')}  ·  ${formatBytes(library.totalSize)}",
          );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('레벨 관리', 'Library'), style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              FadeSwitcher(
                alignment: Alignment.centerLeft,
                child: Text(
                  summary,
                  key: ValueKey(summary),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.curve,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: checking || count == 0 ? null : library.checkUpdates,
                icon: FadeSwitcher(
                  duration: Motion.fast,
                  child: checking
                      ? const SizedBox(
                          key: ValueKey('checking'),
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, key: ValueKey('idle')),
                ),
                label: Text(checking ? tr('확인 중...', 'Checking...') : tr('업데이트 확인', 'Check for updates')),
              ),
              if (library.updateCount > 0) ...[
                const SizedBox(width: 8),
                Appear(
                  child: FilledButton(
                    onPressed: library.updateAll,
                    child: Text(tr('모두 업데이트 (${library.updateCount})', 'Update all (${library.updateCount})')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 위로 가기, 현재 위치, 정렬, 새 폴더. 경로에도 끌어다 놓을 수 있다.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crumbs = library.breadcrumb;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('위로 (Backspace)', 'Up (Backspace)'),
              onPressed: library.currentPath.isEmpty ? null : library.goUp,
              icon: const Icon(Icons.arrow_upward),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SizedBox(
                height: 32,
                child: SlideOverflow(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (index, crumb) in crumbs.indexed) ...[
                        if (index > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        _CrumbTarget(
                          library: library,
                          path: crumb.$2,
                          isCurrent: index == crumbs.length - 1,
                          label: crumb.$1,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            MenuAnchor(
              menuChildren: [
                for (final entry in librarySortLabels.entries)
                  MenuItemButton(
                    leadingIcon: Icon(library.sort == entry.key ? Icons.check : null),
                    onPressed: () => library.setSort(entry.key),
                    child: Text(entry.value),
                  ),
              ],
              builder: (context, controller, _) => OutlinedButton.icon(
                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.sort),
                label: Text(librarySortLabels[library.sort]!),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _createFolder(context, library),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(tr('새 폴더', 'New folder')),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: tr('탐색기에서 열기', 'Open in Explorer'),
              onPressed: library.openFolderPath,
              icon: const Icon(Icons.open_in_new),
            ),
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.drive_file_move_outline),
                  onPressed: library.changeFolder,
                  child: Text(tr('라이브러리 폴더 변경', 'Change library folder')),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.refresh),
                  onPressed: library.refreshContents,
                  child: Text(tr('새로 고침', 'Refresh')),
                ),
              ],
              builder: (context, controller, _) => IconButton(
                tooltip: tr('더 보기', 'More'),
                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.more_vert),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 경로 조각 하나. 여기에 끌어다 놓으면 그 폴더로 옮긴다.
class _CrumbTarget extends StatefulWidget {
  const _CrumbTarget({required this.library, required this.path, required this.isCurrent, required this.label});

  final LibraryController library;
  final String path;
  final bool isCurrent;
  final String label;

  @override
  State<_CrumbTarget> createState() => _CrumbTargetState();
}

class _CrumbTargetState extends State<_CrumbTarget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DragTarget<List<LibraryEntry>>(
      onWillAcceptWithDetails: (details) {
        // 이미 그 폴더에 있는 항목은 받지 않는다.
        final ok = details.data.every((entry) {
          final index = entry.relativePath.lastIndexOf('/');
          final parent = index < 0 ? '' : entry.relativePath.substring(0, index);
          return parent != widget.path && !widget.path.startsWith('${entry.relativePath}/');
        });
        if (ok && !_hovered) setState(() => _hovered = true);
        return ok;
      },
      onLeave: (_) => setState(() => _hovered = false),
      onAcceptWithDetails: (details) {
        setState(() => _hovered = false);
        widget.library.moveEntries(details.data, widget.path);
      },
      builder: (context, candidate, rejected) => AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          color: _hovered ? theme.colorScheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextButton(
          onPressed: widget.isCurrent ? null : () => widget.library.openPath(widget.path),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            disabledForegroundColor: theme.colorScheme.onSurface,
          ),
          child: Text(widget.label, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}

/// 아래에서 떠오르는 선택 막대. 목록 위에 겹쳐 그려서 항목 위치를 바꾸지 않는다.
class _FloatingSelectionBar extends StatelessWidget {
  const _FloatingSelectionBar({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 0.5),
      duration: Motion.fast,
      curve: Motion.curve,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.fast,
        curve: Motion.curve,
        // 막대의 빈 곳을 눌러도 뒤의 '빈 곳 누르면 선택 해제'가 불리지 않게 막는다.
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: child),
      ),
    ),
  );
}

/// 여러 개를 골랐을 때 나오는 막대.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = library.selectedEntries;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shadowColor: Colors.black,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('${selected.length}개 선택됨', '${selected.length} selected'),
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton.icon(
              onPressed: selected.isEmpty ? null : () => _moveMany(context, library, selected),
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text(tr('이동', 'Move')),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: selected.isEmpty ? null : () => _deleteMany(context, library, selected),
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('삭제', 'Delete')),
            ),
            const SizedBox(width: 4),
            TextButton(onPressed: library.clearSelection, child: Text(tr('선택 해제', 'Deselect'))),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 메뉴 ─────────────────────────

Future<void> _showEntryMenu(
  BuildContext context,
  LibraryController library,
  LibraryEntry entry,
  Offset position,
) async {
  final selected = library.selectedEntries;
  final many = selected.length > 1 && library.selection.contains(entry.relativePath);
  final targets = many ? selected : [entry];

  final action = await _showMenuAt(context, position, [
    if (!many)
      PopupMenuItem(
        value: 'open',
        child: ListTile(
          leading: Icon(entry is FolderEntry ? Icons.folder_open : Icons.open_in_new),
          title: Text(entry is FolderEntry ? tr('열기', 'Open') : tr('탐색기에서 열기', 'Open in Explorer')),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (!many)
      PopupMenuItem(
        value: 'rename',
        child: ListTile(
          leading: const Icon(Icons.drive_file_rename_outline),
          title: Text(tr('이름 변경', 'Rename')),
          subtitle: const Text('F2'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    PopupMenuItem(
      value: 'move',
      child: ListTile(
        leading: const Icon(Icons.drive_file_move_outline),
        title: Text(tr('폴더로 이동', 'Move to folder')),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'delete',
      child: ListTile(
        leading: const Icon(Icons.delete_outline),
        title: Text(tr('삭제', 'Delete')),
        subtitle: const Text('Delete'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
  ]);
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'open':
      entry is FolderEntry ? library.openPath(entry.relativePath) : library.openFolderPath(entry.relativePath);
    case 'rename':
      await _rename(context, library, entry);
    case 'move':
      await _moveMany(context, library, targets);
    case 'delete':
      await _deleteMany(context, library, targets);
  }
}

Future<void> _showFolderMenu(BuildContext context, LibraryController library, Offset position) async {
  final action = await _showMenuAt(context, position, [
    PopupMenuItem(
      value: 'new',
      child: ListTile(
        leading: const Icon(Icons.create_new_folder_outlined),
        title: Text(tr('새 폴더', 'New folder')),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'selectAll',
      child: ListTile(
        leading: const Icon(Icons.select_all),
        title: Text(tr('모두 선택', 'Select all')),
        subtitle: const Text('Ctrl+A'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'explorer',
      child: ListTile(
        leading: const Icon(Icons.open_in_new),
        title: Text(tr('탐색기에서 열기', 'Open in Explorer')),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'refresh',
      child: ListTile(
        leading: const Icon(Icons.refresh),
        title: Text(tr('새로 고침', 'Refresh')),
        contentPadding: EdgeInsets.zero,
      ),
    ),
  ]);
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'new':
      await _createFolder(context, library);
    case 'selectAll':
      library.selectAll();
    case 'explorer':
      await library.openFolderPath();
    case 'refresh':
      await library.refreshContents();
  }
}

Future<String?> _showMenuAt(BuildContext context, Offset position, List<PopupMenuEntry<String>> items) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final size = overlay?.size ?? MediaQuery.sizeOf(context);

  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, size.width - position.dx, size.height - position.dy),
    items: items,
  );
}

// ───────────────────────── 대화상자 ─────────────────────────

Future<void> _createFolder(BuildContext context, LibraryController library) async {
  final name = await _askName(
    context,
    title: tr('새 폴더', 'New folder'),
    label: tr('폴더 이름', 'Folder name'),
    confirm: tr('만들기', 'Create'),
  );
  if (name != null) await library.createFolder(name);
}

Future<void> _rename(BuildContext context, LibraryController library, LibraryEntry entry) async {
  final name = await _askName(
    context,
    title: tr('이름 변경', 'Rename'),
    label: tr('새 이름', 'New name'),
    confirm: tr('바꾸기', 'Rename'),
    initial: entry.name,
  );
  if (name != null) await library.renameEntry(entry, name);
}

Future<void> _moveMany(BuildContext context, LibraryController library, List<LibraryEntry> entries) async {
  if (entries.isEmpty) return;

  final target = await showDialog<String>(
    context: context,
    builder: (context) => _MoveDialog(entries: entries, library: library),
  );
  if (target != null) await library.moveEntries(entries, target);
}

Future<void> _deleteMany(BuildContext context, LibraryController library, List<LibraryEntry> entries) async {
  if (entries.isEmpty) return;
  final colors = Theme.of(context).colorScheme;

  final title = entries.length == 1
      ? tr('"${entries.single.name}"을(를) 삭제할까요?', 'Delete "${entries.single.name}"?')
      : tr('${entries.length}개를 삭제할까요?', "Delete ${entries.length} ${plural(entries.length, 'item')}?");
  final levelsInside = entries.whereType<FolderEntry>().fold(0, (sum, folder) => sum + folder.levelCount);
  final message = levelsInside > 0
      ? tr(
          '폴더 안의 레벨 ${formatNumber(levelsInside)}개를 포함해 디스크에서 지워집니다.',
          "This deletes it from disk, including ${formatNumber(levelsInside)} ${plural(levelsInside, 'level')} inside.",
        )
      : tr('디스크에서 지워집니다.', 'This deletes it from disk.');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('취소', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('삭제', 'Delete')),
        ),
      ],
    ),
  );
  if (confirmed == true) await library.deleteEntries(entries);
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => _NameDialog(title: title, label: label, confirm: confirm, initial: initial),
);

/// 이름을 입력받는 창. 입력 칸은 창이 닫히는 애니메이션이 끝날 때까지 쓰이므로,
/// 창이 완전히 사라질 때(State.dispose) 정리한다.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label, required this.confirm, required this.initial});

  final String title;
  final String label;
  final String confirm;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('취소', 'Cancel'))),
      FilledButton(onPressed: _submit, child: Text(widget.confirm)),
    ],
  );
}

/// 옮길 폴더를 직접 들어가며 고른다. 자기 자신과 그 안쪽으로는 들어갈 수 없다.
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.entries, required this.library});

  final List<LibraryEntry> entries;
  final LibraryController library;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  String _path = '';
  FolderContents? _contents;

  @override
  void initState() {
    super.initState();
    _path = _parentOf(widget.entries.first.relativePath);
    _load();
  }

  static String _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  Future<void> _load() async {
    final contents = await widget.library.browse(_path);
    if (mounted) setState(() => _contents = contents);
  }

  void _enter(String path) {
    setState(() {
      _path = path;
      _contents = null;
    });
    _load();
  }

  bool _isSelfOrInside(String path) =>
      widget.entries.any((entry) => path == entry.relativePath || path.startsWith('${entry.relativePath}/'));

  bool get _canMoveHere =>
      !_isSelfOrInside(_path) && widget.entries.any((entry) => _parentOf(entry.relativePath) != _path);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contents = _contents;
    final title = widget.entries.length == 1
        ? tr('"${widget.entries.single.name}" 옮기기', 'Move "${widget.entries.single.name}"')
        : tr('${widget.entries.length}개 옮기기', "Move ${widget.entries.length} ${plural(widget.entries.length, 'item')}");

    final crumbs = <(String, String)>[(tr('루트', 'Root'), '')];
    var walked = '';
    for (final part in _path.split('/').where((part) => part.isNotEmpty)) {
      walked = walked.isEmpty ? part : '$walked/$part';
      crumbs.add((part, walked));
    }

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 32,
              child: SlideOverflow(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, crumb) in crumbs.indexed) ...[
                      if (index > 0) Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      TextButton(
                        onPressed: index == crumbs.length - 1 ? null : () => _enter(crumb.$2),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          disabledForegroundColor: theme.colorScheme.onSurface,
                        ),
                        child: Text(crumb.$1, maxLines: 1, softWrap: false),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: switch (contents) {
                null => const Center(child: CircularProgressIndicator()),
                FolderContents(folders: []) => Center(
                  child: Text(
                    tr('하위 폴더가 없어요.', 'No subfolders.'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                final value => ListView(
                  children: [
                    for (final folder in value.folders)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(folder.name),
                        enabled: !_isSelfOrInside(folder.relativePath),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _enter(folder.relativePath),
                      ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('취소', 'Cancel'))),
        FilledButton(
          onPressed: _canMoveHere ? () => Navigator.of(context).pop(_path) : null,
          child: Text(_path.isEmpty ? tr('루트로 옮기기', 'Move to root') : tr('여기로 옮기기', 'Move here')),
        ),
      ],
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder({required this.atRoot, required this.onBrowse, required this.onCreateFolder});

  final bool atRoot;
  final VoidCallback onBrowse;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: EmptyState(
          icon: Icon(atRoot ? Icons.download_outlined : Icons.folder_open_outlined),
          title: atRoot ? tr('아직 받은 레벨이 없어요', 'No downloaded levels yet') : tr('빈 폴더예요', 'This folder is empty'),
          message: atRoot
              ? tr('레벨 찾기에서 마음에 드는 레벨을 받아보세요.', 'Find levels you like in Levels and download them.')
              : tr('레벨을 끌어다 놓거나, 안에 폴더를 더 만들 수 있어요.', 'Drag levels here, or create more folders inside.'),
          action: atRoot
              ? FilledButton(onPressed: onBrowse, child: Text(tr('레벨 둘러보기', 'Browse levels')))
              : OutlinedButton.icon(
                  onPressed: onCreateFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(tr('새 폴더', 'New folder')),
                ),
        ),
      ),
    ),
  );
}

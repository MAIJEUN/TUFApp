import 'package:flutter/material.dart';

import '../app/controllers.dart';
import '../core/l10n.dart';
import 'pages/clears_page.dart';
import 'pages/creators_page.dart';
import 'pages/leaderboard_page.dart';
import 'pages/levels_page.dart';
import 'pages/library_page.dart';
import 'pages/packs_page.dart';
import 'widgets/motion.dart';

/// 상단 AppBar + 탭. 페이지를 오가도 스크롤 위치와 입력이 유지되도록 모든 페이지를 살려 두고 겹쳐서 전환한다.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: AppPage.values.length, vsync: this);
  AppController? _app;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (!identical(app, _app)) {
      _app?.removeListener(_syncTabWithPage);
      _app = app..addListener(_syncTabWithPage);
      _tabs.index = app.page.index;
    }
  }

  @override
  void dispose() {
    _app?.removeListener(_syncTabWithPage);
    _tabs.dispose();
    super.dispose();
  }

  /// 탭을 누르면 페이지를 바꾼다.
  void _onTabChanged() => _app?.setPage(AppPage.values[_tabs.index]);

  /// 다른 곳에서 페이지를 바꾸면(예: '레벨 둘러보기' 버튼) 탭도 따라간다.
  void _syncTabWithPage() {
    final index = _app!.page.index;
    if (_tabs.index != index) _tabs.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TUFApp'),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge([app, app.installs]),
            builder: (context, _) => Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: FadeSwitcher(
                    alignment: Alignment.centerRight,
                    child: Tooltip(
                      key: ValueKey(app.status),
                      message: app.status,
                      child: Text(
                        app.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.medium,
                  curve: Motion.curve,
                  child: FadeSwitcher(
                    scale: true,
                    child: app.installs.activeCount > 0
                        ? Padding(
                            key: const ValueKey('downloading'),
                            padding: const EdgeInsets.only(left: 16),
                            child: Tooltip(
                              message: tr('받는 중', 'Downloading'),
                              child: Badge(
                                label: Text('${app.installs.activeCount}'),
                                child: const Icon(Icons.downloading),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('idle')),
                  ),
                ),
                const SizedBox(width: 8),
                _LanguageMenu(app: app),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [const Icon(Icons.search, size: 18), const SizedBox(width: 8), Text(tr('레벨 찾기', 'Levels'))],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(tr('레벨 팩', 'Packs')),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flag_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(tr('클리어', 'Passes')),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.leaderboard_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(tr('리더보드', 'Leaderboard')),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.handyman_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(tr('제작자', 'Creators')),
                ],
              ),
            ),
            Tab(
              child: ListenableBuilder(
                listenable: app.library,
                builder: (context, _) => AnimatedSize(
                  duration: Motion.medium,
                  curve: Motion.curve,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_done, size: 18),
                      const SizedBox(width: 8),
                      Text(tr('레벨 관리', 'Library')),
                      if (app.library.installedCount > 0) ...[
                        const SizedBox(width: 8),
                        Badge(
                          label: Text('${app.library.installedCount}'),
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          textColor: theme.colorScheme.onSecondaryContainer,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            _PageLayer(active: app.page == AppPage.levels, child: const LevelsPage()),
            _PageLayer(active: app.page == AppPage.packs, child: const PacksPage()),
            _PageLayer(active: app.page == AppPage.clears, child: const ClearsPage()),
            _PageLayer(active: app.page == AppPage.leaderboard, child: const LeaderboardPage()),
            _PageLayer(active: app.page == AppPage.creators, child: const CreatorsPage()),
            _PageLayer(active: app.page == AppPage.library, child: const LibraryPage()),
          ],
        ),
      ),
    );
  }
}

/// 화면 언어 고르기. 시스템 언어를 따르거나 한국어·영어 중 하나로 고정한다.
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final choice = app.languageChoice;
    return PopupMenuButton<AppLanguage?>(
      tooltip: tr('언어', 'Language'),
      icon: const Icon(Icons.translate),
      // null(시스템 언어)도 고를 수 있어야 하므로 onSelected 대신 항목마다 onTap을 쓴다.
      itemBuilder: (context) => [
        for (final (value, label) in [
          (null, tr('시스템 언어 (${AppLanguage.system.nativeName})', 'System (${AppLanguage.system.nativeName})')),
          for (final language in AppLanguage.values) (language, language.nativeName),
        ])
          CheckedPopupMenuItem(
            value: value,
            checked: value == choice,
            onTap: () => app.setLanguage(value),
            child: Text(label),
          ),
      ],
    );
  }
}

/// 보이는 페이지는 흐려졌다 나타나며 살짝 올라온다. 숨은 페이지는 상태를 유지한 채 입력만 막는다.
class _PageLayer extends StatelessWidget {
  const _PageLayer({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !active,
    child: ExcludeFocus(
      excluding: !active,
      // RepaintBoundary: 흐려지는 동안 페이지를 매 프레임 다시 그리지 않고,
      // 미리 그려 둔 그림에 투명도만 입힌다. (움직임까지 넣으면 매번 다시 그려야 해서 뺐다.)
      child: RepaintBoundary(
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: Motion.fast,
          curve: Curves.easeOut,
          // 보이지 않는 페이지의 애니메이션(도는 표시 등)은 멈춰 둔다.
          child: TickerMode(enabled: active, child: child),
        ),
      ),
    ),
  );
}

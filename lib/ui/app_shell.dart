import 'package:flutter/material.dart';

import '../app/controllers.dart';
import '../core/l10n.dart';
import 'app_shortcuts.dart';
import 'pages/clears_page.dart';
import 'pages/creators_page.dart';
import 'pages/leaderboard_page.dart';
import 'pages/levels_page.dart';
import 'pages/library_page.dart';
import 'pages/packs_page.dart';
import 'widgets/motion.dart';

/// App bar and tabs. All pages stay alive and are stacked, so scroll positions and input survive switching tabs.
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

  void _onTabChanged() => _app?.setPage(AppPage.values[_tabs.index]);

  /// Follows page changes made elsewhere (e.g. the "Browse levels" button).
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
            _PageLayer(page: AppPage.levels, active: app.page, child: const LevelsPage()),
            _PageLayer(page: AppPage.packs, active: app.page, child: const PacksPage()),
            _PageLayer(page: AppPage.clears, active: app.page, child: const ClearsPage()),
            _PageLayer(page: AppPage.leaderboard, active: app.page, child: const LeaderboardPage()),
            _PageLayer(page: AppPage.creators, active: app.page, child: const CreatorsPage()),
            _PageLayer(page: AppPage.library, active: app.page, child: const LibraryPage()),
          ],
        ),
      ),
    );
  }
}

/// UI language menu: follow the system language or pin Korean or English.
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final choice = app.languageChoice;
    return PopupMenuButton<AppLanguage?>(
      tooltip: tr('언어', 'Language'),
      icon: const Icon(Icons.translate),
      // onSelected ignores a null value, and null (system language) must be selectable, so each item uses onTap.
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

/// The visible page fades in; hidden pages keep their state but ignore input.
class _PageLayer extends StatelessWidget {
  const _PageLayer({required this.page, required this.active, required this.child});

  final AppPage page;

  /// The page currently shown.
  final AppPage active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final active = page == this.active;
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeFocus(
        excluding: !active,
        // RepaintBoundary: while fading, the page isn't repainted every
        // frame; only the opacity of the cached picture changes.
        // (A slide was dropped because it forces a repaint every frame.)
        child: RepaintBoundary(
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: Motion.fast,
            curve: Curves.easeOut,
            // Pause animations (spinners etc.) on hidden pages.
            child: TickerMode(
              enabled: active,
              child: PageTab(page: page, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

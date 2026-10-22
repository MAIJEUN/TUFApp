import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controllers.dart';
import 'widgets/smooth_scroll.dart';

/// Tracks the route stack for the shortcuts, and records pages closed by going back so "forward" can reopen them.
class AppNavigatorObserver extends NavigatorObserver {
  AppNavigatorObserver(this.history);

  final NavigationHistory history;
  final _routes = <Route<dynamic>>[];

  Route<dynamic>? get top => _routes.lastOrNull;

  /// Whether a dialog or menu is open over the pages. Page shortcuts stay out of its way.
  bool get popupOpen => top is PopupRoute;

  bool _isPage(Route<dynamic>? route) => route != null && route == top && route != _routes.firstOrNull;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    if (route is PageRoute && previousRoute != null) history.clearForward();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route) && route is MaterialPageRoute) {
      final builder = route.builder;
      history.recordBack(() async {
        if (navigator case final navigator?) unawaited(navigator.push(MaterialPageRoute<void>(builder: builder)));
      });
    }
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) _routes[index] = newRoute;
  }
}

/// Marks the subtree of one tab in the app shell, so [PageCommandScope]s know which tab they belong to.
class PageTab extends InheritedWidget {
  const PageTab({super.key, required this.page, required super.child});

  final AppPage page;

  static AppPage? of(BuildContext context) => context.getInheritedWidgetOfExactType<PageTab>()?.page;

  @override
  bool updateShouldNotify(PageTab oldWidget) => page != oldWidget.page;
}

/// What the keyboard shortcuts act on in one page.
class PageCommands {
  const PageCommands({this.scroll, this.refresh, this.searchable = true});

  /// Scrolled by Page Up/Down, Space, Home/End and the arrow keys.
  final SmoothScrollController? scroll;

  /// Run by F5 / Ctrl+R.
  final VoidCallback? refresh;

  /// Whether Ctrl+F may focus the search box registered with [PageCommandScope.searchFocusOf].
  final bool searchable;
}

/// Registers what the shortcuts act on for the page around it. The shortcuts use the scope of the visible page:
/// the topmost route, or in the app shell the active tab. When several match, the most recently built one wins
/// (an open pack over the pack list).
class PageCommandScope extends StatefulWidget {
  const PageCommandScope({super.key, required this.commands, required this.child});

  /// Read when a shortcut fires, so it always reflects the page's current state.
  final PageCommands Function() commands;
  final Widget child;

  /// Focus node for the page's search box; Ctrl+F focuses it and selects its text.
  static FocusNode? searchFocusOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PageCommandData>()?.state._searchFocus;

  @override
  State<PageCommandScope> createState() => _PageCommandScopeState();
}

class _PageCommandScopeState extends State<PageCommandScope> {
  static final _mounted = <_PageCommandScopeState>[];

  final _searchFocus = FocusNode(debugLabel: 'page search');
  Route<dynamic>? _route;
  AppPage? _tab;

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _tab = PageTab.of(context);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _searchFocus.dispose();
    super.dispose();
  }

  void focusSearch() {
    final field = _searchFocus.context;
    if (field == null || !widget.commands().searchable) return;
    _searchFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_searchFocus.hasFocus) return;
      field.findAncestorStateOfType<EditableTextState>()?.selectAll(SelectionChangedCause.keyboard);
    });
  }

  @override
  Widget build(BuildContext context) => _PageCommandData(state: this, child: widget.child);
}

class _PageCommandData extends InheritedWidget {
  const _PageCommandData({required this.state, required super.child});

  final _PageCommandScopeState state;

  @override
  bool updateShouldNotify(_PageCommandData oldWidget) => false;
}

// ───────────────────────── Shortcuts ─────────────────────────

class _BackIntent extends Intent {
  const _BackIntent();
}

class _ForwardIntent extends Intent {
  const _ForwardIntent();
}

class _GoToTabIntent extends Intent {
  const _GoToTabIntent(this.index);

  final int index;
}

class _CycleTabIntent extends Intent {
  const _CycleTabIntent(this.step);

  final int step;
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

enum _ScrollUnit { line, page, edge }

class _ScrollKeyIntent extends Intent {
  const _ScrollKeyIntent(this.unit, {required this.forward});

  final _ScrollUnit unit;
  final bool forward;
}

class _LeaveTextIntent extends Intent {
  const _LeaveTextIntent();
}

class _ZoomIntent extends Intent {
  /// +1 zooms in, -1 zooms out, 0 resets.
  const _ZoomIntent(this.step);

  final int step;
}

class _CallbackAction<T extends Intent> extends Action<T> {
  _CallbackAction(this.run, {this.enabled});

  final void Function(T intent) run;
  final bool Function(T intent)? enabled;

  @override
  bool isEnabled(T intent) => enabled?.call(intent) ?? true;

  @override
  Object? invoke(T intent) {
    run(intent);
    return null;
  }
}

/// Browser-style shortcuts for the whole app, plus UI zoom. Wraps the navigator (MaterialApp.builder).
///
/// - Back / forward: Alt+←/→, the mouse side buttons
/// - Tabs: Ctrl+1–6, Ctrl+Tab / Ctrl+Shift+Tab
/// - Refresh: F5, Ctrl+R; search: Ctrl+F, Ctrl+K; leave a text field: Esc
/// - Scroll: Page Up/Down, Space / Shift+Space, Home/End, ↑/↓
/// - Zoom: Ctrl+= / Ctrl+- / Ctrl+0, Ctrl+wheel
///
/// Keys that edit text (Space, arrows, Home/End, ...) are left to a focused text field, and Space is left to
/// a focused button. Page shortcuts are off while a dialog or menu is open.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.app,
    required this.navigatorKey,
    required this.observer,
    required this.child,
  });

  final AppController app;
  final GlobalKey<NavigatorState> navigatorKey;
  final AppNavigatorObserver observer;
  final Widget child;

  static const _lineStep = 60.0;

  /// Like browsers, a page step keeps a little of the previous page in view.
  static const _pageFraction = 0.85;

  static final _shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): const _BackIntent(),
    const SingleActivator(LogicalKeyboardKey.browserBack): const _BackIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): const _ForwardIntent(),
    const SingleActivator(LogicalKeyboardKey.browserForward): const _ForwardIntent(),
    for (final (index, key) in const [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ].indexed)
      SingleActivator(key, control: true): _GoToTabIntent(index),
    const SingleActivator(LogicalKeyboardKey.tab, control: true): const _CycleTabIntent(1),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): const _CycleTabIntent(-1),
    const SingleActivator(LogicalKeyboardKey.f5): const _RefreshIntent(),
    const SingleActivator(LogicalKeyboardKey.keyR, control: true): const _RefreshIntent(),
    const SingleActivator(LogicalKeyboardKey.browserRefresh): const _RefreshIntent(),
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): const _SearchIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true): const _SearchIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const _LeaveTextIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowDown): const _ScrollKeyIntent(_ScrollUnit.line, forward: true),
    const SingleActivator(LogicalKeyboardKey.arrowUp): const _ScrollKeyIntent(_ScrollUnit.line, forward: false),
    const SingleActivator(LogicalKeyboardKey.pageDown): const _ScrollKeyIntent(_ScrollUnit.page, forward: true),
    const SingleActivator(LogicalKeyboardKey.pageUp): const _ScrollKeyIntent(_ScrollUnit.page, forward: false),
    const SingleActivator(LogicalKeyboardKey.space): const _ScrollKeyIntent(_ScrollUnit.page, forward: true),
    const SingleActivator(LogicalKeyboardKey.space, shift: true): const _ScrollKeyIntent(
      _ScrollUnit.page,
      forward: false,
    ),
    const SingleActivator(LogicalKeyboardKey.end): const _ScrollKeyIntent(_ScrollUnit.edge, forward: true),
    const SingleActivator(LogicalKeyboardKey.home): const _ScrollKeyIntent(_ScrollUnit.edge, forward: false),
    // '+' is Shift+= on most layouts, so accept both, and the numpad keys.
    const SingleActivator(LogicalKeyboardKey.equal, control: true): const _ZoomIntent(1),
    const SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true): const _ZoomIntent(1),
    const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): const _ZoomIntent(1),
    const SingleActivator(LogicalKeyboardKey.minus, control: true): const _ZoomIntent(-1),
    const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): const _ZoomIntent(-1),
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): const _ZoomIntent(0),
    const SingleActivator(LogicalKeyboardKey.numpad0, control: true): const _ZoomIntent(0),
  };

  /// Whether a text field has focus; it keeps the keys it edits with.
  static bool get _editingText =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  /// Whether the focused widget is activated by Space (a button, checkbox, ...).
  static bool get _focusActivates {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    final action = Actions.maybeFind<ActivateIntent>(context);
    return action != null && action.isEnabled(const ActivateIntent());
  }

  /// The commands of the visible page, or null while a dialog or menu is open.
  _PageCommandScopeState? get _page {
    final top = observer.top;
    if (top == null || observer.popupOpen) return null;
    final onShell = !observer._isPage(top);
    for (final scope in _PageCommandScopeState._mounted.reversed) {
      if (scope._route != top) continue;
      if (onShell && scope._tab != app.page) continue;
      return scope;
    }
    return null;
  }

  void _back() {
    final navigator = navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
    } else {
      app.goBackInPage();
    }
  }

  void _goToTab(AppPage page) {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    app.history.clearForward();
    app.setPage(page);
  }

  void _scroll(_ScrollKeyIntent intent) {
    final controller = _page?.widget.commands().scroll;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final sign = intent.forward ? 1 : -1;
    switch (intent.unit) {
      case _ScrollUnit.line:
        controller.glideBy(sign * _lineStep);
      case _ScrollUnit.page:
        controller.glideBy(sign * position.viewportDimension * _pageFraction);
      case _ScrollUnit.edge:
        controller.glideTo(intent.forward ? position.maxScrollExtent : position.minScrollExtent);
    }
  }

  void _zoom(int step) => switch (step) {
    > 0 => app.zoomIn(),
    < 0 => app.zoomOut(),
    _ => app.resetZoom(),
  };

  bool _scrollEnabled(_ScrollKeyIntent intent) {
    if (_editingText) return false;
    if (intent.unit == _ScrollUnit.page && _focusActivates) return false;
    return _page?.widget.commands().scroll?.hasClients ?? false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (observer.popupOpen) return;
    if (event.buttons & kBackMouseButton != 0) _back();
    if (event.buttons & kForwardMouseButton != 0) app.history.goForward();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !HardwareKeyboard.instance.isControlPressed) return;
    if (event.scrollDelta.dy != 0) _zoom(event.scrollDelta.dy < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    bool noPopup(Intent _) => !observer.popupOpen;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerSignal: _onPointerSignal,
      child: Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: {
            _BackIntent: _CallbackAction<_BackIntent>((_) => _back(), enabled: noPopup),
            _ForwardIntent: _CallbackAction<_ForwardIntent>((_) => app.history.goForward(), enabled: noPopup),
            _GoToTabIntent: _CallbackAction<_GoToTabIntent>(
              (intent) => _goToTab(AppPage.values[intent.index]),
              enabled: noPopup,
            ),
            _CycleTabIntent: _CallbackAction<_CycleTabIntent>((intent) {
              final count = AppPage.values.length;
              _goToTab(AppPage.values[(app.page.index + intent.step + count) % count]);
            }, enabled: noPopup),
            _RefreshIntent: _CallbackAction<_RefreshIntent>(
              (_) => _page?.widget.commands().refresh?.call(),
              enabled: (_) => _page?.widget.commands().refresh != null,
            ),
            _SearchIntent: _CallbackAction<_SearchIntent>((_) => _page?.focusSearch(), enabled: (_) => _page != null),
            _ScrollKeyIntent: _CallbackAction<_ScrollKeyIntent>(_scroll, enabled: _scrollEnabled),
            _ZoomIntent: _CallbackAction<_ZoomIntent>((intent) => _zoom(intent.step)),
            // Esc leaves a focused text field. Inside a dialog it is left alone, so Esc still closes the dialog.
            _LeaveTextIntent: _CallbackAction<_LeaveTextIntent>(
              (_) => FocusManager.instance.primaryFocus?.unfocus(),
              enabled: (_) => _editingText && !observer.popupOpen,
            ),
          },
          child: ListenableBuilder(
            listenable: app,
            builder: (context, child) => _Zoom(zoom: app.zoom, child: child!),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Scales the whole UI like page zoom in a browser: lays the app out at size / [zoom] and paints it [zoom] times
/// larger. The device pixel ratio is raised to match, so images are decoded and baked at the final resolution.
/// The structure stays the same at 100%, so changing the zoom never rebuilds the app from scratch.
class _Zoom extends StatelessWidget {
  const _Zoom({required this.zoom, required this.child});

  final double zoom;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final size = constraints.biggest / zoom;
      return MediaQuery(
        data: media.copyWith(
          size: size,
          devicePixelRatio: media.devicePixelRatio * zoom,
          padding: media.padding / zoom,
          viewPadding: media.viewPadding / zoom,
          viewInsets: media.viewInsets / zoom,
        ),
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      );
    },
  );
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/models/pack.dart';
import 'package:tufapp/core/tuf_api_client.dart';
import 'package:tufapp/main.dart';
import 'package:tufapp/ui/app_shortcuts.dart';
import 'package:tufapp/ui/widgets/smooth_scroll.dart';

/// Browser-style shortcuts: back/forward, tabs, refresh, search, scrolling and zoom.
void main() {
  AppController newApp() => AppController(api: TufApiClient(client: MockClient((_) async => http.Response('{}', 404))));

  /// The levels page shows a startup spinner, so pumpAndSettle would never finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool control = false, bool alt = false}) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(key);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  group('앱 전체', () {
    late AppController app;

    Future<NavigatorState> pumpApp(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      app = newApp();
      addTearDown(app.dispose);
      await tester.pumpWidget(TufApp(controller: app));
      await tester.pump(const Duration(milliseconds: 300));
      return tester.state<NavigatorState>(find.byType(Navigator).first);
    }

    testWidgets('Ctrl+숫자와 Ctrl+Tab으로 탭을 바꾼다', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.digit3, control: true);
      expect(app.page, AppPage.clears);
      await press(tester, LogicalKeyboardKey.tab, control: true);
      expect(app.page, AppPage.leaderboard);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.page, AppPage.clears);
    });

    testWidgets('Alt+←/→와 마우스 옆 버튼으로 연 화면을 닫고 다시 연다', (tester) async {
      final navigator = await pumpApp(tester);
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('detail'))));
      await settle(tester);
      expect(find.text('detail'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
      await settle(tester);
      expect(find.text('detail'), findsNothing);

      await press(tester, LogicalKeyboardKey.arrowRight, alt: true);
      await settle(tester);
      expect(find.text('detail'), findsOneWidget, reason: '앞으로 가기로 다시 열린다');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
      await mouse.down(const Offset(700, 450));
      await mouse.up();
      await settle(tester);
      expect(find.text('detail'), findsNothing, reason: '마우스 뒤로 버튼');

      final forward = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kForwardMouseButton);
      await forward.down(const Offset(700, 450));
      await forward.up();
      await settle(tester);
      expect(find.text('detail'), findsOneWidget, reason: '마우스 앞으로 버튼');
    });

    testWidgets('새 화면을 열면 앞으로 갈 곳이 사라진다', (tester) async {
      final navigator = await pumpApp(tester);
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('first'))));
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
      await settle(tester);
      expect(app.history.canGoForward, isTrue);

      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('second'))));
      await settle(tester);
      expect(app.history.canGoForward, isFalse);
    });

    testWidgets('뒤로 가기는 열린 팩을 닫고, 앞으로 가기는 다시 연다', (tester) async {
      await pumpApp(tester);
      final pack = LevelPack.fromJson({'id': 'abc', 'name': 'AWC', 'levelCount': 0});
      app.setPage(AppPage.packs);
      app.packs.open(pack);
      await tester.pump(const Duration(milliseconds: 300));

      await press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
      expect(app.packs.openedPack, isNull);
      await press(tester, LogicalKeyboardKey.arrowRight, alt: true);
      expect(app.packs.openedPack?.id, 'abc');
      await settle(tester);
    });

    testWidgets('Ctrl+=/-/0으로 화면 배율을 바꾼다', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.equal, control: true);
      expect(app.zoom, 1.1);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The UI is laid out at the reduced size.
      expect(MediaQuery.sizeOf(tester.element(find.byType(Scaffold).first)).width, closeTo(1400 / 1.1, 0.5));

      await press(tester, LogicalKeyboardKey.minus, control: true);
      await press(tester, LogicalKeyboardKey.minus, control: true);
      expect(app.zoom, 0.9);
      await press(tester, LogicalKeyboardKey.digit0, control: true);
      expect(app.zoom, 1);
    });
  });

  group('페이지', () {
    late SmoothScrollController scroll;
    late int refreshes;

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = newApp();
      addTearDown(app.dispose);
      scroll = SmoothScrollController();
      addTearDown(scroll.dispose);
      refreshes = 0;
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = AppNavigatorObserver(app.history);

      await tester.pumpWidget(
        AppScope(
          controller: app,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [observer],
            builder: (context, child) =>
                AppShortcuts(app: app, navigatorKey: navigatorKey, observer: observer, child: child!),
            home: Scaffold(
              body: PageTab(
                page: AppPage.levels,
                child: PageCommandScope(
                  commands: () => PageCommands(scroll: scroll, refresh: () => refreshes++),
                  child: Builder(
                    builder: (context) => ListView(
                      controller: scroll,
                      children: [
                        TextField(focusNode: PageCommandScope.searchFocusOf(context)),
                        for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('row $i')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Page Down / End / Home / 화살표로 스크롤한다', (tester) async {
      await pumpPage(tester);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(scroll.offset, closeTo(600 * 0.85, 1));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(scroll.offset, closeTo(600 * 0.85 + 60, 1));
      await press(tester, LogicalKeyboardKey.end);
      expect(scroll.offset, scroll.position.maxScrollExtent);
      await press(tester, LogicalKeyboardKey.home);
      expect(scroll.offset, 0);
    });

    testWidgets('F5와 Ctrl+R은 새로고침한다', (tester) async {
      await pumpPage(tester);
      await press(tester, LogicalKeyboardKey.f5);
      await press(tester, LogicalKeyboardKey.keyR, control: true);
      expect(refreshes, 2);
    });

    testWidgets('Ctrl+F는 검색창으로 가고, 글을 쓰는 동안 Space는 스크롤하지 않으며, Esc로 빠져나온다', (tester) async {
      await pumpPage(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyF, control: true);
      final field = tester.state<EditableTextState>(find.byType(EditableText));
      expect(field.widget.focusNode.hasFocus, isTrue);
      expect(field.textEditingValue.selection, const TextSelection(baseOffset: 0, extentOffset: 3));

      await press(tester, LogicalKeyboardKey.space);
      expect(scroll.offset, 0, reason: '글을 쓰는 중에는 Space가 글자다');

      await press(tester, LogicalKeyboardKey.escape);
      expect(field.widget.focusNode.hasFocus, isFalse);
      await press(tester, LogicalKeyboardKey.space);
      expect(scroll.offset, greaterThan(0));
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/ui/pages/library_page.dart';

/// 이름 입력 창은 닫히는 애니메이션 동안에도 입력 칸을 그린다.
/// 그 사이에 입력 칸을 정리해 버리면 디버그 실행에서 오류가 났다.
void main() {
  testWidgets('새 폴더 창을 확인·취소로 닫아도 오류가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = (await tester.runAsync(() => Directory.systemTemp.createTemp('tufapp_dialog_')))!;
    addTearDown(() => root.delete(recursive: true));
    final app = AppController();
    addTearDown(app.dispose);
    await tester.runAsync(() => app.library.open(root.path));

    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 확인으로 닫기.
    await tester.tap(find.text('새 폴더').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Packs');
    await tester.tap(find.text('만들기'));
    // 닫히는 애니메이션을 한 프레임씩 넘기며 오류가 나는지 본다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    // 취소로 닫기.
    await tester.tap(find.text('새 폴더').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
  });
}

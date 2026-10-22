import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/ui/pages/library_page.dart';

/// The name dialog still draws its text field during the closing animation.
/// Disposing the field in the meantime used to throw in debug runs.
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

    // Close with confirm.
    await tester.tap(find.text('새 폴더').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Packs');
    await tester.tap(find.text('만들기'));
    // Step through the closing animation frame by frame and check for errors.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    // Close with cancel.
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

@Tags(['network'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tufapp/core/level_library.dart';
import 'package:tufapp/core/level_manager.dart';
import 'package:tufapp/core/tuf_api_client.dart';

/// Downloads a small level (#5947, about 120 KB) from the real TUF server.
/// Needs the network; skip with `flutter test --exclude-tags network`.
void main() {
  test('레벨 받기 → 다시 받기(업데이트) → 삭제', () async {
    final root = await Directory.systemTemp.createTemp('tufapp_install_test_');
    final api = TufApiClient();

    try {
      final library = await LevelLibrary.open(root.path);
      final manager = LevelManager(api, library);
      final level = await api.getLevel(5947);

      // In the app, the progress callback is tied to widgets and can't be sent to an isolate.
      // To reproduce that, the callback holds an object that can't be sent (a Completer).
      final unsendable = Completer<void>();
      final stages = <InstallStage>[];
      void onProgress(InstallProgress progress) {
        if (!unsendable.isCompleted) stages.add(progress.stage);
      }

      final installed = await manager.install(level, onProgress: onProgress);

      expect(stages, containsAllInOrder([InstallStage.fetchingInfo, InstallStage.extracting, InstallStage.completed]));
      expect(installed.mainChartPath, isNotNull);
      expect(File(p.join(library.folderPathOf(installed), installed.mainChartPath!)).existsSync(), isTrue);

      // Downloading the same level again replaces the existing folder.
      await manager.install(level, onProgress: onProgress);
      expect(library.getAll(), hasLength(1));
      expect(Directory(library.tempPath).listSync(), isEmpty, reason: '임시 파일이 남으면 안 된다');

      expect(await manager.uninstall(level.id), isTrue);
      expect(Directory(library.folderPathOf(installed)).existsSync(), isFalse);
    } finally {
      api.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

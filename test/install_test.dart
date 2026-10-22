@Tags(['network'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tufapp/core/level_library.dart';
import 'package:tufapp/core/level_manager.dart';
import 'package:tufapp/core/tuf_api_client.dart';

/// 실제 TUF 서버에서 작은 레벨(#5947, 약 120KB)을 받아 보는 테스트.
/// 네트워크가 필요하므로 `flutter test --exclude-tags network`로 뺄 수 있다.
void main() {
  test('레벨 받기 → 다시 받기(업데이트) → 삭제', () async {
    final root = await Directory.systemTemp.createTemp('tufapp_install_test_');
    final api = TufApiClient();

    try {
      final library = await LevelLibrary.open(root.path);
      final manager = LevelManager(api, library);
      final level = await api.getLevel(5947);

      // 앱에서는 진행률 콜백이 위젯과 연결돼 있어 isolate로 보낼 수 없다.
      // 같은 상황을 만들려고 보낼 수 없는 객체(Completer)를 콜백이 붙잡게 한다.
      final unsendable = Completer<void>();
      final stages = <InstallStage>[];
      void onProgress(InstallProgress progress) {
        if (!unsendable.isCompleted) stages.add(progress.stage);
      }

      final installed = await manager.install(level, onProgress: onProgress);

      expect(stages, containsAllInOrder([InstallStage.fetchingInfo, InstallStage.extracting, InstallStage.completed]));
      expect(installed.mainChartPath, isNotNull);
      expect(File(p.join(library.folderPathOf(installed), installed.mainChartPath!)).existsSync(), isTrue);

      // 같은 레벨을 다시 받으면 기존 폴더를 교체한다.
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

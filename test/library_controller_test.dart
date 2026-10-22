import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/level_library.dart';
import 'package:tufapp/core/library_organizer.dart';
import 'package:tufapp/core/tuf_api_client.dart';

/// 탐색기처럼 고르고 옮기는 부분(선택 규칙, 여러 개 옮기기/지우기)을 확인한다.
void main() {
  late Directory root;
  late LibraryController library;
  final messages = <String>[];

  Future<void> makeLevel(String folderName, {int size = 100}) async {
    await Directory(p.join(root.path, folderName)).create(recursive: true);
    await File(p.join(root.path, folderName, 'main.adofai')).writeAsString('{}');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tufapp_controller_');
    messages.clear();
    library = LibraryController(
      api: TufApiClient(),
      installs: InstallCenter(onStatus: messages.add),
      onStatus: messages.add,
    );
  });

  tearDown(() async {
    library.dispose();
    await root.delete(recursive: true);
  });

  /// 폴더 2개와 레벨 3개가 있는 라이브러리를 연다.
  Future<void> openSample() async {
    await Directory(p.join(root.path, 'a')).create();
    await Directory(p.join(root.path, 'b')).create();
    await makeLevel('level1');
    await makeLevel('level2');
    await makeLevel('level3');
    await library.open(root.path);
  }

  test('폴더가 먼저 오고 이름순으로 정렬한다', () async {
    await openSample();
    expect([for (final entry in library.entries) entry.name], ['a', 'b', 'level1', 'level2', 'level3']);
  });

  test('그냥 누르면 하나만, Ctrl은 토글, Shift는 범위', () async {
    await openSample();
    final entries = library.entries;

    library.select(entries[2]);
    expect(library.selection, {'level1'});

    library.select(entries[4], toggle: true);
    expect(library.selection, {'level1', 'level3'});

    library.select(entries[4], toggle: true);
    expect(library.selection, {'level1'}, reason: 'Ctrl로 다시 누르면 빠진다');

    library.select(entries[0]);
    library.select(entries[2], range: true);
    expect(library.selection, {'a', 'b', 'level1'}, reason: '기준점부터 누른 곳까지');
  });

  test('모두 선택과 선택 해제', () async {
    await openSample();
    library.selectAll();
    expect(library.selection, hasLength(5));

    library.clearSelection();
    expect(library.selection, isEmpty);
  });

  test('선택한 항목을 끌면 선택 전체가 따라온다', () async {
    await openSample();
    final entries = library.entries;

    library.select(entries[2]);
    library.select(entries[3], toggle: true);

    expect([for (final e in library.dragGroupFor(entries[2])) e.name], ['level1', 'level2']);
    // 선택에 없는 항목을 끌면 그것만
    expect([for (final e in library.dragGroupFor(entries[4])) e.name], ['level3']);
  });

  test('여러 개를 한 번에 옮긴다', () async {
    await openSample();
    final levels = [
      for (final e in library.entries)
        if (e is! FolderEntry) e,
    ];

    await library.moveEntries(levels, 'a');

    expect(Directory(p.join(root.path, 'a', 'level1')).existsSync(), isTrue);
    expect(Directory(p.join(root.path, 'level1')).existsSync(), isFalse);
    expect(library.currentPath, '', reason: '보고 있던 폴더는 그대로');
    expect(library.entries.map((e) => e.name), ['a', 'b']);
    expect(messages.last, contains('3개'));
  });

  test('폴더를 자기 안으로 옮기려 하면 알려주고 나머지는 옮긴다', () async {
    await openSample();
    final a = library.entries.firstWhere((e) => e.name == 'a');
    final level = library.entries.firstWhere((e) => e.name == 'level1');

    await library.moveEntries([a, level], 'a');

    expect(Directory(p.join(root.path, 'a')).existsSync(), isTrue, reason: '폴더는 그대로 남는다');
    expect(Directory(p.join(root.path, 'a', 'level1')).existsSync(), isTrue);
    expect(messages.last, contains('옮기지 못했습니다'));
  });

  test('여러 개를 한 번에 지운다', () async {
    await openSample();
    final targets = [
      library.entries.firstWhere((e) => e.name == 'b'),
      library.entries.firstWhere((e) => e.name == 'level2'),
    ];

    await library.deleteEntries(targets);

    expect(Directory(p.join(root.path, 'b')).existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'level2')).existsSync(), isFalse);
    expect([for (final entry in library.entries) entry.name], ['a', 'level1', 'level3']);
  });

  test('폴더를 옮기면 보고 있던 위치와 선택이 정리된다', () async {
    await openSample();
    await library.openPath('a');
    expect(library.currentPath, 'a');

    await library.goUp();
    expect(library.currentPath, '');

    library.selectAll();
    await library.openPath('b');
    expect(library.selection, isEmpty, reason: '폴더를 옮기면 선택은 풀린다');
  });

  test('없어진 항목은 선택에서 빠진다', () async {
    await openSample();
    library.selectAll();

    await Directory(p.join(root.path, 'level1')).delete(recursive: true);
    await library.refreshContents();

    expect(library.selection.contains('level1'), isFalse);
    expect(library.selection, hasLength(4));
  });

  test('크기순 정렬은 큰 레벨을 먼저 둔다', () async {
    await openSample();
    final index = await LevelLibrary.open(root.path);
    await index.set(
      InstalledLevel(
        levelId: 1,
        song: 'song',
        artist: 'artist',
        fileId: 'file',
        folderName: 'level2',
        sizeBytes: 999,
        installedAt: DateTime(2026),
      ),
    );
    await library.open(root.path);

    library.setSort(LibrarySort.size);
    final levels = [
      for (final e in library.entries)
        if (e is! FolderEntry) e.name,
    ];
    expect(levels.first, 'level2', reason: '크기를 아는 레벨이 먼저');
  });
}

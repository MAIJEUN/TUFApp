import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tufapp/core/level_library.dart';
import 'package:tufapp/core/library_organizer.dart';

void main() {
  late Directory root;
  late LevelLibrary library;
  late LibraryOrganizer organizer;

  /// 레벨 폴더를 만들고 목록에 넣는다.
  Future<InstalledLevel> addLevel(int id, String folderName, {int size = 100}) async {
    await Directory(p.join(root.path, folderName)).create(recursive: true);
    await File(p.join(root.path, folderName, 'main.adofai')).writeAsString('{}');
    final level = InstalledLevel(
      levelId: id,
      song: 'song$id',
      artist: 'artist',
      fileId: 'file$id',
      folderName: folderName,
      sizeBytes: size,
      installedAt: DateTime(2026, 1, id),
    );
    await library.set(level);
    return level;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tufapp_organizer_');
    library = await LevelLibrary.open(root.path);
    organizer = LibraryOrganizer(library);
  });

  tearDown(() async => root.delete(recursive: true));

  test('팩째 받은 폴더는 팩 아이콘을 기억하고, 옮기거나 지워도 문제없다', () async {
    const icon = 'https://api.tuforums.com/cdn/images/pack_icon/x/original';
    final packFolder = p.join(root.path, 'AWC Original Levels');
    await LibraryOrganizer.writeFolderInfo(packFolder, const FolderInfo(iconUrl: 'old', packId: 'HX'));
    // 두 번째는 숨김 파일을 덮어쓴다.
    await LibraryOrganizer.writeFolderInfo(packFolder, const FolderInfo(iconUrl: icon, packId: 'HX'));
    await addLevel(1, 'AWC Original Levels/AWC 2023/#1 song1');

    var folder = (await organizer.list('')).folders.single;
    expect(folder.iconUrl, icon);
    expect(folder.folderCount, 1, reason: '정보 파일은 항목으로 세지 않는다');

    await organizer.createFolder('', 'Packs');
    await organizer.move(folder, 'Packs');
    folder = (await organizer.list('Packs')).folders.single;
    expect(folder.iconUrl, icon, reason: '폴더를 옮기면 정보도 따라간다');

    await organizer.delete(folder);
    expect((await organizer.list('Packs')).isEmpty, isTrue);
  });

  test("이름에 '+'가 든 폴더는 '_'로 바꾸고, 레벨 안의 파일은 건드리지 않는다", () async {
    await addLevel(1, 'FAINT/Tier 0 + 1/#263 230+BPM');
    // 레벨 안의 파일 이름은 차트가 가리키므로 그대로 둬야 한다.
    await File(p.join(root.path, 'FAINT/Tier 0 + 1/#263 230+BPM/song+.ogg')).writeAsString('');
    await Directory(p.join(root.path, 'Tier 0 _ 1')).create(); // 바꿀 이름이 이미 있는 경우

    expect(await organizer.fixUnloadableNames(), 2);

    expect(library.get(1)!.folderName, 'FAINT/Tier 0 _ 1/#263 230_BPM', reason: '목록의 경로도 따라 바뀐다');
    expect(File(p.join(root.path, 'FAINT/Tier 0 _ 1/#263 230_BPM/song+.ogg')).existsSync(), isTrue);
    expect(await organizer.fixUnloadableNames(), 0, reason: '한 번 바꾸면 다시 바꿀 것이 없다');

    // 직접 만들거나 이름을 바꿀 때도 '+'는 자동으로 바뀐다.
    await organizer.createFolder('', 'A+B');
    expect(Directory(p.join(root.path, 'A_B')).existsSync(), isTrue);
  });

  test('루트의 폴더와 레벨을 나눠서 보여준다', () async {
    await addLevel(1, '#1 song1');
    await organizer.createFolder('', 'Camellia');
    await addLevel(2, 'Camellia/#2 song2');

    final root0 = await organizer.list('');
    expect([for (final f in root0.folders) f.name], ['Camellia']);
    expect([for (final l in root0.levels) l.name], ['#1 song1']);
    expect(root0.folders.single.levelCount, 1);

    final inside = await organizer.list('Camellia');
    expect(inside.folders, isEmpty);
    expect((inside.levels.single as LevelEntry).level.levelId, 2);
  });

  test('폴더를 만들고, 같은 이름은 막는다', () async {
    expect(await organizer.createFolder('', '연습용'), '연습용');
    expect(Directory(p.join(root.path, '연습용')).existsSync(), isTrue);

    expect(() => organizer.createFolder('', '연습용'), throwsA(isA<LibraryOperationException>()));
    expect(() => organizer.createFolder('', '  '), throwsA(isA<LibraryOperationException>()));
    expect(() => organizer.createFolder('', 'a/b'), throwsA(isA<LibraryOperationException>()));
  });

  test('레벨을 폴더 안으로 옮기면 폴더와 목록이 함께 바뀐다', () async {
    await addLevel(1, '#1 song1');
    await organizer.createFolder('', 'Camellia');

    final entry = (await organizer.list('')).levels.single;
    final moved = await organizer.move(entry, 'Camellia');

    expect(moved, 'Camellia/#1 song1');
    expect(Directory(p.join(root.path, 'Camellia', '#1 song1')).existsSync(), isTrue);
    expect(Directory(p.join(root.path, '#1 song1')).existsSync(), isFalse);
    expect(library.get(1)!.folderName, 'Camellia/#1 song1');
    // 앱을 다시 켜도 같은 경로를 가리킨다.
    final reopened = await LevelLibrary.open(root.path);
    expect(reopened.get(1)!.folderName, 'Camellia/#1 song1');
  });

  test('폴더 이름을 바꾸면 안에 있던 레벨 경로도 따라간다', () async {
    await organizer.createFolder('', 'old');
    await addLevel(1, 'old/#1 song1');
    await addLevel(2, 'old/안쪽/#2 song2');

    final folder = (await organizer.list('')).folders.single;
    expect(await organizer.rename(folder, 'new'), 'new');

    expect(library.get(1)!.folderName, 'new/#1 song1');
    expect(library.get(2)!.folderName, 'new/안쪽/#2 song2');
    expect(Directory(p.join(root.path, 'new', '안쪽', '#2 song2')).existsSync(), isTrue);
  });

  test('폴더를 지우면 안에 있던 레벨도 목록에서 빠진다', () async {
    await organizer.createFolder('', 'temp');
    await addLevel(1, 'temp/#1 song1');
    await addLevel(2, '#2 song2');

    final folder = (await organizer.list('')).folders.single;
    expect(await organizer.delete(folder), 1);

    expect(Directory(p.join(root.path, 'temp')).existsSync(), isFalse);
    expect(library.get(1), isNull);
    expect(library.get(2), isNotNull, reason: '다른 폴더의 레벨은 그대로 둔다');
  });

  test('폴더를 자기 자신 안으로 옮기지 않는다', () async {
    await organizer.createFolder('', 'a');
    await organizer.createFolder('a', 'b');

    final a = (await organizer.list('')).folders.single;
    expect(() => organizer.move(a, 'a/b'), throwsA(isA<LibraryOperationException>()));
    expect(() => organizer.move(a, 'a'), throwsA(isA<LibraryOperationException>()));
  });

  test('라이브러리 폴더 밖은 다루지 않는다', () async {
    expect(() => organizer.fullPath('../바깥'), throwsA(isA<LibraryOperationException>()));
    expect(() => organizer.createFolder('..', '바깥'), throwsA(isA<LibraryOperationException>()));
  });

  test('모든 폴더를 훑어서 옮길 곳 목록을 만든다', () async {
    await organizer.createFolder('', 'a');
    await organizer.createFolder('a', 'b');
    await organizer.createFolder('', 'c');
    await addLevel(1, 'a/#1 song1');

    expect([for (final f in await organizer.allFolders()) f.relativePath], ['a', 'a/b', 'c']);
  });

  test('목록에 없어도 .adofai가 있으면 레벨로 본다', () async {
    // 사용자가 직접 넣어 둔 레벨 폴더
    await Directory(p.join(root.path, 'AWC', '2024', '직접 넣은 레벨')).create(recursive: true);
    await File(p.join(root.path, 'AWC', '2024', '직접 넣은 레벨', 'main.adofai')).writeAsString('{}');

    final rootContents = await organizer.list('');
    final folder = rootContents.folders.single;
    expect(folder.name, 'AWC');
    expect(folder.folderCount, 1, reason: '바로 아래 2024 폴더 하나');
    expect(folder.levelCount, 0);

    final inside = await organizer.list('AWC/2024');
    expect(inside.levels.single, isA<ExternalLevelEntry>());
    expect(inside.levels.single.name, '직접 넣은 레벨');
    expect(inside.folders, isEmpty, reason: '레벨 폴더는 폴더로 세지 않는다');
  });

  test('직접 넣은 레벨도 옮기고 지울 수 있다', () async {
    await Directory(p.join(root.path, '직접 넣은 레벨')).create(recursive: true);
    await File(p.join(root.path, '직접 넣은 레벨', 'main.adofai')).writeAsString('{}');
    await organizer.createFolder('', '보관함');

    final entry = (await organizer.list('')).levels.single;
    expect(await organizer.move(entry, '보관함'), '보관함/직접 넣은 레벨');
    expect(File(p.join(root.path, '보관함', '직접 넣은 레벨', 'main.adofai')).existsSync(), isTrue);

    final moved = (await organizer.list('보관함')).levels.single;
    expect(await organizer.delete(moved), 0, reason: '목록에 없던 레벨이라 뺄 항목이 없다');
    expect(Directory(p.join(root.path, '보관함', '직접 넣은 레벨')).existsSync(), isFalse);
  });
}

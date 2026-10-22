import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'l10n.dart';
import 'level_library.dart';

/// 라이브러리 폴더 안의 항목 하나. 실제 디스크의 폴더를 그대로 보여준다.
sealed class LibraryEntry {
  const LibraryEntry({required this.name, required this.relativePath});

  /// 화면에 보여줄 이름 (폴더 이름).
  final String name;

  /// 라이브러리 루트 기준 경로. 구분자는 항상 '/'.
  final String relativePath;
}

/// 받은 레벨 하나.
class LevelEntry extends LibraryEntry {
  const LevelEntry({required super.name, required super.relativePath, required this.level});

  final InstalledLevel level;
}

/// 앱으로 받지 않았지만 폴더 안에 .adofai가 있는 레벨. 직접 넣어 둔 레벨도 같이 정리할 수 있게 보여준다.
class ExternalLevelEntry extends LibraryEntry {
  const ExternalLevelEntry({required super.name, required super.relativePath});
}

/// 레벨을 담는 폴더. 개수는 바로 아래 단계만 센다.
class FolderEntry extends LibraryEntry {
  const FolderEntry({
    required super.name,
    required super.relativePath,
    required this.folderCount,
    required this.levelCount,
    this.iconUrl,
  });

  final int folderCount;
  final int levelCount;

  /// 팩째 받은 폴더면 그 팩의 아이콘.
  final String? iconUrl;

  bool get isEmpty => folderCount == 0 && levelCount == 0;
}

/// 폴더에 붙여 두는 정보. 지금은 팩째 받은 폴더의 팩 아이콘과 팩 id.
class FolderInfo {
  const FolderInfo({this.iconUrl, this.packId});

  factory FolderInfo.fromJson(Map<String, dynamic> json) => FolderInfo(
    iconUrl: json['iconUrl'] is String ? json['iconUrl'] as String : null,
    packId: json['packId'] is String ? json['packId'] as String : null,
  );

  final String? iconUrl;
  final String? packId;

  Map<String, Object?> toJson() => {'iconUrl': iconUrl, 'packId': packId};
}

/// 폴더 하나의 내용. 폴더가 먼저, 그다음 레벨이 이름순으로 온다.
class FolderContents {
  const FolderContents({required this.path, required this.folders, required this.levels});

  final String path;
  final List<FolderEntry> folders;

  /// 받은 레벨([LevelEntry])과 직접 넣어 둔 레벨([ExternalLevelEntry]).
  final List<LibraryEntry> levels;

  bool get isEmpty => folders.isEmpty && levels.isEmpty;
  List<LibraryEntry> get all => [...folders, ...levels];
}

/// 이름이나 경로가 잘못됐을 때.
class LibraryOperationException implements Exception {
  const LibraryOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 라이브러리 폴더를 탐색기처럼 다룬다: 폴더 만들기, 이름 바꾸기, 옮기기, 지우기.
///
/// 폴더는 실제 디스크 폴더다. 레벨을 옮기면 폴더째 옮기고, 목록의 [InstalledLevel.folderName]도 같이 고친다.
class LibraryOrganizer {
  const LibraryOrganizer(this.library);

  /// Windows에서 폴더 이름에 쓸 수 없는 문자.
  static final _illegalCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  final LevelLibrary library;

  String get rootPath => library.rootPath;

  /// 라이브러리 루트 기준 경로를 실제 경로로 바꾼다. 루트 밖으로 나가면 막는다.
  String fullPath(String relativePath) {
    final root = p.normalize(library.rootPath);
    final full = p.normalize(p.join(root, relativePath));
    if (full != root && !p.isWithin(root, full)) {
      throw LibraryOperationException(tr('라이브러리 폴더 밖은 다룰 수 없습니다.', "Can't work outside the library folder."));
    }
    return full;
  }

  /// [relativePath] 폴더의 내용을 읽는다. 루트는 빈 문자열.
  Future<FolderContents> list(String relativePath) async {
    final directory = Directory(fullPath(relativePath));
    if (!await directory.exists()) {
      return FolderContents(path: relativePath, folders: const [], levels: const []);
    }

    final levelsByPath = {for (final level in library.getAll()) _normalize(level.folderName): level};
    final folders = <FolderEntry>[];
    final levels = <LibraryEntry>[];

    // 폴더마다 안을 들여다봐야 해서, 하나씩 기다리면 항목이 많을 때 눈에 띄게 느리다. 한꺼번에 돌린다.
    final children = await _childDirectories(directory);
    final entries = await Future.wait([for (final child in children) _entryFor(child, relativePath, levelsByPath)]);

    for (final entry in entries) {
      switch (entry) {
        case FolderEntry():
          folders.add(entry);
        case LibraryEntry():
          levels.add(entry);
      }
    }

    folders.sort((a, b) => _compareNames(a.name, b.name));
    levels.sort((a, b) => _compareNames(a.name, b.name));
    return FolderContents(path: relativePath, folders: folders, levels: levels);
  }

  /// 폴더 하나를 보고 레벨인지 폴더인지 정한다.
  Future<LibraryEntry> _entryFor(Directory child, String parentPath, Map<String, InstalledLevel> levelsByPath) async {
    final name = p.basename(child.path);
    final relative = _join(parentPath, name);

    final level = levelsByPath[relative];
    if (level != null) return LevelEntry(name: name, relativePath: relative, level: level);
    if (await _looksLikeLevel(child)) return ExternalLevelEntry(name: name, relativePath: relative);
    return _folderEntry(child, name, relative, levelsByPath);
  }

  /// 바로 아래 폴더와 레벨이 몇 개인지 세어 둔다 (한 단계만 본다).
  Future<FolderEntry> _folderEntry(
    Directory directory,
    String name,
    String relative,
    Map<String, InstalledLevel> levelsByPath,
  ) async {
    final children = await _childDirectories(directory);
    final isLevel = await Future.wait([
      for (final child in children)
        levelsByPath.containsKey(_join(relative, p.basename(child.path))) ? Future.value(true) : _looksLikeLevel(child),
    ]);

    final levelCount = isLevel.where((value) => value).length;
    return FolderEntry(
      name: name,
      relativePath: relative,
      folderCount: children.length - levelCount,
      levelCount: levelCount,
      iconUrl: (await readFolderInfo(directory.path))?.iconUrl,
    );
  }

  /// 폴더 정보를 담는 파일. 폴더 안에 두므로 이름을 바꾸거나 옮겨도 따라간다.
  static const folderInfoFileName = '.tufapp-folder.json';

  /// 폴더에 붙은 정보(팩 아이콘 등). 없거나 읽을 수 없으면 null.
  static Future<FolderInfo?> readFolderInfo(String folderPath) async {
    final file = File(p.join(folderPath, folderInfoFileName));
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic> ? FolderInfo.fromJson(json) : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// 폴더에 정보를 남긴다. 폴더가 없으면 만든다. 실패해도 받기에는 지장이 없으므로 조용히 넘어간다.
  static Future<void> writeFolderInfo(String folderPath, FolderInfo info) async {
    final file = File(p.join(folderPath, folderInfoFileName));
    try {
      await Directory(folderPath).create(recursive: true);
      // Windows는 숨김 파일을 덮어쓰지 못하므로 지우고 새로 쓴다.
      if (await file.exists()) await file.delete();
      await file.writeAsString(jsonEncode(info.toJson()));
      // 탐색기에서 레벨 파일 사이에 보이지 않게 숨긴다.
      if (Platform.isWindows) await Process.run('attrib', ['+h', file.path]);
    } on FileSystemException {
      // 무시한다.
    } on ProcessException {
      // 숨기지 못해도 괜찮다.
    }
  }

  /// 숨김 폴더와 임시 폴더를 뺀 하위 폴더들.
  static Future<List<Directory>> _childDirectories(Directory directory) async {
    final result = <Directory>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory && !p.basename(entity.path).startsWith('.')) result.add(entity);
      }
    } on FileSystemException {
      // 권한이 없는 폴더는 건너뛴다.
    }
    return result;
  }

  /// 폴더 바로 안에 .adofai 파일이 있으면 레벨 폴더로 본다.
  static Future<bool> _looksLikeLevel(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && p.extension(entity.path).toLowerCase() == '.adofai') return true;
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  /// 레벨을 담지 않은 폴더까지 포함해 모든 폴더 경로를 훑는다 (옮길 곳 고르기 등에 쓴다).
  Future<List<FolderEntry>> allFolders([String relativePath = '']) async {
    final result = <FolderEntry>[];
    final contents = await list(relativePath);
    for (final folder in contents.folders) {
      result
        ..add(folder)
        ..addAll(await allFolders(folder.relativePath));
    }
    return result;
  }

  /// [parent] 아래에 새 폴더를 만든다.
  Future<String> createFolder(String parent, String name) async {
    final safe = _validateName(name);
    final relative = _join(parent, safe);
    final directory = Directory(fullPath(relative));
    if (await directory.exists()) {
      throw LibraryOperationException(tr('"$safe" 폴더가 이미 있습니다.', 'A folder named "$safe" already exists.'));
    }
    await directory.create(recursive: true);
    return relative;
  }

  /// 폴더나 레벨 폴더의 이름을 바꾼다. 안에 든 레벨의 경로도 따라 바뀐다.
  Future<String> rename(LibraryEntry entry, String newName) async {
    final safe = _validateName(newName);
    if (safe == entry.name) return entry.relativePath;

    final parent = _parentOf(entry.relativePath);
    final target = _join(parent, safe);
    await _moveDirectory(entry.relativePath, target, tr('"$safe"이(가) 이미 있습니다.', '"$safe" already exists.'));
    return target;
  }

  /// 폴더나 레벨을 [targetFolder] 안으로 옮긴다. 루트로 옮기려면 빈 문자열.
  Future<String> move(LibraryEntry entry, String targetFolder) async {
    if (_parentOf(entry.relativePath) == _normalize(targetFolder)) return entry.relativePath;
    if (entry is FolderEntry && _isInside(entry.relativePath, targetFolder)) {
      throw LibraryOperationException(tr('폴더를 자기 자신 안으로 옮길 수 없습니다.', "Can't move a folder into itself."));
    }

    final target = _join(targetFolder, entry.name);
    await _moveDirectory(
      entry.relativePath,
      target,
      tr('"${entry.name}"이(가) 옮길 곳에 이미 있습니다.', '"${entry.name}" already exists there.'),
    );
    return target;
  }

  /// 이름에 게임이 불러오지 못하는 글자('+')가 든 폴더를 찾아 이름을 바꾼다. 바꾼 개수를 돌려준다.
  ///
  /// 레벨 폴더 자체의 이름은 바꾸지만 그 안(음악, 차트 파일)은 건드리지 않는다.
  /// 차트가 파일 이름으로 음악을 찾기 때문이다. 바꾸지 못한 폴더(게임이 열고 있는 등)는 건너뛴다.
  Future<int> fixUnloadableNames([String relativePath = '']) async {
    var count = 0;
    final contents = await list(relativePath);
    for (final entry in contents.all) {
      var current = entry.relativePath;
      final fixed = replaceUnloadable(entry.name);
      if (fixed != entry.name) {
        try {
          final target = await _uniquePath(relativePath, fixed);
          await _moveDirectory(entry.relativePath, target, '');
          current = target;
          count++;
        } on FileSystemException {
          continue;
        } on LibraryOperationException {
          continue;
        }
      }
      if (entry is FolderEntry) count += await fixUnloadableNames(current);
    }
    return count;
  }

  /// [parent] 안에서 [name]이 이미 있으면 "name (2)"처럼 비어 있는 이름을 찾는다.
  Future<String> _uniquePath(String parent, String name) async {
    var candidate = _join(parent, name);
    for (var i = 2; await Directory(fullPath(candidate)).exists(); i++) {
      candidate = _join(parent, '$name ($i)');
    }
    return candidate;
  }

  /// 폴더나 레벨 폴더를 통째로 지운다. 목록에 있던 레벨은 목록에서도 뺀다. 지워진 레벨 수를 돌려준다.
  Future<int> delete(LibraryEntry folder) async {
    final directory = Directory(fullPath(folder.relativePath));
    final inside = _levelsInside(folder.relativePath);
    if (await directory.exists()) await directory.delete(recursive: true);
    for (final level in inside) {
      await library.remove(level.levelId);
    }
    return inside.length;
  }

  /// 폴더 이동/이름 변경을 실제로 수행하고 목록의 경로를 고친다.
  Future<void> _moveDirectory(String from, String to, String existsMessage) async {
    final source = Directory(fullPath(from));
    final destination = Directory(fullPath(to));
    if (!await source.exists()) throw LibraryOperationException(tr('폴더를 찾을 수 없습니다.', 'Folder not found.'));
    if (await destination.exists()) throw LibraryOperationException(existsMessage);

    await Directory(p.dirname(destination.path)).create(recursive: true);
    await source.rename(destination.path);
    await library.movePath(from, to);
  }

  List<InstalledLevel> _levelsInside(String relativePath) {
    final prefix = '${_normalize(relativePath)}/';
    return [
      for (final level in library.getAll())
        if (_normalize(level.folderName).startsWith(prefix)) level,
    ];
  }

  static bool _isInside(String folder, String candidate) {
    final normalized = _normalize(candidate);
    final prefix = '${_normalize(folder)}/';
    return normalized == _normalize(folder) || normalized.startsWith(prefix);
  }

  /// 게임이 불러오지 못하는 글자를 바꾼다 (경로에 '+'가 있으면 레벨을 제대로 읽지 못한다).
  static String replaceUnloadable(String name) => name.replaceAll('+', '_');

  static String _validateName(String name) {
    final trimmed = replaceUnloadable(name).trim().replaceAll(RegExp(r'[. ]+$'), '');
    if (trimmed.isEmpty) throw LibraryOperationException(tr('이름을 입력해 주세요.', 'Please enter a name.'));
    if (_illegalCharacters.hasMatch(trimmed)) {
      throw LibraryOperationException(
        tr(r'이름에 < > : " / \ | ? * 는 쓸 수 없습니다.', r'Names cannot contain < > : " / \ | ? *'),
      );
    }
    return trimmed;
  }

  static String _parentOf(String relativePath) {
    final normalized = _normalize(relativePath);
    final index = normalized.lastIndexOf('/');
    return index < 0 ? '' : normalized.substring(0, index);
  }

  static String _join(String parent, String name) {
    final base = _normalize(parent);
    return base.isEmpty ? name : '$base/$name';
  }

  /// 경로 구분자를 '/'로 맞추고 앞뒤 구분자를 뗀다.
  static String _normalize(String path) => path.replaceAll(r'\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

  /// 숫자가 섞인 이름도 사람이 기대하는 순서로 (대소문자 무시).
  static int _compareNames(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
}

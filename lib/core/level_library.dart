import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'json.dart';
import 'l10n.dart';
import 'zip_names.dart';

/// 로컬에 받아 둔 레벨 정보. C# 버전과 같은 JSON 형식이라 기존 라이브러리를 그대로 읽을 수 있다.
class InstalledLevel {
  const InstalledLevel({
    required this.levelId,
    required this.song,
    required this.artist,
    this.creator,
    this.difficulty,
    required this.fileId,
    required this.folderName,
    this.mainChartPath,
    this.sizeBytes = 0,
    required this.installedAt,
  });

  factory InstalledLevel.fromJson(Map<String, dynamic> json) => InstalledLevel(
    levelId: asInt(json['levelId']),
    song: json['song'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    creator: asStringOrNull(json['creator']),
    difficulty: asStringOrNull(json['difficulty']),
    fileId: json['fileId'] as String? ?? '',
    folderName: json['folderName'] as String? ?? '',
    mainChartPath: asStringOrNull(json['mainChartPath']),
    sizeBytes: asInt(json['sizeBytes']),
    installedAt: DateTime.tryParse(json['installedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  final int levelId;
  final String song;
  final String artist;
  final String? creator;
  final String? difficulty;

  /// 받을 당시의 CDN fileId. 서버의 값과 다르면 업데이트가 있는 것.
  final String fileId;

  /// 라이브러리 루트 기준 폴더 이름.
  final String folderName;

  /// 폴더 기준 메인 .adofai 상대 경로. 찾지 못하면 null.
  final String? mainChartPath;
  final int sizeBytes;
  final DateTime installedAt;

  InstalledLevel copyWith({String? folderName}) => InstalledLevel(
    levelId: levelId,
    song: song,
    artist: artist,
    creator: creator,
    difficulty: difficulty,
    fileId: fileId,
    folderName: folderName ?? this.folderName,
    mainChartPath: mainChartPath,
    sizeBytes: sizeBytes,
    installedAt: installedAt,
  );

  Map<String, dynamic> toJson() => {
    'levelId': levelId,
    'song': song,
    'artist': artist,
    'creator': creator,
    'difficulty': difficulty,
    'fileId': fileId,
    'folderName': folderName,
    'mainChartPath': mainChartPath,
    'sizeBytes': sizeBytes,
    'installedAt': installedAt.toIso8601String(),
  };
}

/// 받은 레벨 목록. 라이브러리 폴더 안의 [indexFileName]에 저장된다.
class LevelLibrary {
  LevelLibrary._(this.rootPath, Iterable<InstalledLevel> levels, {this.recovery}) {
    for (final level in levels) {
      _levels[level.levelId] = level;
    }
  }

  static const indexFileName = 'tufapp-library.json';

  /// 다운로드와 압축 해제 중에 쓰는 임시 폴더 이름.
  static const tempFolderName = '.tufapp-tmp';

  final String rootPath;

  /// 목록 파일이 깨져 있어서 고친 내용. 문제가 없었으면 null.
  final String? recovery;
  final Map<int, InstalledLevel> _levels = {};
  Future<void> _saveChain = Future.value();

  String get tempPath => p.join(rootPath, tempFolderName);

  static Future<LevelLibrary> open(String rootPath) async {
    final root = p.normalize(p.absolute(rootPath));
    await Directory(root).create(recursive: true);

    final index = File(p.join(root, indexFileName));
    if (!await index.exists()) return LevelLibrary._(root, const []);

    // 목록 파일이 깨져 있어도 앱이 멈추지 않게 한다. 레벨 폴더는 건드리지 않는다.
    Object? json;
    try {
      json = jsonDecode(await index.readAsString());
    } on FormatException {
      json = null;
    }
    if (json is! List) {
      // 읽을 수 없는 파일은 지우지 않고 옆에 남겨 두고, 빈 목록으로 시작한다.
      final backup = '${index.path}.broken-${DateTime.now().millisecondsSinceEpoch}';
      await index.rename(backup);
      return LevelLibrary._(
        root,
        const [],
        recovery: tr(
          '받은 레벨 목록 파일을 읽을 수 없어서 새로 시작합니다. 원래 파일은 ${p.basename(backup)}(으)로 남겨 뒀습니다.',
          "Couldn't read the downloaded level list, so it starts fresh. The original file was kept as ${p.basename(backup)}.",
        ),
      );
    }

    final levels = <InstalledLevel>[];
    var skipped = 0;
    for (final item in json) {
      final level = item is Map<String, dynamic> ? _tryParse(item) : null;
      // 폴더 이름이 없거나 라이브러리 밖을 가리키는 항목은 지우기·업데이트 때 위험하므로 뺀다.
      if (level == null || !_isSafeFolderName(level.folderName)) {
        skipped++;
      } else {
        levels.add(level);
      }
    }
    return LevelLibrary._(
      root,
      levels,
      recovery: skipped == 0
          ? null
          : tr(
              '받은 레벨 목록에서 읽을 수 없는 항목 $skipped개를 뺐습니다.',
              'Removed $skipped unreadable ${plural(skipped, 'entry', 'entries')} from the downloaded level list.',
            ),
    );
  }

  static InstalledLevel? _tryParse(Map<String, dynamic> json) {
    try {
      return InstalledLevel.fromJson(json);
    } on TypeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// 라이브러리 안의 하위 폴더를 가리키는 이름인지 (비어 있거나 루트 자신, 루트 밖이면 아님).
  static bool _isSafeFolderName(String folderName) {
    final name = folderName.replaceAll(r'\', '/').trim();
    if (name.isEmpty || p.isAbsolute(name)) return false;
    final normalized = p.posix.normalize(name);
    return normalized != '.' && !normalized.startsWith('..');
  }

  /// [level] 폴더의 실제 경로. 루트 자신이거나 루트 밖이면 null (그런 경로는 지우거나 바꾸면 안 된다).
  String? safeFolderPathOf(InstalledLevel level) {
    if (!_isSafeFolderName(level.folderName)) return null;
    final path = p.normalize(folderPathOf(level));
    return p.isWithin(rootPath, path) ? path : null;
  }

  /// 최근에 받은 순서.
  List<InstalledLevel> getAll() => _levels.values.toList()..sort((a, b) => b.installedAt.compareTo(a.installedAt));

  InstalledLevel? get(int levelId) => _levels[levelId];

  bool contains(int levelId) => _levels.containsKey(levelId);

  String folderPathOf(InstalledLevel level) => p.join(rootPath, level.folderName);

  Future<void> set(InstalledLevel level) {
    if (!_isSafeFolderName(level.folderName)) {
      throw FileSystemException(tr('레벨 폴더 이름이 올바르지 않습니다', 'Invalid level folder name'), level.folderName);
    }
    _levels[level.levelId] = level;
    return _save();
  }

  /// 폴더를 옮기거나 이름을 바꿨을 때, 그 안에 있던 레벨들의 경로를 한꺼번에 고친다.
  /// [from]이 레벨 폴더 자신이면 그 레벨만 바뀐다.
  Future<void> movePath(String from, String to) async {
    final source = _normalizePath(from);
    final target = _normalizePath(to);
    if (source.isEmpty || source == target) return;

    var changed = false;
    for (final level in _levels.values.toList()) {
      final current = _normalizePath(level.folderName);
      final String moved;
      if (current == source) {
        moved = target;
      } else if (current.startsWith('$source/')) {
        moved = '$target${current.substring(source.length)}';
      } else {
        continue;
      }
      _levels[level.levelId] = level.copyWith(folderName: moved);
      changed = true;
    }
    if (changed) await _save();
  }

  static String _normalizePath(String path) => path.replaceAll(r'\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

  Future<bool> remove(int levelId) async {
    final removed = _levels.remove(levelId) != null;
    if (removed) await _save();
    return removed;
  }

  /// 폴더가 사라진 항목(사용자가 직접 지운 경우 등)을 목록에서 뺀다.
  Future<List<InstalledLevel>> pruneMissing() async {
    final missing = <InstalledLevel>[];
    for (final level in _levels.values.toList()) {
      final path = safeFolderPathOf(level);
      if (path == null || !await Directory(path).exists()) missing.add(level);
    }
    for (final level in missing) {
      _levels.remove(level.levelId);
    }
    if (missing.isNotEmpty) await _save();
    return missing;
  }

  /// 저장이 겹치지 않도록 순서대로 이어 붙인다. 앞의 저장이 실패해도 다음 저장은 시도한다.
  Future<void> _save() {
    _saveChain = _saveChain.catchError((Object _) {}).then((_) => _writeIndex());
    return _saveChain;
  }

  Future<void> _writeIndex() async {
    final snapshot = _levels.values.toList()..sort((a, b) => a.levelId.compareTo(b.levelId));
    final json = const JsonEncoder.withIndent('  ').convert(snapshot.map((l) => l.toJson()).toList());

    // 임시 파일에 쓰고 교체해서, 저장 도중 꺼져도 인덱스가 깨지지 않게 한다.
    final temp = File(p.join(rootPath, '$indexFileName.tmp'));
    await temp.writeAsString(json);
    await temp.rename(p.join(rootPath, indexFileName));
  }
}

abstract final class LevelArchive {
  /// zip을 [destinationDir]에 풀고 풀린 파일의 총 크기를 반환한다.
  /// 모든 파일이 폴더 하나에 들어 있으면 그 단계를 없애서 풀고, __MACOSX 같은 찌꺼기는 건너뛴다.
  /// 무거운 작업이라 Isolate에서 호출한다.
  static int extract(String zipPath, String destinationDir) {
    final root = p.normalize(p.absolute(destinationDir));
    Directory(root).createSync(recursive: true);

    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entries = archive.files.where((f) => !_isJunk(f.name)).toList();

      // 옛 압축 도구가 UTF-8 표시 없이 적은 이름(한글·일본어 등)을 제대로 읽는다.
      final fixName = ZipNames.decoder(entries.map((f) => f.name), hint: _levelText(entries));
      final names = {for (final entry in entries) entry: _normalize(fixName(entry.name))};
      final prefix = _singleRootFolder(names.values);

      var total = 0;
      for (final entry in entries) {
        final relative = names[entry]!.substring(prefix.length);
        if (relative.isEmpty) continue;

        final target = p.normalize(p.join(root, relative));
        // zip slip 방지: 대상 폴더 밖으로 나가는 경로 거부
        if (!p.isWithin(root, target)) {
          throw FormatException(
            tr('zip에 잘못된 경로가 있습니다: ${entry.name}', 'The zip contains an invalid path: ${entry.name}'),
          );
        }

        if (!entry.isFile) {
          Directory(target).createSync(recursive: true);
          continue;
        }

        Directory(p.dirname(target)).createSync(recursive: true);
        final output = OutputFileStream(target);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        total += entry.size;
      }
      return total;
    } finally {
      input.closeSync();
    }
  }

  static String _normalize(String path) => path.replaceAll('\\', '/');

  /// 레벨 파일(.adofai) 안에는 노래·그림 파일 이름이 그대로 적혀 있다.
  /// 깨진 이름을 어떤 코드 페이지로 읽어야 하는지 고를 때 견줘 볼 글이다.
  static String? _levelText(List<ArchiveFile> entries) {
    for (final entry in entries) {
      if (!entry.isFile) continue;
      if (!_normalize(entry.name).toLowerCase().endsWith('.adofai')) continue;
      if (entry.size > ZipNames.hintLimit) continue;

      final bytes = entry.readBytes();
      if (bytes == null) continue;
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
    return null;
  }

  static bool _isJunk(String name) {
    final path = _normalize(name).toLowerCase();
    return path.startsWith('__macosx/') || path == '.ds_store' || path.endsWith('/.ds_store');
  }

  /// 모든 항목이 "Folder/..." 로 시작하면 "Folder/", 아니면 "".
  static String _singleRootFolder(Iterable<String> paths) {
    String? prefix;
    for (final path in paths) {
      final slash = path.indexOf('/');
      if (slash <= 0) return '';
      final first = path.substring(0, slash + 1);
      if (prefix == null) {
        prefix = first;
      } else if (prefix != first) {
        return '';
      }
    }
    return prefix ?? '';
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'level_downloader.dart';
import 'level_library.dart';
import 'models/level.dart';
import 'models/search_models.dart';
import 'tuf_api_client.dart';

enum InstallStage { fetchingInfo, downloading, extracting, completed }

class InstallProgress {
  const InstallProgress(this.levelId, this.stage, [this.download]);

  final int levelId;
  final InstallStage stage;
  final DownloadProgress? download;
}

/// TUF CDN으로 받을 수 없는 레벨 (외부 링크, 창작마당 전용 등).
class LevelNotDownloadableException implements Exception {
  const LevelNotDownloadableException(this.level);

  final Level level;

  /// 대신 안내할 수 있는 링크.
  String? get alternativeLink => [level.dlLink, level.workshopLink, level.legacyDllink].whereType<String>().firstOrNull;

  @override
  String toString() =>
      tr('레벨 ${level.id}은(는) TUF CDN 다운로드 링크가 없습니다.', 'Level ${level.id} has no TUF CDN download link.');
}

class LevelUpdateInfo {
  const LevelUpdateInfo(this.installed, this.remote);

  final InstalledLevel installed;
  final Level remote;
}

/// 레벨 받기, 업데이트, 삭제를 묶은 진입점.
class LevelManager {
  LevelManager(this._api, this.library) : _downloader = LevelDownloader(_api);

  static const _updateCheckConcurrency = 4;
  static const _maxFolderNameLength = 80;

  final TufApiClient _api;
  final LevelLibrary library;
  final LevelDownloader _downloader;

  /// 레벨을 받아서 라이브러리에 넣는다. 이미 있으면 새 버전으로 교체한다.
  Future<InstalledLevel> install(
    Level level, {
    void Function(InstallProgress progress)? onProgress,
    CancelToken? cancelToken,
    String? parentFolder,
  }) async {
    final dlLink = level.dlLink;
    if (dlLink == null || !LevelDownloader.isTufCdnLink(dlLink)) throw LevelNotDownloadableException(level);

    onProgress?.call(InstallProgress(level.id, InstallStage.fetchingInfo));
    final metadata = await _tryGetCdnMetadata(level.id);
    cancelToken?.throwIfCancelled();

    await Directory(library.tempPath).create(recursive: true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final zipPath = p.join(library.tempPath, '${level.id}-$token.zip');
    final stagingDir = p.join(library.tempPath, '${level.id}-$token');

    try {
      await _downloader.download(
        dlLink,
        zipPath,
        onProgress: (d) => onProgress?.call(InstallProgress(level.id, InstallStage.downloading, d)),
        cancelToken: cancelToken,
      );
      cancelToken?.throwIfCancelled();

      onProgress?.call(InstallProgress(level.id, InstallStage.extracting));
      final size = await _extractInBackground(zipPath, stagingDir);
      await _tryDeleteFile(zipPath);
      cancelToken?.throwIfCancelled();

      // 이미 받은 레벨은 사용자가 옮겨 둔 자리를 그대로 쓴다. 새로 받으면 [parentFolder] 아래에 둔다.
      // 기록된 자리가 라이브러리 안의 폴더가 아니면 (루트 자신 등) 쓰지 않는다. 그 자리를 통째로 바꿔 버리기 때문이다.
      final existing = library.get(level.id);
      final folderName = existing != null && library.safeFolderPathOf(existing) != null
          ? existing.folderName
          : [?parentFolder, folderNameFor(level)].join('/');
      final finalDir = p.join(library.rootPath, folderName);
      await Directory(p.dirname(finalDir)).create(recursive: true);
      await _replaceDirectory(stagingDir, finalDir);

      final installed = InstalledLevel(
        levelId: level.id,
        song: level.song,
        artist: level.artist,
        creator: level.creatorDisplay,
        difficulty: level.difficulty?.name,
        fileId: level.fileId ?? '',
        folderName: folderName,
        mainChartPath: await _findMainChart(finalDir, metadata),
        sizeBytes: size,
        installedAt: DateTime.now(),
      );

      await library.set(installed);
      onProgress?.call(InstallProgress(level.id, InstallStage.completed));
      return installed;
    } finally {
      await _tryDeleteFile(zipPath);
      await _tryDeleteDirectory(stagingDir);
    }
  }

  /// 라이브러리에서 빼고 폴더도 지운다.
  Future<bool> uninstall(int levelId) async {
    final installed = library.get(levelId);
    if (installed == null) return false;

    // 폴더 이름이 비었거나 라이브러리 밖을 가리키면 지우지 않고 목록에서만 뺀다 (루트를 통째로 지우지 않게).
    final path = library.safeFolderPathOf(installed);
    if (path != null) {
      final folder = Directory(path);
      if (await folder.exists()) await folder.delete(recursive: true);
    }
    return library.remove(levelId);
  }

  /// 받은 레벨 중 서버에서 파일이 바뀐 것(fileId가 달라진 것)을 찾는다. 조회에 실패한 레벨은 건너뛴다.
  Future<List<LevelUpdateInfo>> checkUpdates() async {
    final installed = library.getAll();
    final updates = <LevelUpdateInfo>[];

    for (var i = 0; i < installed.length; i += _updateCheckConcurrency) {
      final batch = installed.skip(i).take(_updateCheckConcurrency);
      final results = await Future.wait(
        batch.map((item) async {
          try {
            final remote = await _api.getLevel(item.levelId);
            final remoteFileId = remote.fileId;
            if (remote.isDeleted || remoteFileId == null) return null;
            if (remoteFileId.toLowerCase() == item.fileId.toLowerCase()) return null;
            return LevelUpdateInfo(item, remote);
          } on TufApiException {
            return null;
          }
        }),
      );
      updates.addAll(results.whereType<LevelUpdateInfo>());
    }

    return updates..sort((a, b) => a.installed.levelId.compareTo(b.installed.levelId));
  }

  /// zip 압축 해제를 별도 isolate에서 실행한다.
  /// 클로저는 자신이 만들어진 스코프 전체를 붙잡으므로, [install] 안에서 바로 만들면
  /// onProgress(→ 위젯 트리)까지 isolate로 보내려다 실패한다. 경로 두 개만 있는 스코프에서 만든다.
  static Future<int> _extractInBackground(String zipPath, String destinationDir) =>
      Isolate.run(() => LevelArchive.extract(zipPath, destinationDir));

  Future<CdnLevelMetadata?> _tryGetCdnMetadata(int levelId) async {
    try {
      return await _api.getLevelCdnMetadata(levelId);
    } on TufApiException {
      // 메타데이터는 메인 차트를 찾는 데만 쓴다. 없어도 설치는 진행한다.
      return null;
    }
  }

  /// "#{id} {곡 제목}" 형식의 폴더 이름. 예: "#5947 4'33''"
  /// Windows 폴더 이름에 쓸 수 없는 문자는 '_'로 바꾼다.
  @visibleForTesting
  static String folderNameFor(Level level) => safeFolderName('#${level.id} ${level.song}');

  /// 아무 이름(레벨, 팩, 팩 안의 폴더)을 Windows 폴더 이름으로 쓸 수 있게 다듬는다.
  /// '+'는 Windows에서는 쓸 수 있지만 게임이 경로에 '+'가 있는 레벨을 제대로 불러오지 못해서 함께 바꾼다.
  static String safeFolderName(String name) {
    var safe = name.replaceAll(RegExp(r'[<>:"/\\|?*+\x00-\x1F]'), '_').trim();
    if (safe.length > _maxFolderNameLength) safe = safe.substring(0, _maxFolderNameLength);
    // Windows는 끝의 점/공백을 허용하지 않는다.
    safe = safe.replaceAll(RegExp(r'[. ]+$'), '');
    return safe.isEmpty ? '_' : safe;
  }

  /// [source]를 [target] 자리로 옮긴다. 기존 폴더는 백업했다가 성공하면 지우고, 실패하면 되돌린다.
  Future<void> _replaceDirectory(String source, String target) async {
    if (!await Directory(target).exists()) {
      await Directory(source).rename(target);
      return;
    }

    final backup = p.join(library.tempPath, 'backup-${DateTime.now().microsecondsSinceEpoch}');
    await Directory(target).rename(backup);
    try {
      await Directory(source).rename(target);
    } catch (_) {
      await Directory(backup).rename(target);
      rethrow;
    }
    await _tryDeleteDirectory(backup);
  }

  /// 메인 .adofai의 상대 경로. CDN 메타데이터를 우선하고, 없으면 가장 큰 .adofai를 고른다.
  static Future<String?> _findMainChart(String folder, CdnLevelMetadata? metadata) async {
    final charts = <({String relative, int size})>[];
    await for (final entity in Directory(folder).list(recursive: true, followLinks: false)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.adofai') {
        charts.add((
          relative: p.relative(entity.path, from: folder).replaceAll('\\', '/'),
          size: await entity.length(),
        ));
      }
    }
    if (charts.isEmpty) return null;

    // 압축 해제 시 최상위 폴더를 없앴을 수 있으므로 끝부분이 일치하는지로 비교한다.
    final target = metadata?.targetLevelRelativePath?.replaceAll('\\', '/').toLowerCase();
    if (target != null && target.isNotEmpty) {
      final matches = charts.where((c) {
        final relative = c.relative.toLowerCase();
        return target == relative || target.endsWith('/$relative');
      }).toList()..sort((a, b) => b.relative.length.compareTo(a.relative.length));
      if (matches.isNotEmpty) return matches.first.relative;
    }

    charts.sort((a, b) => b.size.compareTo(a.size));
    return charts.first.relative;
  }

  static Future<void> _tryDeleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 정리 실패는 무시
    }
  }

  static Future<void> _tryDeleteDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // 정리 실패는 무시
    }
  }
}

/// %AppData%\TUFApp\settings.json 에 저장되는 설정. C# 버전과 같은 파일을 쓴다.
class AppSettings {
  AppSettings({required this.libraryPath, this.language});

  String libraryPath;

  /// 고른 화면 언어. null이면 시스템 언어를 따른다.
  AppLanguage? language;

  static Future<String> _settingsDirectory() async {
    final appData = Platform.environment['APPDATA'];
    if (Platform.isWindows && appData != null) return p.join(appData, 'TUFApp');
    return (await getApplicationSupportDirectory()).path;
  }

  static Future<String> defaultLibraryPath() async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'TUFApp', 'Levels');

  static Future<AppSettings> load() async {
    final file = File(p.join(await _settingsDirectory(), 'settings.json'));
    String? path;
    AppLanguage? language;
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, dynamic>) {
          if (json['libraryPath'] case final String value when value.trim().isNotEmpty) path = value;
          language = AppLanguage.fromCode(json['language']);
        }
      }
    } on FormatException {
      // 설정 파일이 깨졌으면 기본값으로 시작한다.
    }
    return AppSettings(libraryPath: path ?? await defaultLibraryPath(), language: language);
  }

  Future<void> save() async {
    final dir = Directory(await _settingsDirectory());
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'settings.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'libraryPath': libraryPath, 'language': ?language?.code}),
    );
  }
}

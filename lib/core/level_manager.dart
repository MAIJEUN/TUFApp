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

/// A level that can't be downloaded from the TUF CDN (external link, Workshop only, etc.).
class LevelNotDownloadableException implements Exception {
  const LevelNotDownloadableException(this.level);

  final Level level;

  /// A link to suggest instead.
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

/// Entry point for downloading, updating and deleting levels.
class LevelManager {
  LevelManager(this._api, this.library) : _downloader = LevelDownloader(_api);

  static const _updateCheckConcurrency = 4;
  static const _maxFolderNameLength = 80;

  final TufApiClient _api;
  final LevelLibrary library;
  final LevelDownloader _downloader;

  /// Downloads a level into the library, replacing the existing version if present.
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

      // A level already in the library stays where the user moved it; a new one goes under [parentFolder].
      // A recorded location that isn't a folder inside the library (like the
      // root) is not used, since it would be replaced wholesale.
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

  /// Removes the level from the index and deletes its folder.
  Future<bool> uninstall(int levelId) async {
    final installed = library.get(levelId);
    if (installed == null) return false;

    // If the folder name is empty or points outside the library, only remove the entry (never delete the root).
    final path = library.safeFolderPathOf(installed);
    if (path != null) {
      final folder = Directory(path);
      if (await folder.exists()) await folder.delete(recursive: true);
    }
    return library.remove(levelId);
  }

  /// Finds downloaded levels whose file changed on the server (different fileId). Levels that fail to load are skipped.
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

  /// Extracts the zip in a separate isolate.
  /// A closure captures its whole enclosing scope, so creating it inside [install] would try to send
  /// onProgress (and with it the widget tree) to the isolate and fail. It is created in a scope holding only two paths.
  static Future<int> _extractInBackground(String zipPath, String destinationDir) =>
      Isolate.run(() => LevelArchive.extract(zipPath, destinationDir));

  Future<CdnLevelMetadata?> _tryGetCdnMetadata(int levelId) async {
    try {
      return await _api.getLevelCdnMetadata(levelId);
    } on TufApiException {
      // Metadata is only used to find the main chart; installing works without it.
      return null;
    }
  }

  /// Folder name in the form "#{id} {song}", e.g. "#5947 4'33''".
  /// Characters not allowed in Windows folder names become '_'.
  @visibleForTesting
  static String folderNameFor(Level level) => safeFolderName('#${level.id} ${level.song}');

  /// Makes any name (level, pack, folder in a pack) usable as a Windows folder name.
  /// '+' is allowed on Windows, but the game can't load levels whose path contains it, so it is replaced too.
  static String safeFolderName(String name) {
    var safe = name.replaceAll(RegExp(r'[<>:"/\\|?*+\x00-\x1F]'), '_').trim();
    if (safe.length > _maxFolderNameLength) safe = safe.substring(0, _maxFolderNameLength);
    // Windows doesn't allow trailing dots or spaces.
    safe = safe.replaceAll(RegExp(r'[. ]+$'), '');
    return safe.isEmpty ? '_' : safe;
  }

  /// Moves [source] to [target]. The existing folder is backed up, deleted on success and restored on failure.
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

  /// Relative path of the main .adofai. Prefers the CDN metadata, otherwise the largest .adofai file.
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

    // The top-level folder may have been flattened during extraction, so compare by suffix.
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
      // Ignore cleanup failures.
    }
  }

  static Future<void> _tryDeleteDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Ignore cleanup failures.
    }
  }
}

/// Settings stored in %AppData%\TUFApp\settings.json, shared with the C# version.
class AppSettings {
  AppSettings({required this.libraryPath, this.language});

  String libraryPath;

  /// The chosen UI language. null follows the system language.
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
      // Start with defaults if the settings file is broken.
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

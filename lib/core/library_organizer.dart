import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'l10n.dart';
import 'level_library.dart';

/// An item in the library folder, mirroring the folders on disk.
sealed class LibraryEntry {
  const LibraryEntry({required this.name, required this.relativePath});

  /// Display name (the folder name).
  final String name;

  /// Path relative to the library root, always '/'-separated.
  final String relativePath;
}

/// A level downloaded by the app.
class LevelEntry extends LibraryEntry {
  const LevelEntry({required super.name, required super.relativePath, required this.level});

  final InstalledLevel level;
}

/// A folder with a .adofai file that the app didn't download. Shown so levels added by hand can be organized too.
class ExternalLevelEntry extends LibraryEntry {
  const ExternalLevelEntry({required super.name, required super.relativePath});
}

/// A folder holding levels. Counts cover direct children only.
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

  /// The pack's icon if the folder came from a pack download.
  final String? iconUrl;

  bool get isEmpty => folderCount == 0 && levelCount == 0;
}

/// Info attached to a folder; currently the icon and id of the pack it came from.
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

/// Contents of one folder: folders first, then levels, by name.
class FolderContents {
  const FolderContents({required this.path, required this.folders, required this.levels});

  final String path;
  final List<FolderEntry> folders;

  /// Downloaded levels ([LevelEntry]) and levels added by hand ([ExternalLevelEntry]).
  final List<LibraryEntry> levels;

  bool get isEmpty => folders.isEmpty && levels.isEmpty;
  List<LibraryEntry> get all => [...folders, ...levels];
}

/// Thrown for invalid names or paths.
class LibraryOperationException implements Exception {
  const LibraryOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Explorer-like operations on the library folder: create, rename, move and delete folders.
///
/// Folders are real folders on disk. Moving a level moves its folder
/// and updates [InstalledLevel.folderName] in the index.
class LibraryOrganizer {
  const LibraryOrganizer(this.library);

  /// Characters not allowed in Windows folder names.
  static final _illegalCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  final LevelLibrary library;

  String get rootPath => library.rootPath;

  /// Turns a library-relative path into a full path, rejecting paths outside the root.
  String fullPath(String relativePath) {
    final root = p.normalize(library.rootPath);
    final full = p.normalize(p.join(root, relativePath));
    if (full != root && !p.isWithin(root, full)) {
      throw LibraryOperationException(l10n.cantWorkOutsideThe);
    }
    return full;
  }

  /// Lists the contents of [relativePath] (empty for the root).
  Future<FolderContents> list(String relativePath) async {
    final directory = Directory(fullPath(relativePath));
    if (!await directory.exists()) {
      return FolderContents(path: relativePath, folders: const [], levels: const []);
    }

    final levelsByPath = {for (final level in library.getAll()) _normalize(level.folderName): level};
    final folders = <FolderEntry>[];
    final levels = <LibraryEntry>[];

    // Each folder has to be inspected, which is noticeably slow one by one in large folders, so run them together.
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

  /// Decides whether a folder is a level or a plain folder.
  Future<LibraryEntry> _entryFor(Directory child, String parentPath, Map<String, InstalledLevel> levelsByPath) async {
    final name = p.basename(child.path);
    final relative = _join(parentPath, name);

    final level = levelsByPath[relative];
    if (level != null) return LevelEntry(name: name, relativePath: relative, level: level);
    if (await _looksLikeLevel(child)) return ExternalLevelEntry(name: name, relativePath: relative);
    return _folderEntry(child, name, relative, levelsByPath);
  }

  /// Counts direct subfolders and levels (one level deep).
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

  /// File holding folder info. It lives inside the folder, so it follows renames and moves.
  static const folderInfoFileName = '.tufapp-folder.json';

  /// Info attached to a folder (pack icon etc.), or null if missing or unreadable.
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

  /// Attaches info to a folder, creating it if needed. Failures are ignored since they don't affect downloads.
  static Future<void> writeFolderInfo(String folderPath, FolderInfo info) async {
    final file = File(p.join(folderPath, folderInfoFileName));
    try {
      await Directory(folderPath).create(recursive: true);
      // Windows can't overwrite hidden files, so delete and rewrite.
      if (await file.exists()) await file.delete();
      await file.writeAsString(jsonEncode(info.toJson()));
      // Hide it so it doesn't show up among level files in Explorer.
      if (Platform.isWindows) await Process.run('attrib', ['+h', file.path]);
    } on FileSystemException {
      // Ignore.
    } on ProcessException {
      // Not being able to hide it is fine.
    }
  }

  /// Subfolders, excluding hidden and temporary ones.
  static Future<List<Directory>> _childDirectories(Directory directory) async {
    final result = <Directory>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory && !p.basename(entity.path).startsWith('.')) result.add(entity);
      }
    } on FileSystemException {
      // Skip folders without access.
    }
    return result;
  }

  /// A folder with a .adofai file directly inside is a level folder.
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

  /// Walks every folder path, including folders without levels (used to pick a move target, etc.).
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

  Future<String> createFolder(String parent, String name) async {
    final safe = _validateName(name);
    final relative = _join(parent, safe);
    final directory = Directory(fullPath(relative));
    if (await directory.exists()) {
      throw LibraryOperationException(l10n.aFolderNamedAlready(safe));
    }
    await directory.create(recursive: true);
    return relative;
  }

  /// Renames a folder or level folder; paths of levels inside follow.
  Future<String> rename(LibraryEntry entry, String newName) async {
    final safe = _validateName(newName);
    if (safe == entry.name) return entry.relativePath;

    final parent = _parentOf(entry.relativePath);
    final target = _join(parent, safe);
    await _moveDirectory(entry.relativePath, target, l10n.alreadyExists(safe));
    return target;
  }

  /// Moves a folder or level into [targetFolder] (empty for the root).
  Future<String> move(LibraryEntry entry, String targetFolder) async {
    if (_parentOf(entry.relativePath) == _normalize(targetFolder)) return entry.relativePath;
    if (entry is FolderEntry && _isInside(entry.relativePath, targetFolder)) {
      throw LibraryOperationException(l10n.cantMoveAFolder);
    }

    final target = _join(targetFolder, entry.name);
    await _moveDirectory(entry.relativePath, target, l10n.alreadyExistsThere(entry.name));
    return target;
  }

  /// Renames folders whose names contain characters the game can't load ('+'). Returns how many were renamed.
  ///
  /// Level folders themselves are renamed, but their contents (music, chart files) are not,
  /// because charts find their music by file name. Folders that can't be renamed (open in the game, etc.) are skipped.
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

  /// If [name] already exists in [parent], finds a free name like "name (2)".
  Future<String> _uniquePath(String parent, String name) async {
    var candidate = _join(parent, name);
    for (var i = 2; await Directory(fullPath(candidate)).exists(); i++) {
      candidate = _join(parent, '$name ($i)');
    }
    return candidate;
  }

  /// Deletes a folder or level folder entirely, removing indexed levels
  /// from the index. Returns how many levels were removed.
  Future<int> delete(LibraryEntry folder) async {
    final directory = Directory(fullPath(folder.relativePath));
    final inside = _levelsInside(folder.relativePath);
    if (await directory.exists()) await directory.delete(recursive: true);
    for (final level in inside) {
      await library.remove(level.levelId);
    }
    return inside.length;
  }

  /// Performs a folder move or rename and updates the paths in the index.
  Future<void> _moveDirectory(String from, String to, String existsMessage) async {
    final source = Directory(fullPath(from));
    final destination = Directory(fullPath(to));
    if (!await source.exists()) throw LibraryOperationException(l10n.folderNotFound);
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

  /// Replaces characters the game can't load (a '+' in the path breaks level loading).
  static String replaceUnloadable(String name) => name.replaceAll('+', '_');

  static String _validateName(String name) {
    final trimmed = replaceUnloadable(name).trim().replaceAll(RegExp(r'[. ]+$'), '');
    if (trimmed.isEmpty) throw LibraryOperationException(l10n.pleaseEnterAName);
    if (_illegalCharacters.hasMatch(trimmed)) {
      throw LibraryOperationException(l10n.namesCannotContain);
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

  /// Normalizes separators to '/' and trims leading and trailing ones.
  static String _normalize(String path) => path.replaceAll(r'\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

  /// Case-insensitive name order.
  static int _compareNames(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
}

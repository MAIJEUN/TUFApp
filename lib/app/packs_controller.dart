import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/l10n.dart';
import '../core/level_manager.dart';
import '../core/library_organizer.dart';
import '../core/models/level.dart';
import '../core/models/pack.dart';
import '../core/tuf_api_client.dart';
import 'controllers.dart';

/// A level to download and the library folder to put it in.
typedef PackDownloadItem = ({Level level, String folder});

/// Downloads several levels in order (a whole pack or one folder).
class PackDownload extends ChangeNotifier {
  PackDownload({
    required this.scope,
    required this.label,
    required this.items,
    this.folderLevels = const {},
    this.packId,
  });

  /// The pack the levels belong to (also for a single folder). Pack cards use it to show a progress bar.
  final String? packId;

  /// Which button started it (pack id or folder id); that button turns into the progress indicator.
  final Object scope;

  /// e.g. "AWC Original Levels" or "AWC 2023"
  final String label;
  final List<PackDownloadItem> items;

  /// Folder id → levels in this job inside that folder (including
  /// subfolders), so folder buttons show their own progress.
  final Map<int, List<int>> folderLevels;

  int done = 0;
  int failed = 0;
  bool cancelled = false;
  bool finished = false;

  /// Finished levels (downloaded or failed).
  final Set<int> finishedIds = {};
  final Set<int> failedIds = {};

  int? currentLevelId;

  int get total => items.length;
  double get fraction => total == 0 ? 1 : (done + failed) / total;

  /// Overall progress, including the current level's progress ([current], 0–1) so the bar doesn't jump in steps.
  double progress(double current) {
    if (total == 0) return 1;
    final running = currentLevelId != null && !finishedIds.contains(currentLevelId) ? current : 0.0;
    return ((finishedIds.length + running) / total).clamp(0.0, 1.0);
  }

  /// Levels handled by the [scope] button, or null if it isn't part of this job.
  List<int>? levelsFor(Object scope) {
    if (scope == this.scope) return [for (final item in items) item.level.id];
    return scope is int ? folderLevels[scope] : null;
  }

  /// Whether [scope] still has levels left. A finished folder button turns back into a button.
  bool isActiveFor(Object scope) {
    final ids = levelsFor(scope);
    return ids != null && ids.isNotEmpty && !finished && !ids.every(finishedIds.contains);
  }

  void _start(int levelId) {
    currentLevelId = levelId;
    notifyListeners();
  }

  void _advance(int levelId, {required bool ok}) {
    finishedIds.add(levelId);
    // Levels interrupted by Stop are not counted as failures.
    if (ok) {
      done++;
    } else if (!cancelled) {
      failed++;
      failedIds.add(levelId);
    }
    notifyListeners();
  }

  void _finish() {
    finished = true;
    currentLevelId = null;
    notifyListeners();
  }
}

/// Packs page: searching packs, opening one, and downloading a pack or folder.
class PacksController extends ChangeNotifier {
  PacksController({required this.api, required this.levels, required this.installs, required this.onStatus});

  final TufApiClient api;
  final LevelsController levels;
  final InstallCenter installs;
  final void Function(String message) onStatus;

  /// Records closed packs so "forward" can reopen them.
  NavigationHistory? history;

  static const _pageSize = 30;
  static const _searchDelay = Duration(milliseconds: 400);

  // ── List ──

  List<LevelPack> packs = const [];
  int total = 0;
  bool isSearching = false;
  bool isLoadingMore = false;
  bool hasSearched = false;
  String? error;

  /// Why loading the next page failed. While set, it is not requested again until [retryLoadMore].
  String? loadMoreError;

  String query = '';
  PackSort sort = PackSort.recent;
  bool descending = true;

  int _requestId = 0;
  Timer? _searchTimer;

  bool get hasMore => packs.length < total;

  /// Loads once, the first time the page is shown.
  void ensureLoaded() {
    if (!hasSearched && !isSearching) search();
  }

  /// Searches once typing pauses.
  void setQuery(String value) {
    if (value == query) return;
    query = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDelay, search);
    notifyListeners();
  }

  void setSort(PackSort value) {
    if (value == sort) return;
    sort = value;
    search();
  }

  void toggleOrder() {
    descending = !descending;
    search();
  }

  Future<void> search() async {
    _searchTimer?.cancel();
    final id = ++_requestId;
    isSearching = true;
    error = null;
    loadMoreError = null;
    notifyListeners();

    try {
      final result = await api.searchPacks(query: query, sort: sort, descending: descending, limit: _pageSize);
      if (id != _requestId) return;
      packs = result.packs;
      total = result.total;
    } on Object catch (e) {
      // Unexpected errors too, so the list never stays loading forever.
      if (id != _requestId) return;
      error = _messageOf(e);
      packs = const [];
      total = 0;
    }
    isSearching = false;
    hasSearched = true;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (isSearching || isLoadingMore || !hasMore || loadMoreError != null) return;
    final id = _requestId;
    isLoadingMore = true;
    notifyListeners();

    try {
      final result = await api.searchPacks(
        query: query,
        sort: sort,
        descending: descending,
        offset: packs.length,
        limit: _pageSize,
      );
      if (id != _requestId) return;
      final known = {for (final pack in packs) pack.id};
      packs = [...packs, ...result.packs.where((pack) => !known.contains(pack.id))];
      total = result.total;
    } on Object catch (e) {
      if (id == _requestId) loadMoreError = _messageOf(e);
    } finally {
      if (id == _requestId) {
        isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  static String _messageOf(Object error) => error is TufApiException ? error.message : '$error';

  /// Retries a failed next page ("Retry" at the bottom of the list).
  Future<void> retryLoadMore() {
    loadMoreError = null;
    return loadMore();
  }

  // ── Single pack ──

  /// The opened pack. Its header uses the list values while the contents load.
  LevelPack? openedPack;
  LevelPackDetail? detail;
  bool isLoadingDetail = false;
  String? detailError;

  /// Ids of expanded folders.
  final Set<int> expanded = {};
  int _detailRequestId = 0;

  Future<void> open(LevelPack pack) async {
    history?.clearForward();
    final id = ++_detailRequestId;
    openedPack = pack;
    detailError = null;
    expanded.clear();

    // Show contents the list card already fetched without waiting.
    final cached = _details[pack.id];
    detail = cached;
    isLoadingDetail = cached == null;
    if (cached != null) _showDetail(cached);
    notifyListeners();
    if (cached != null) return;

    try {
      final result = await _fetchDetail(pack.id);
      if (id != _detailRequestId) return;
      _showDetail(result);
    } on Object catch (e) {
      if (id != _detailRequestId) return;
      detailError = _messageOf(e);
    }
    isLoadingDetail = false;
    notifyListeners();
  }

  /// Opens a pack by link code (or id), including packs not in the list such
  /// as tournament packs on profiles. Returns true if opened.
  Future<bool> openById(String id) async {
    final detail = await detailFor(id);
    if (detail == null) return false;
    await open(detail.pack);
    return true;
  }

  void _showDetail(LevelPackDetail result) {
    detail = result;
    openedPack = result.pack;
    unawaited(_tagExistingPackFolder(result.pack));
    // Like the website, only the first top-level folder starts expanded.
    final firstFolder = result.items.whereType<PackFolder>().firstOrNull;
    if (firstFolder != null) expanded.add(firstFolder.id);
  }

  Future<void> reloadDetail() async {
    final pack = openedPack;
    if (pack == null) return;
    _details.remove(pack.id);
    _detailRequests.remove(pack.id);
    await open(pack);
  }

  // ── Pack contents cache ──

  /// List cards fetch pack contents to show the difficulties of the remaining levels; limit how many run at once.
  static const _maxConcurrentDetails = 4;

  final Map<String, LevelPackDetail> _details = {};
  final Map<String, Future<LevelPackDetail?>> _detailRequests = {};
  final List<Completer<void>> _detailQueue = [];
  int _runningDetails = 0;

  LevelPackDetail? cachedDetail(String id) => _details[id];

  /// Fetches pack contents once. Returns null on failure and tries again next time.
  Future<LevelPackDetail?> detailFor(String id) => _detailRequests[id] ??= () async {
    try {
      return await _fetchDetail(id);
    } on TufApiException {
      _detailRequests.remove(id);
      return null;
    }
  }();

  Future<LevelPackDetail> _fetchDetail(String id) async {
    if (_details[id] case final cached?) return cached;
    while (_runningDetails >= _maxConcurrentDetails) {
      final turn = Completer<void>();
      _detailQueue.add(turn);
      await turn.future;
    }
    _runningDetails++;
    try {
      final result = await api.getPack(id, resolveLevel: _resolveLevel);
      // Don't cache results fetched before the difficulty list arrived; their icons would be missing.
      if (levels.catalog != null) _details[id] = result;
      return result;
    } finally {
      _runningDetails--;
      if (_detailQueue.isNotEmpty) _detailQueue.removeAt(0).complete();
    }
  }

  void close() {
    if (openedPack case final pack?) history?.recordBack(() => open(pack));
    _detailRequestId++;
    openedPack = null;
    detail = null;
    detailError = null;
    isLoadingDetail = false;
    notifyListeners();
  }

  void toggleFolder(int id) {
    expanded.contains(id) ? expanded.remove(id) : expanded.add(id);
    notifyListeners();
  }

  void setAllExpanded(bool value) {
    expanded.clear();
    if (value) {
      void addAll(List<PackNode> nodes) {
        for (final folder in nodes.whereType<PackFolder>()) {
          expanded.add(folder.id);
          addAll(folder.children);
        }
      }

      addAll(detail?.items ?? const []);
    }
    notifyListeners();
  }

  bool get allExpanded {
    var all = true;
    void check(List<PackNode> nodes) {
      for (final folder in nodes.whereType<PackFolder>()) {
        if (!expanded.contains(folder.id)) all = false;
        check(folder.children);
      }
    }

    check(detail?.items ?? const []);
    return all;
  }

  /// Pack responses only carry difficulty and tag ids; fill them in from the loaded catalogs.
  Level _resolveLevel(Level level) {
    final difficulty = level.difficulty ?? levels.catalog?.byId(level.diffId);
    final tagCatalog = levels.tagCatalog;
    final tags = tagCatalog == null
        ? level.tags
        : [
            for (final tag in level.tags)
              if (tagCatalog.byId(tag.id) case final item?)
                tag.withInfo(name: item.name, icon: item.icon, color: item.color)
              else
                tag,
          ];
    return level.copyWith(difficulty: difficulty, tags: tags);
  }

  // ── Pack downloads ──

  PackDownload? download;

  /// Downloadable levels in a pack or folder that aren't in the library
  /// yet. The library mirrors the pack's folder layout.
  List<PackDownloadItem> downloadItems(LevelPack pack, List<PackNode> nodes, {List<String> path = const []}) {
    final items = <PackDownloadItem>[];
    final seen = <int>{};

    void walk(List<PackNode> nodes, List<String> path) {
      for (final node in nodes) {
        switch (node) {
          case PackFolder():
            walk(node.children, [...path, LevelManager.safeFolderName(node.name)]);
          case PackLevelEntry(:final level):
            if (!seen.add(level.id)) continue;
            if (installs.stateOf(level) != LevelInstallState.notInstalled) continue;
            items.add((level: level, folder: path.join('/')));
        }
      }
    }

    walk(nodes, [LevelManager.safeFolderName(pack.name), ...path]);
    return items;
  }

  /// The folder path of [target] inside the pack (for folder downloads).
  List<String> folderPathOf(PackFolder target) {
    List<String>? find(List<PackNode> nodes, List<String> path) {
      for (final folder in nodes.whereType<PackFolder>()) {
        final here = [...path, LevelManager.safeFolderName(folder.name)];
        if (folder.id == target.id) return path;
        final inner = find(folder.children, here);
        if (inner != null) return inner;
      }
      return null;
    }

    return find(detail?.items ?? const [], const []) ?? const [];
  }

  /// Path of the pack's folder in the library ([LevelManager.safeFolderName]), or null without a library.
  String? _packFolderPath(LevelPack pack) {
    final root = installs.manager?.library.rootPath;
    return root == null ? null : p.join(root, LevelManager.safeFolderName(pack.name));
  }

  /// Marks the pack folder with the pack's icon (creating the folder if needed).
  Future<void> _tagPackFolder(LevelPack pack) async {
    final folder = _packFolderPath(pack);
    if (folder == null || pack.iconUrl == null) return;
    await LibraryOrganizer.writeFolderInfo(folder, FolderInfo(iconUrl: pack.iconUrl, packId: pack.id));
  }

  /// Marks an existing pack folder when the pack is opened, so folders downloaded earlier get the icon too.
  Future<void> _tagExistingPackFolder(LevelPack pack) async {
    final folder = _packFolderPath(pack);
    if (folder == null || pack.iconUrl == null || !await Directory(folder).exists()) return;
    if ((await LibraryOrganizer.readFolderInfo(folder))?.iconUrl == pack.iconUrl) return;
    await _tagPackFolder(pack);
  }

  /// Level id → ids of the folders containing it, outermost first. A repeated level uses its first position.
  Map<int, List<int>> _folderAncestors() {
    final result = <int, List<int>>{};
    void walk(List<PackNode> nodes, List<int> path) {
      for (final node in nodes) {
        switch (node) {
          case PackFolder():
            walk(node.children, [...path, node.id]);
          case PackLevelEntry(:final level):
            result.putIfAbsent(level.id, () => path);
        }
      }
    }

    walk(detail?.items ?? const [], const []);
    return result;
  }

  /// Only one pack download runs at a time.
  bool get isDownloading => download != null;

  /// Downloads in order. The pressed button ([scope]) shows progress and turns back into a button when done.
  Future<void> startDownload(Object scope, String label, List<PackDownloadItem> items) async {
    if (items.isEmpty || isDownloading) return;

    final ancestors = _folderAncestors();
    final ids = {for (final item in items) item.level.id};
    final folderLevels = <int, List<int>>{};
    for (final id in ids) {
      for (final folder in ancestors[id] ?? const <int>[]) {
        folderLevels.putIfAbsent(folder, () => []).add(id);
      }
    }

    final job = PackDownload(
      scope: scope,
      label: label,
      items: items,
      folderLevels: folderLevels,
      packId: openedPack?.id,
    );
    download = job;
    notifyListeners();

    // Mark the pack folder with the pack's icon so it is recognizable in the library.
    if (openedPack case final pack?) await _tagPackFolder(pack);

    for (final item in items) {
      if (job.cancelled) break;
      final folders = ancestors[item.level.id] ?? const <int>[];
      // Expand the folders containing the level being downloaded.
      if (!expanded.containsAll(folders)) {
        expanded.addAll(folders);
        notifyListeners();
      }
      job._start(item.level.id);
      final ok = await installs.install(item.level, parentFolder: item.folder);
      job._advance(item.level.id, ok: ok);
      // Collapse finished folders, innermost first.
      final done = [
        for (final folder in folders.reversed)
          if (folderLevels[folder]!.every(job.finishedIds.contains)) folder,
      ];
      if (!job.cancelled && done.isNotEmpty) {
        expanded.removeAll(done);
        notifyListeners();
      }
    }
    job._finish();

    final failed = job.failed > 0 ? tr(', 실패 ${job.failed}개', ', ${job.failed} failed') : '';
    onStatus(
      job.cancelled
          ? tr(
              "'${job.label}' 받기를 멈췄습니다 (${job.done}/${job.total}개 받음$failed)",
              "Stopped downloading '${job.label}' (${job.done}/${job.total} done$failed)",
            )
          : tr(
              "'${job.label}' 받기 완료: ${job.done}개$failed",
              "Downloaded '${job.label}': ${job.done} ${plural(job.done, 'level')}$failed",
            ),
    );
    download = null;
    notifyListeners();
  }

  void cancelDownload() {
    final job = download;
    if (job == null || job.finished) return;
    job.cancelled = true;
    // Also stop the level currently downloading.
    for (final item in job.items) {
      installs.jobFor(item.level.id)?.cancel();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }
}

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

/// 받을 레벨 하나와 라이브러리 안에서 넣을 폴더.
typedef PackDownloadItem = ({Level level, String folder});

/// 여러 레벨을 차례로 받는 작업 (팩 전체 또는 폴더 하나).
class PackDownload extends ChangeNotifier {
  PackDownload({
    required this.scope,
    required this.label,
    required this.items,
    this.folderLevels = const {},
    this.packId,
  });

  /// 받고 있는 레벨들이 든 팩 (폴더만 받아도 그 팩). 목록의 팩 카드가 진행 막대를 보여줄 때 쓴다.
  final String? packId;

  /// 어느 버튼에서 시작했는지 (팩이면 팩 id, 폴더면 폴더 id). 그 버튼이 진행률로 바뀐다.
  final Object scope;

  /// 예: "AWC Original Levels" 또는 "AWC 2023"
  final String label;
  final List<PackDownloadItem> items;

  /// 폴더 id → 이번에 받는 레벨 중 그 폴더(하위 폴더 포함) 안에 있는 것. 폴더 버튼도 자기 몫의 진행률을 보여준다.
  final Map<int, List<int>> folderLevels;

  int done = 0;
  int failed = 0;
  bool cancelled = false;
  bool finished = false;

  /// 끝난 레벨 (받았거나 실패).
  final Set<int> finishedIds = {};
  final Set<int> failedIds = {};

  /// 지금 받고 있는 레벨.
  int? currentLevelId;

  int get total => items.length;
  double get fraction => total == 0 ? 1 : (done + failed) / total;

  /// 전체 진행률. 지금 받는 레벨의 진행률([current], 0~1)까지 더해서 막대가 계단처럼 뛰지 않게 한다.
  double progress(double current) {
    if (total == 0) return 1;
    final running = currentLevelId != null && !finishedIds.contains(currentLevelId) ? current : 0.0;
    return ((finishedIds.length + running) / total).clamp(0.0, 1.0);
  }

  /// [scope] 버튼이 맡은 레벨들. 이번 작업에 포함되지 않으면 null.
  List<int>? levelsFor(Object scope) {
    if (scope == this.scope) return [for (final item in items) item.level.id];
    return scope is int ? folderLevels[scope] : null;
  }

  /// [scope]의 몫이 아직 남았는지. 다 끝난 폴더 버튼은 다시 버튼으로 돌아간다.
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
    // 멈추기로 끊긴 레벨은 실패로 세지 않는다.
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

/// '레벨 팩' 화면: 팩 목록 검색, 팩 하나 열어 보기, 팩/폴더째 받기.
class PacksController extends ChangeNotifier {
  PacksController({required this.api, required this.levels, required this.installs, required this.onStatus});

  final TufApiClient api;
  final LevelsController levels;
  final InstallCenter installs;
  final void Function(String message) onStatus;

  static const _pageSize = 30;
  static const _searchDelay = Duration(milliseconds: 400);

  // ── 목록 ──

  List<LevelPack> packs = const [];
  int total = 0;
  bool isSearching = false;
  bool isLoadingMore = false;
  bool hasSearched = false;
  String? error;

  /// 다음 묶음을 받다가 실패한 이유. 있으면 저절로 다시 받지 않고 [retryLoadMore]를 기다린다.
  String? loadMoreError;

  String query = '';
  PackSort sort = PackSort.recent;
  bool descending = true;

  int _requestId = 0;
  Timer? _searchTimer;

  bool get hasMore => packs.length < total;

  /// 처음 화면을 열었을 때 한 번만 불러온다.
  void ensureLoaded() {
    if (!hasSearched && !isSearching) search();
  }

  /// 입력이 멈추면 검색한다.
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
    } on TufApiException catch (e) {
      if (id != _requestId) return;
      error = e.message;
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
    } on TufApiException catch (e) {
      if (id == _requestId) loadMoreError = e.message;
    } finally {
      if (id == _requestId) {
        isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// 실패한 다음 묶음을 다시 받는다 (목록 맨 아래의 '다시 시도').
  Future<void> retryLoadMore() {
    loadMoreError = null;
    return loadMore();
  }

  // ── 팩 하나 ──

  /// 열어 둔 팩. 내용을 받는 동안에도 머리글은 목록에서 가져온 값으로 보여준다.
  LevelPack? openedPack;
  LevelPackDetail? detail;
  bool isLoadingDetail = false;
  String? detailError;

  /// 펼쳐 둔 폴더 id.
  final Set<int> expanded = {};
  int _detailRequestId = 0;

  Future<void> open(LevelPack pack) async {
    final id = ++_detailRequestId;
    openedPack = pack;
    detailError = null;
    expanded.clear();

    // 목록 카드가 이미 받아 둔 내용이면 기다리지 않고 바로 보여준다.
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
    } on TufApiException catch (e) {
      if (id != _detailRequestId) return;
      detailError = e.message;
    }
    isLoadingDetail = false;
    notifyListeners();
  }

  /// 팩 링크 코드(또는 id)로 연다. 프로필의 대회 팩처럼 목록에 없는 팩도 열 수 있다. 열었으면 true.
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
    // 웹처럼 처음에는 맨 위 폴더만 펼쳐 둔다.
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

  // ── 팩 내용 받아 두기 ──

  /// 목록 카드가 나머지 레벨의 난이도를 보여주려고 팩 내용을 받는다. 한꺼번에 몰리지 않게 동시에 몇 개만.
  static const _maxConcurrentDetails = 4;

  final Map<String, LevelPackDetail> _details = {};
  final Map<String, Future<LevelPackDetail?>> _detailRequests = {};
  final List<Completer<void>> _detailQueue = [];
  int _runningDetails = 0;

  /// 이미 받아 둔 팩 내용.
  LevelPackDetail? cachedDetail(String id) => _details[id];

  /// 팩 내용을 (한 번만) 받는다. 실패하면 null이고, 다음에 다시 시도한다.
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
      // 난이도 목록이 오기 전에 받았으면 카드에 아이콘이 빠지므로 기억하지 않는다.
      if (levels.catalog != null) _details[id] = result;
      return result;
    } finally {
      _runningDetails--;
      if (_detailQueue.isNotEmpty) _detailQueue.removeAt(0).complete();
    }
  }

  void close() {
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

  /// 모든 폴더를 펼치거나 접는다.
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

  /// 팩 응답의 레벨은 난이도와 태그가 id로만 온다. 받아 둔 목록에서 찾아 채운다.
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

  // ── 팩째 받기 ──

  PackDownload? download;

  /// 팩이나 폴더 안에서 아직 받지 않았고 받을 수 있는 레벨. 라이브러리 안의 폴더 구조는 팩과 같게 만든다.
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

  /// [nodes]가 팩 안에서 놓인 폴더 경로 (폴더 받기용).
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

  /// 라이브러리의 팩 이름 폴더([LevelManager.safeFolderName]) 경로. 라이브러리가 없으면 null.
  String? _packFolderPath(LevelPack pack) {
    final root = installs.manager?.library.rootPath;
    return root == null ? null : p.join(root, LevelManager.safeFolderName(pack.name));
  }

  /// 팩 폴더에 팩 아이콘을 남긴다 (폴더가 없으면 만든다).
  Future<void> _tagPackFolder(LevelPack pack) async {
    final folder = _packFolderPath(pack);
    if (folder == null || pack.iconUrl == null) return;
    await LibraryOrganizer.writeFolderInfo(folder, FolderInfo(iconUrl: pack.iconUrl, packId: pack.id));
  }

  /// 전에 받아 둔 팩 폴더에도 아이콘이 붙도록, 팩을 열 때 이미 있는 폴더면 정보를 남긴다.
  Future<void> _tagExistingPackFolder(LevelPack pack) async {
    final folder = _packFolderPath(pack);
    if (folder == null || pack.iconUrl == null || !await Directory(folder).exists()) return;
    if ((await LibraryOrganizer.readFolderInfo(folder))?.iconUrl == pack.iconUrl) return;
    await _tagPackFolder(pack);
  }

  /// 레벨 id → 그 레벨을 담은 폴더 id들 (바깥 폴더부터). 같은 레벨이 여러 번 나오면 처음 자리.
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

  /// 받는 중인지. 한 번에 하나만 돌린다.
  bool get isDownloading => download != null;

  /// 차례로 받는다. 누른 버튼([scope])이 진행률로 바뀌고, 끝나면 다시 버튼으로 돌아온다.
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

    // 팩 이름 폴더에 팩 아이콘을 남겨서 레벨 관리에서도 알아볼 수 있게 한다.
    if (openedPack case final pack?) await _tagPackFolder(pack);

    for (final item in items) {
      if (job.cancelled) break;
      final folders = ancestors[item.level.id] ?? const <int>[];
      // 받고 있는 레벨이 든 폴더를 펼쳐서 보여준다.
      if (!expanded.containsAll(folders)) {
        expanded.addAll(folders);
        notifyListeners();
      }
      job._start(item.level.id);
      final ok = await installs.install(item.level, parentFolder: item.folder);
      job._advance(item.level.id, ok: ok);
      // 다 받은 폴더는 접는다 (안쪽 폴더부터).
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
    // 지금 받고 있는 레벨도 멈춘다.
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

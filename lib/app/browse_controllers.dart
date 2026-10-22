import 'dart:math';

import '../core/models/browse.dart';
import '../core/models/facet.dart';
import '../core/models/profile.dart';
import '../core/models/search_models.dart';
import 'paged_list.dart';

/// '클리어' 화면: TUF에 올라온 모든 클리어 기록. 검색·정렬·필터는 서버가 한다.
class ClearsController extends PagedList<PlayerPassEntry> {
  ClearsController(super.api, {required this.catalog});

  /// 난이도 슬라이더에 쓸 난이도 목록 (앱이 시작하면서 받는다).
  final DifficultyCatalog? Function() catalog;

  static const pageSize = 30;

  String query = '';
  ClearSort sort = ClearSort.recent;
  bool descending = true;
  bool filterOpen = false;

  /// PGU 슬라이더 위치. null이면 처음부터 끝까지.
  int? pguLower;
  int? pguUpper;
  final Set<String> specialDifficulties = {};
  KeyCountFilter keyCount = KeyCountFilter.all;
  WorldsFirstFilter worldsFirst = WorldsFirstFilter.none;
  GameVersionFilter version = GameVersionFilter.all;

  int? _seed;

  /// 기본값에서 바뀐 필터 수 (필터 단추의 배지).
  int get activeFilterCount {
    final pgu = catalog()?.pgu.length ?? 0;
    final rangeChanged = (pguLower ?? 0) != 0 || (pguUpper ?? pgu - 1) != pgu - 1;
    return [
      rangeChanged,
      specialDifficulties.isNotEmpty,
      keyCount != KeyCountFilter.all,
      worldsFirst != WorldsFirstFilter.none,
      version != GameVersionFilter.all,
    ].where((changed) => changed).length;
  }

  @override
  Future<void> reload() {
    // 무작위 정렬은 새로 검색할 때마다 순서가 바뀌고, 이어 받는 묶음은 같은 순서를 따른다.
    _seed = sort == ClearSort.random ? Random().nextInt(0x7FFFFFFF) + 1 : null;
    return super.reload();
  }

  @override
  Future<({List<PlayerPassEntry> items, int total, bool hasMore})> fetch(int offset) async {
    // "#123"은 그 번호의 기록 하나.
    final id = RegExp(r'^#(\d+)$').firstMatch(query.trim())?.group(1);
    if (id != null) {
      if (offset > 0) return (items: const <PlayerPassEntry>[], total: total, hasMore: false);
      final found = await api.findPassesById(int.parse(id));
      return (items: found, total: found.length, hasMore: false);
    }

    final pgu = catalog()?.pgu ?? const [];
    String? name(int? index, int fallback) =>
        pgu.isEmpty ? null : pgu[(index ?? fallback).clamp(0, pgu.length - 1)].name;
    final page = await api.searchPasses(
      ClearSearchQuery(
        query: query,
        sort: sort,
        descending: descending,
        minDifficulty: name(pguLower, 0),
        maxDifficulty: name(pguUpper, pgu.length - 1),
        specialDifficulties: specialDifficulties.toList(),
        keyCount: keyCount,
        worldsFirst: worldsFirst,
        version: version,
        offset: offset,
        limit: pageSize,
        seed: _seed,
      ),
    );
    if (page.seed != null) _seed = page.seed;
    return (items: page.passes, total: page.total, hasMore: offset + page.passes.length < page.total);
  }

  @override
  Object keyOf(PlayerPassEntry item) => item.pass.id;

  void setQuery(String value) {
    if (value == query) return;
    query = value;
    reloadSoon();
  }

  void setSort(ClearSort value) {
    if (value == sort) return;
    sort = value;
    reload();
  }

  void toggleOrder() {
    descending = !descending;
    reload();
  }

  void toggleFilterOpen() {
    filterOpen = !filterOpen;
    notifyListeners();
  }

  /// 슬라이더를 끄는 동안 자주 불리므로 잠깐 기다렸다가 받는다.
  void setPguRange(int lower, int upper) {
    pguLower = lower;
    pguUpper = upper;
    notifyListeners();
    reloadSoon();
  }

  void toggleSpecial(String name) {
    if (!specialDifficulties.remove(name)) specialDifficulties.add(name);
    reload();
  }

  void setKeyCount(KeyCountFilter value) {
    keyCount = value;
    reload();
  }

  void setWorldsFirst(WorldsFirstFilter value) {
    worldsFirst = value;
    reload();
  }

  void setVersion(GameVersionFilter value) {
    version = value;
    reload();
  }

  void resetFilters() {
    pguLower = null;
    pguUpper = null;
    specialDifficulties.clear();
    keyCount = KeyCountFilter.all;
    worldsFirst = WorldsFirstFilter.none;
    version = GameVersionFilter.all;
    reload();
  }
}

/// '리더보드' 화면: 플레이어 순위.
class LeaderboardController extends PagedList<LeaderboardPlayer> {
  LeaderboardController(super.api);

  static const pageSize = 30;

  String query = '';
  LeaderboardSort sort = LeaderboardSort.rankedScore;
  bool descending = true;

  @override
  Future<({List<LeaderboardPlayer> items, int total, bool hasMore})> fetch(int offset) async {
    final page = await api.getLeaderboard(
      query: query,
      sort: sort,
      descending: descending,
      offset: offset,
      limit: pageSize,
    );
    return (items: page.players, total: page.total, hasMore: offset + page.players.length < page.total);
  }

  @override
  Object keyOf(LeaderboardPlayer item) => item.id;

  void setQuery(String value) {
    if (value == query) return;
    query = value;
    reloadSoon();
  }

  void setSort(LeaderboardSort value) {
    if (value == sort) return;
    sort = value;
    reload();
  }

  void toggleOrder() {
    descending = !descending;
    reload();
  }
}

/// '제작자' 화면: 제작자 목록 (웹의 /creators).
class CreatorsController extends PagedList<CreatorListEntry> {
  CreatorsController(super.api);

  static const pageSize = 30;

  String query = '';
  CreatorSort sort = CreatorSort.chartsTotal;
  bool descending = true;
  bool filterOpen = false;

  /// 인증 상태로 거르기. null이면 모두.
  CreatorVerification? verification;

  /// 이 큐레이션 유형의 레벨이 있는 제작자만. [curationsMatchAll]이면 모두 있는 제작자만.
  final Set<int> curationTypeIds = {};
  bool curationsMatchAll = false;

  int get activeFilterCount => [verification != null, curationTypeIds.isNotEmpty].where((on) => on).length;

  @override
  Future<({List<CreatorListEntry> items, int total, bool hasMore})> fetch(int offset) async {
    final page = await api.getCreators(
      query: query,
      sort: sort,
      descending: descending,
      verification: verification,
      facetQuery: buildFacetQuery(
        curationTypes: FacetSelection(ids: curationTypeIds, matchAll: curationsMatchAll),
      ),
      offset: offset,
      limit: pageSize,
    );
    return (items: page.creators, total: page.total, hasMore: offset + page.creators.length < page.total);
  }

  @override
  Object keyOf(CreatorListEntry item) => item.id;

  void setQuery(String value) {
    if (value == query) return;
    query = value;
    reloadSoon();
  }

  void setSort(CreatorSort value) {
    if (value == sort) return;
    sort = value;
    reload();
  }

  void toggleOrder() {
    descending = !descending;
    reload();
  }

  void toggleFilterOpen() {
    filterOpen = !filterOpen;
    notifyListeners();
  }

  void setVerification(CreatorVerification? value) {
    if (value == verification) return;
    verification = value;
    reload();
  }

  void toggleCuration(int id) {
    if (!curationTypeIds.remove(id)) curationTypeIds.add(id);
    reload();
  }

  void setCurationsMatchAll(bool value) {
    if (value == curationsMatchAll) return;
    curationsMatchAll = value;
    curationTypeIds.length > 1 ? reload() : notifyListeners();
  }

  void resetFilters() {
    verification = null;
    curationTypeIds.clear();
    curationsMatchAll = false;
    reload();
  }
}

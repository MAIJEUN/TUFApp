import 'dart:math';

import '../core/models/browse.dart';
import '../core/models/facet.dart';
import '../core/models/profile.dart';
import '../core/models/search_models.dart';
import 'paged_list.dart';

/// Passes page: every pass on TUF. Searching, sorting and filtering happen on the server.
class ClearsController extends PagedList<PlayerPassEntry> {
  ClearsController(super.api, {required this.catalog});

  /// Difficulties for the slider (loaded at startup).
  final DifficultyCatalog? Function() catalog;

  static const pageSize = 30;

  String query = '';
  ClearSort sort = ClearSort.recent;
  bool descending = true;
  bool filterOpen = false;

  /// PGU slider range. null means the full range.
  int? pguLower;
  int? pguUpper;
  final Set<String> specialDifficulties = {};
  KeyCountFilter keyCount = KeyCountFilter.all;
  WorldsFirstFilter worldsFirst = WorldsFirstFilter.none;
  GameVersionFilter version = GameVersionFilter.all;

  int? _seed;

  /// Number of filters changed from their defaults (shown as a badge on the filter button).
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
    // Random sort reshuffles on every new search; later pages keep the same order.
    _seed = sort == ClearSort.random ? Random().nextInt(0x7FFFFFFF) + 1 : null;
    return super.reload();
  }

  @override
  Future<({List<PlayerPassEntry> items, int total, bool hasMore})> fetch(int offset) async {
    // "#123" finds that single pass.
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

  /// Called often while dragging the slider, so the request is debounced.
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

/// Leaderboard page: player rankings.
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

/// Creators page: the creator list (the website's /creators).
class CreatorsController extends PagedList<CreatorListEntry> {
  CreatorsController(super.api);

  static const pageSize = 30;

  String query = '';
  CreatorSort sort = CreatorSort.chartsTotal;
  bool descending = true;
  bool filterOpen = false;

  /// Verification status filter. null means all.
  CreatorVerification? verification;

  /// Only creators with levels of these curation types; with [curationsMatchAll], creators with all of them.
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

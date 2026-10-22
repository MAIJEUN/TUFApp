import '../../../app/controllers.dart';
import '../../../app/paged_list.dart';
import '../../../core/models/level.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/search_models.dart';

/// All of a player's passes. Search and sort happen on the server.
class PlayerPassList extends PagedList<PlayerPassEntry> {
  PlayerPassList(super.api, this.playerId);

  final int playerId;
  static const pageSize = 50;

  PlayerPassSort sort = PlayerPassSort.score;
  bool descending = true;
  String query = '';
  bool hideReclears = false;

  @override
  Future<({List<PlayerPassEntry> items, int total, bool hasMore})> fetch(int offset) async {
    final page = await api.getPlayerPasses(
      playerId,
      offset: offset,
      limit: pageSize,
      sort: sort,
      descending: descending,
      query: query,
      bestPerLevel: hideReclears,
    );
    return (items: page.passes, total: page.total, hasMore: offset + page.passes.length < page.total);
  }

  @override
  Object keyOf(PlayerPassEntry item) => item.pass.id;

  void setSort(PlayerPassSort value) {
    if (value == sort) return;
    sort = value;
    reload();
  }

  void toggleOrder() {
    descending = !descending;
    reload();
  }

  void setQuery(String value) {
    if (value == query) return;
    query = value;
    reloadSoon();
  }

  void setHideReclears(bool value) {
    if (value == hideReclears) return;
    hideReclears = value;
    reload();
  }
}

/// Levels a creator charted or did VFX for, using the same server search as the levels page.
class CreatorLevelList extends PagedList<Level> {
  CreatorLevelList(super.api, this.creatorId);

  final int creatorId;

  SortOption sort = sortOptions.first;
  bool ascending = false;
  String query = '';
  int? _seed;

  @override
  Future<void> reload() {
    _seed = sort.key == LevelSortKey.random ? DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFE + 1 : null;
    return super.reload();
  }

  @override
  Future<({List<Level> items, int total, bool hasMore})> fetch(int offset) async {
    final page = await api.searchLevels(
      LevelSearchQuery(
        query: query,
        sort: LevelSort(sort.key, ascending ? SortDirection.asc : SortDirection.desc),
        offset: offset,
        limit: 30,
        seed: _seed,
        byCreatorId: creatorId,
      ),
    );
    return (items: page.results, total: page.total, hasMore: page.hasMore);
  }

  @override
  Object keyOf(Level item) => item.id;

  void setSort(SortOption value) {
    if (value == sort) return;
    sort = value;
    reload();
  }

  void toggleOrder() {
    ascending = !ascending;
    reload();
  }

  void setQuery(String value) {
    if (value == query) return;
    query = value;
    reloadSoon();
  }
}

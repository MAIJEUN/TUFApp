import '../json.dart';
import '../l10n.dart';
import 'difficulty.dart';

enum LevelSortKey {
  recent('RECENT'),
  diff('DIFF'),
  clears('CLEARS'),
  totalClears('TOTAL_CLEARS'),
  likes('LIKES'),
  baseScore('BASESCORE'),
  bpm('BPM'),
  tiles('TILES'),
  time('TIME'),
  random('RANDOM');

  const LevelSortKey(this.apiName);

  final String apiName;
}

enum SortDirection { desc, asc }

class LevelSort {
  const LevelSort(this.key, [this.direction = SortDirection.desc]);

  final LevelSortKey key;
  final SortDirection direction;

  /// The backend only understands "KEY_ASC" / "KEY_DESC"; without the
  /// suffix it falls back to the default sort (id desc).
  String toApiValue() => '${key.apiName}_${direction == SortDirection.asc ? 'ASC' : 'DESC'}';
}

/// Three-state filter of the website's levels page (cleared levels, downloadable).
enum FilterState {
  /// Show everything (no filter)
  show,

  /// Hide matching levels
  hide,

  /// Show only matching levels
  only,
}

class PagedResult<T> {
  const PagedResult({required this.results, required this.total, required this.hasMore});

  factory PagedResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) => PagedResult(
    results: asObjectList(json['results']).map(parse).toList(),
    total: asInt(json['total']),
    hasMore: json['hasMore'] == true,
  );

  final List<T> results;
  final int total;
  final bool hasMore;
}

/// The server's difficulties, which decide the order and names used in filters.
class DifficultyCatalog {
  DifficultyCatalog(Iterable<Difficulty> difficulties)
    : all = List.unmodifiable([...difficulties]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))) {
    if (pgu.isEmpty) {
      throw StateError(tr('서버 난이도 목록에 PGU 난이도가 없습니다.', "The server's difficulty list has no PGU difficulties."));
    }
  }

  final List<Difficulty> all;

  /// P1 ~ U20
  late final List<Difficulty> pgu = all.where((d) => d.type == 'PGU').toList();

  /// Qq, GQ0–UQ4. Like the website, only SPECIAL difficulties with Q in the name (the server ignores LEGACY Q2+, Q3+).
  late final List<Difficulty> q = all.where((d) => d.type == 'SPECIAL' && d.name.contains('Q')).toList();

  /// Special difficulties other than Q: Unranked, P0, Censored, Impossible, ...
  late final List<Difficulty> special = all.where((d) => d.type == 'SPECIAL' && !d.name.contains('Q')).toList();

  Difficulty? named(String? name) => name == null ? null : all.where((d) => d.name == name).firstOrNull;

  Difficulty? byId(int? id) => id == null ? null : all.where((d) => d.id == id).firstOrNull;

  /// Builds a filter from slider positions (indices), swapping them if reversed.
  DifficultyFilter createFilter({
    required int pguLower,
    required int pguUpper,
    required int qLower,
    required int qUpper,
    required bool includeQ,
  }) {
    int clampTo(List<Difficulty> list, int i) => i.clamp(0, list.length - 1);

    final pguLo = clampTo(pgu, pguLower < pguUpper ? pguLower : pguUpper);
    final pguHi = clampTo(pgu, pguLower < pguUpper ? pguUpper : pguLower);

    var qNames = const <String>[];
    if (q.isNotEmpty) {
      final qLo = clampTo(q, qLower < qUpper ? qLower : qUpper);
      final qHi = clampTo(q, qLower < qUpper ? qUpper : qLower);
      qNames = [for (var i = qLo; i <= qHi; i++) q[i].name];
    }

    return DifficultyFilter(
      pguFrom: pgu[pguLo],
      pguTo: pgu[pguHi],
      qNames: qNames,
      includeQ: includeQ && qNames.isNotEmpty,
    );
  }
}

/// The server takes the PGU range as two names and Q difficulties as a list of full names.
class DifficultyFilter {
  const DifficultyFilter({required this.pguFrom, required this.pguTo, required this.qNames, required this.includeQ});

  final Difficulty pguFrom;
  final Difficulty pguTo;

  /// Full names of the Q difficulties in range (e.g. "GQ0 (G1~G4)"). The server ignores short names.
  final List<String> qNames;
  final bool includeQ;

  String get pguRangeValue => '${pguFrom.name},${pguTo.name}';

  List<String> get includedQNames => includeQ ? qNames : const [];
}

/// GET /v2/database/levels search parameters.
class LevelSearchQuery {
  const LevelSearchQuery({
    this.query,
    this.sort = const LevelSort(LevelSortKey.recent),
    this.difficultyFilter,
    this.specialDifficulties = const [],
    this.clearedFilter = FilterState.show,
    this.availableDlFilter = FilterState.show,
    this.facetQuery,
    this.offset = 0,
    this.limit = 30,
    this.seed,
    this.byCreatorId,
  });

  final String? query;
  final LevelSort sort;

  /// null means no difficulty filter. With a filter, only the PGU range
  /// and included Q/special difficulties are returned.
  final DifficultyFilter? difficultyFilter;

  /// Full names of extra special difficulties to include (Unranked, Censored, ...).
  final List<String> specialDifficulties;
  final FilterState clearedFilter;
  final FilterState availableDlFilter;

  /// Tag and curation type filter (facetQuery v1 JSON), built with [buildFacetQuery].
  final String? facetQuery;
  final int offset;
  final int limit;

  /// Seed of a random sort. Pages keep the same order only when requested with the same seed.
  final int? seed;

  /// Only levels this creator charted or did VFX for (creator page).
  final int? byCreatorId;

  Map<String, String> toQueryParameters() {
    final trimmed = query?.trim() ?? '';
    final specials = {...?difficultyFilter?.includedQNames, ...specialDifficulties};

    return {
      'offset': '$offset',
      'limit': '$limit',
      'sort': sort.toApiValue(),
      if (trimmed.isNotEmpty) 'query': trimmed,
      if (difficultyFilter != null) 'pguRange': difficultyFilter!.pguRangeValue,
      if (specials.isNotEmpty) 'specialDifficulties': specials.join(','),
      'facetQuery': ?facetQuery,
      if (clearedFilter != FilterState.show) 'clearedFilter': clearedFilter.name,
      if (availableDlFilter != FilterState.show) 'availableDlFilter': availableDlFilter.name,
      if (seed != null) 'seed': '$seed',
      if (byCreatorId != null) 'byCreatorId': '$byCreatorId',
    };
  }
}

/// The needed part of the metadata from GET /v2/database/levels/{id}/cdnData.
class CdnLevelMetadata {
  const CdnLevelMetadata({this.targetLevelRelativePath, this.archiveBytes});

  factory CdnLevelMetadata.fromJson(Map<String, dynamic> json) {
    int? sizeOf(Object? archive) => archive is Map<String, dynamic> ? asIntOrNull(archive['size']) : null;
    return CdnLevelMetadata(
      targetLevelRelativePath: asStringOrNull(json['targetLevelRelativePath']),
      archiveBytes: sizeOf(json['originalZip']) ?? sizeOf(json['originalArchive']),
    );
  }

  /// Path of the main chart inside the zip, e.g. "Multi_arm(fixed)/main.adofai"
  final String? targetLevelRelativePath;

  /// Size of the zip to download in bytes, or null if unknown.
  final int? archiveBytes;
}

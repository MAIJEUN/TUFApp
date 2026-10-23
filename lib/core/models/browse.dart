import '../json.dart';
import '../l10n.dart';
import 'difficulty.dart';
import 'pass.dart';
import 'profile.dart';

// ───────────────────────── Passes ─────────────────────────

/// Pass list sort. [apiValue] matches the website (with an _ASC / _DESC suffix).
enum ClearSort {
  recent('RECENT'),
  score('SCORE'),
  accuracy('XACC'),
  difficulty('DIFF'),
  speed('SPEED'),
  keyCount('KEYCOUNT'),
  random('RANDOM');

  const ClearSort(this.apiValue);

  String get label => switch (this) {
    recent => l10n.clearSortRecent,
    score => l10n.clearSortScore,
    accuracy => l10n.clearSortAccuracy,
    difficulty => l10n.clearSortDifficulty,
    speed => l10n.clearSortSpeed,
    keyCount => l10n.clearSortKeyCount,
    random => l10n.clearSortRandom,
  };
  final String apiValue;
}

/// Key count filter.
enum KeyCountFilter {
  all('all'),
  k12('12k'),
  k16('16k');

  const KeyCountFilter(this.apiValue);

  String get label => switch (this) {
    all => l10n.keyCountFilterAll,
    k12 => l10n.keyCountFilterK12,
    k16 => l10n.keyCountFilterK16,
  };
  final String apiValue;
}

/// World's first filter.
enum WorldsFirstFilter {
  none('none'),
  wf('wf'),
  wfpp('wfpp'),
  either('either'),
  both('both');

  const WorldsFirstFilter(this.apiValue);

  String get label => switch (this) {
    none => l10n.worldsFirstFilterNone,
    wf => l10n.worldsFirstFilterWf,
    wfpp => l10n.worldsFirstFilterWfpp,
    either => l10n.worldsFirstFilterEither,
    both => l10n.worldsFirstFilterBoth,
  };
  final String apiValue;
}

/// Filter by the game version a pass was made on.
enum GameVersionFilter {
  all('all'),
  latest('latest'),
  pre340('pre340'),
  v2('v2');

  const GameVersionFilter(this.apiValue);

  String get label => switch (this) {
    all => l10n.gameVersionFilterAll,
    latest => l10n.gameVersionFilterLatest,
    pre340 => l10n.gameVersionFilterPre340,
    v2 => l10n.gameVersionFilterV2,
  };
  final String apiValue;
}

/// GET /v2/database/passes request, with the same parameters as the website's pass list.
class ClearSearchQuery {
  const ClearSearchQuery({
    this.query = '',
    this.sort = ClearSort.recent,
    this.descending = true,
    this.minDifficulty,
    this.maxDifficulty,
    this.specialDifficulties = const [],
    this.keyCount = KeyCountFilter.all,
    this.worldsFirst = WorldsFirstFilter.none,
    this.version = GameVersionFilter.all,
    this.offset = 0,
    this.limit = 30,
    this.seed,
  });

  final String query;
  final ClearSort sort;
  final bool descending;

  /// PGU difficulty range (names). Only passes on levels in this range or in [specialDifficulties] are returned.
  final String? minDifficulty;
  final String? maxDifficulty;
  final List<String> specialDifficulties;
  final KeyCountFilter keyCount;
  final WorldsFirstFilter worldsFirst;
  final GameVersionFilter version;
  final int offset;
  final int limit;

  /// Keeps later pages of a random sort in the same order.
  final int? seed;

  Map<String, Object> toQueryParameters() => {
    'limit': '$limit',
    'offset': '$offset',
    'query': query.trim(),
    'sort': '${sort.apiValue}_${descending ? 'DESC' : 'ASC'}',
    'deletedFilter': 'hide',
    'keyFlag': keyCount.apiValue,
    'wfFilter': worldsFirst.apiValue,
    'adofaiVersionFilter': version.apiValue,
    'wrongJudgementFilter': 'all',
    'minDiff': ?minDifficulty,
    'maxDiff': ?maxDifficulty,
    // The server only accepts an array; repeating the key makes one.
    if (specialDifficulties.isNotEmpty) 'specialDifficulties': specialDifficulties,
    if (sort == ClearSort.random && seed != null) 'seed': '$seed',
  };
}

// ───────────────────────── Leaderboard ─────────────────────────

/// Leaderboard sort keys. Names match the API's sortBy values.
enum LeaderboardSort {
  rankedScore,
  totalScoreV2,
  generalScore,
  ppScore,
  wfScore,
  wfPPScore,
  score12K,
  averageXacc,
  totalPasses,
  universalPassCount,
  worldsFirstCount,
  worldsFirstPPCount,
  topDiff,
  top12kDiff;

  String get label => switch (this) {
    rankedScore => l10n.leaderboardSortRankedScore,
    totalScoreV2 => l10n.leaderboardSortTotalScoreV2,
    generalScore => l10n.leaderboardSortGeneralScore,
    ppScore => l10n.leaderboardSortPpScore,
    wfScore => l10n.leaderboardSortWfScore,
    wfPPScore => l10n.leaderboardSortWfPPScore,
    score12K => l10n.leaderboardSortScore12K,
    averageXacc => l10n.leaderboardSortAverageXacc,
    totalPasses => l10n.leaderboardSortTotalPasses,
    universalPassCount => l10n.leaderboardSortUniversalPassCount,
    worldsFirstCount => l10n.leaderboardSortWorldsFirstCount,
    worldsFirstPPCount => l10n.leaderboardSortWorldsFirstPPCount,
    topDiff => l10n.leaderboardSortTopDiff,
    top12kDiff => l10n.leaderboardSortTop12kDiff,
  };

  /// Keys whose value is a difficulty (shown as an icon).
  bool get isDifficulty => this == topDiff || this == top12kDiff;

  /// Keys whose value is a count (shown without decimals).
  bool get isCount => const {totalPasses, universalPassCount, worldsFirstCount, worldsFirstPPCount}.contains(this);
}

/// One leaderboard row. GET /v3/players/leaderboard
class LeaderboardPlayer {
  const LeaderboardPlayer({
    required this.id,
    required this.name,
    required this.avatar,
    required this.rank,
    required this.values,
    this.country,
    this.topDifficulty,
    this.top12kDifficulty,
    this.creatorId,
  });

  factory LeaderboardPlayer.fromJson(Map<String, dynamic> json) {
    Difficulty? difficulty(Object? value) => value is Map<String, dynamic> ? Difficulty.fromJson(value) : null;
    final user = json['user'];
    final creator = user is Map<String, dynamic> ? user['creator'] : null;
    return LeaderboardPlayer(
      id: asInt(json['id']),
      name: asStringOrNull(json['name']) ?? l10n.unknown,
      avatar: AvatarUrls.of(json),
      rank: asIntOrNull(json['rank']) ?? asIntOrNull(json['rankedScoreRank']) ?? 0,
      country: asStringOrNull(json['country']),
      values: {
        for (final sort in LeaderboardSort.values)
          if (!sort.isDifficulty) sort: asDoubleOrNull(json[sort.name]) ?? 0,
      },
      topDifficulty: difficulty(json['topDiff']),
      top12kDifficulty: difficulty(json['top12kDiff']),
      creatorId: creator is Map<String, dynamic> ? asIntOrNull(creator['id']) : null,
    );
  }

  final int id;
  final String name;
  final AvatarUrls avatar;

  /// Ranked score rank; 0 or less if unranked.
  final int rank;
  final String? country;

  /// Values of the non-difficulty keys.
  final Map<LeaderboardSort, double> values;
  final Difficulty? topDifficulty;
  final Difficulty? top12kDifficulty;

  /// Id of the linked creator profile, if any.
  final int? creatorId;

  double value(LeaderboardSort sort) => values[sort] ?? 0;

  Difficulty? difficulty(LeaderboardSort sort) => switch (sort) {
    LeaderboardSort.topDiff => topDifficulty,
    LeaderboardSort.top12kDiff => top12kDifficulty,
    _ => null,
  };
}

// ───────────────────────── Creators ─────────────────────────

/// Creator list sort keys. Names match the API's sortBy values and labels match the website.
enum CreatorSort {
  chartsTotal,
  chartsCharted,
  chartsVfxed,
  chartsTeamed,
  totalChartClears,
  totalChartLikes,
  name;

  String get label => switch (this) {
    chartsTotal => l10n.creatorSortChartsTotal,
    chartsCharted => l10n.creatorSortChartsCharted,
    chartsVfxed => l10n.creatorSortChartsVfxed,
    chartsTeamed => l10n.creatorSortChartsTeamed,
    totalChartClears => l10n.creatorSortTotalChartClears,
    totalChartLikes => l10n.creatorSortTotalChartLikes,
    name => l10n.creatorSortName,
  };
}

/// One creator list row. GET /v3/creators/leaderboard
class CreatorListEntry {
  const CreatorListEntry({
    required this.id,
    required this.name,
    required this.avatar,
    required this.verification,
    this.handle,
    this.playerId,
    this.counts = const {},
    this.curationTypeCounts = const {},
    this.displayCurationTypeIds = const [],
  });

  factory CreatorListEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : null;
    return CreatorListEntry(
      id: asInt(json['id']),
      name: asStringOrNull(json['name']) ?? l10n.unknown,
      avatar: user == null ? const AvatarUrls() : AvatarUrls.of(user),
      verification: CreatorVerification.fromApi(json['verificationStatus']),
      handle: asStringOrNull(user?['username']),
      playerId: asIntOrNull(user?['playerId']),
      counts: {
        for (final sort in CreatorSort.values)
          if (sort != CreatorSort.name) sort: asInt(json[sort.name]),
      },
      curationTypeCounts: {
        for (final pair in asObjectList(json['curationTypeCountPairs']))
          ?asIntOrNull(pair['typeId']): asInt(pair['count']),
      },
      displayCurationTypeIds: [
        for (final id in (json['displayCurationTypeIds'] as List?) ?? const []) ?asIntOrNull(id),
      ],
    );
  }

  final int id;
  final String name;
  final AvatarUrls avatar;
  final CreatorVerification verification;

  /// Linked TUF account, or null.
  final String? handle;
  final int? playerId;
  final Map<CreatorSort, int> counts;

  /// Curation type id → number of levels of that type.
  final Map<int, int> curationTypeCounts;

  /// Curation types the creator picked to display (chosen automatically if empty).
  final List<int> displayCurationTypeIds;

  int count(CreatorSort sort) => counts[sort] ?? 0;
}

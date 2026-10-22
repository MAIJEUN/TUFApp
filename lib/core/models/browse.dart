import '../json.dart';
import '../l10n.dart';
import 'difficulty.dart';
import 'pass.dart';
import 'profile.dart';

// ───────────────────────── Passes ─────────────────────────

/// Pass list sort. [apiValue] matches the website (with an _ASC / _DESC suffix).
enum ClearSort {
  recent('최신순', 'Date', 'RECENT'),
  score('점수', 'Score', 'SCORE'),
  accuracy('정확도', 'Accuracy', 'XACC'),
  difficulty('난이도', 'Difficulty', 'DIFF'),
  speed('속도', 'Speed', 'SPEED'),
  keyCount('키 수', 'Key count', 'KEYCOUNT'),
  random('무작위', 'Random', 'RANDOM');

  const ClearSort(this._ko, this._en, this.apiValue);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
  final String apiValue;
}

/// Key count filter.
enum KeyCountFilter {
  all('전체', 'All', 'all'),
  k12('12키', '12K', '12k'),
  k16('16키', '16K', '16k');

  const KeyCountFilter(this._ko, this._en, this.apiValue);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
  final String apiValue;
}

/// World's first filter.
enum WorldsFirstFilter {
  none('전체', 'All', 'none'),
  wf('WF', 'WF', 'wf'),
  wfpp('WF PP', 'WF PP', 'wfpp'),
  either('둘 중 하나', 'Either', 'either'),
  both('둘 다', 'Both', 'both');

  const WorldsFirstFilter(this._ko, this._en, this.apiValue);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
  final String apiValue;
}

/// Filter by the game version a pass was made on.
enum GameVersionFilter {
  all('전체', 'All', 'all'),
  latest('최신', 'Latest', 'latest'),
  pre340('<3.4.0', '<3.4.0', 'pre340'),
  v2('v2', 'v2', 'v2');

  const GameVersionFilter(this._ko, this._en, this.apiValue);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
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
  rankedScore('랭크 점수', 'Ranked Score'),
  totalScoreV2('총 점수', 'Total Score'),
  generalScore('일반 점수', 'General Score'),
  ppScore('완벽한 플레이 점수', 'PP Score'),
  wfScore('세계 최초 점수', 'WF Score'),
  wfPPScore('세계 최초 완플 점수', 'WF PP Score'),
  score12K('12키 점수', '12K Score'),
  averageXacc('평균 절대정확도', 'Average X-acc'),
  totalPasses('클리어한 레벨', 'Total Passes'),
  universalPassCount('U 클리어', 'Universal Passes'),
  worldsFirstCount('세계 최초 클리어', 'WF Passes'),
  worldsFirstPPCount('세계 최초 완플 클리어', 'WF PP Passes'),
  topDiff('최고 난이도', 'Top Difficulty'),
  top12kDiff('최고 12키 난이도', 'Top 12K Difficulty');

  const LeaderboardSort(this._ko, this._en);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);

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
      name: asStringOrNull(json['name']) ?? tr('알 수 없음', 'Unknown'),
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
  chartsTotal('총 레벨', 'Total Levels'),
  chartsCharted('채보 레벨', 'Levels Charted'),
  chartsVfxed('이펙트 레벨', "Levels VFX'd"),
  chartsTeamed('팀 명의 레벨', 'Levels as a team member'),
  totalChartClears('모든 레벨 클리어 수', 'Total Level Clears'),
  totalChartLikes('모든 레벨 좋아요 수', 'Total Level Likes'),
  name('이름', 'Name');

  const CreatorSort(this._ko, this._en);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
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
      name: asStringOrNull(json['name']) ?? tr('알 수 없음', 'Unknown'),
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

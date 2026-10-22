import '../json.dart';
import '../l10n.dart';
import 'difficulty.dart';
import 'pass.dart';
import 'profile.dart';

// ───────────────────────── 클리어 목록 ─────────────────────────

/// 클리어 목록 정렬. [apiValue]는 웹과 같은 값이다 (뒤에 _ASC / _DESC가 붙는다).
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

/// 키 수 표시로 거르기.
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

/// 세계 최초 기록으로 거르기.
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

/// 기록을 낸 게임 버전으로 거르기.
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

/// GET /v2/database/passes 요청. 웹의 클리어 목록과 같은 값을 보낸다.
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

  /// PGU 난이도 범위 (이름). 이 범위의 레벨이거나 [specialDifficulties]에 든 레벨의 기록만 나온다.
  final String? minDifficulty;
  final String? maxDifficulty;
  final List<String> specialDifficulties;
  final KeyCountFilter keyCount;
  final WorldsFirstFilter worldsFirst;
  final GameVersionFilter version;
  final int offset;
  final int limit;

  /// 무작위 정렬일 때 다음 묶음도 같은 순서로 이어지게 하는 값.
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
    // 서버는 배열만 받는다. 같은 이름을 여러 번 보내면 배열이 된다.
    if (specialDifficulties.isNotEmpty) 'specialDifficulties': specialDifficulties,
    if (sort == ClearSort.random && seed != null) 'seed': '$seed',
  };
}

// ───────────────────────── 리더보드 ─────────────────────────

/// 리더보드 정렬 기준. 이름은 API의 sortBy 값과 같다.
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

  /// 값이 난이도인 기준 (아이콘으로 보여준다).
  bool get isDifficulty => this == topDiff || this == top12kDiff;

  /// 값이 개수인 기준 (소수점 없이 보여준다).
  bool get isCount => const {totalPasses, universalPassCount, worldsFirstCount, worldsFirstPPCount}.contains(this);
}

/// 리더보드 한 줄. GET /v3/players/leaderboard
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

  /// 랭크 점수 순위. 순위가 없으면 0 이하.
  final int rank;
  final String? country;

  /// 난이도가 아닌 기준의 값.
  final Map<LeaderboardSort, double> values;
  final Difficulty? topDifficulty;
  final Difficulty? top12kDifficulty;

  /// 제작자 프로필이 이어져 있으면 그 id.
  final int? creatorId;

  double value(LeaderboardSort sort) => values[sort] ?? 0;

  Difficulty? difficulty(LeaderboardSort sort) => switch (sort) {
    LeaderboardSort.topDiff => topDifficulty,
    LeaderboardSort.top12kDiff => top12kDifficulty,
    _ => null,
  };
}

// ───────────────────────── 제작자 목록 ─────────────────────────

/// 제작자 목록 정렬 기준. 이름은 API의 sortBy 값과 같고, 글은 웹의 한국어와 같다.
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

/// 제작자 목록 한 줄. GET /v3/creators/leaderboard
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

  /// 연동된 TUF 계정. 없으면 null.
  final String? handle;
  final int? playerId;
  final Map<CreatorSort, int> counts;

  /// 큐레이션 유형 id → 그 유형의 레벨 수.
  final Map<int, int> curationTypeCounts;

  /// 제작자가 직접 고른 대표 큐레이션 유형 (없으면 자동으로 고른다).
  final List<int> displayCurationTypeIds;

  int count(CreatorSort sort) => counts[sort] ?? 0;
}

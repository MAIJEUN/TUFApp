import '../json.dart';
import '../l10n.dart';

/// 레벨 하나의 클리어 기록. GET /v2/database/passes/level/{id}
class LevelPass {
  const LevelPass({
    required this.id,
    this.levelId,
    required this.playerId,
    required this.playerName,
    this.playerAvatar,
    this.country,
    this.score = 0,
    this.accuracy = 0,
    this.speed = 1,
    this.judgements,
    this.videoLink,
    this.videoTitle,
    this.clearedAt,
    this.feelingRating,
    this.expectedRating,
    this.playerAvatarFallback,
    this.isWorldsFirst = false,
    this.isWorldsFirstPP = false,
    this.keyCount,
    this.is12K = false,
    this.is16K = false,
    this.isNoHoldTap = false,
    this.era = AdofaiEra.pre340,
    this.isXPerfectMode = false,
    this.isAutoSubmitted = false,
  });

  factory LevelPass.fromJson(Map<String, dynamic> json) {
    final player = json['player'];
    final judgements = json['judgements'];
    final avatar = player is Map<String, dynamic> ? AvatarUrls.of(player) : const AvatarUrls();
    final keyCount = asIntOrNull(json['keyCount']);
    return LevelPass(
      id: asInt(json['id']),
      levelId: asIntOrNull(json['levelId']),
      playerId: asInt(json['playerId']),
      playerName: (player is Map<String, dynamic> ? asStringOrNull(player['name']) : null) ?? tr('알 수 없음', 'Unknown'),
      playerAvatar: avatar.primary,
      playerAvatarFallback: avatar.fallback,
      country: player is Map<String, dynamic> ? asStringOrNull(player['country']) : null,
      score: asDoubleOrNull(json['scoreV2']) ?? 0,
      accuracy: asDoubleOrNull(json['accuracy']) ?? 0,
      speed: asDoubleOrNull(json['speed']) ?? 1,
      judgements: judgements is Map<String, dynamic> ? PassJudgements.fromJson(judgements) : null,
      videoLink: asStringOrNull(json['videoLink']),
      videoTitle: asStringOrNull(json['vidTitle']),
      clearedAt: DateTime.tryParse(asStringOrNull(json['vidUploadTime']) ?? asStringOrNull(json['createdAt']) ?? ''),
      feelingRating: asStringOrNull(json['feelingRating']),
      expectedRating: asStringOrNull(json['expectedRating']),
      isWorldsFirst: asBool(json['isWorldsFirst']),
      isWorldsFirstPP: asBool(json['isWorldsFirstPP']),
      keyCount: keyCount != null && keyCount > 0 ? keyCount : null,
      is12K: asBool(json['is12K']),
      is16K: asBool(json['is16K']),
      isNoHoldTap: asBool(json['isNoHoldTap']),
      // 예전 기록은 버전 번호 없이 'ADOFAI 2인지'만 있다.
      era: AdofaiEra.fromApi(json['adofaiVersion']) ?? (asBool(json['isAdofaiV2']) ? AdofaiEra.v2 : AdofaiEra.pre340),
      isXPerfectMode: asBool(json['isXPerfectMode']),
      isAutoSubmitted: json['submissionSource'] == 'auto_submission',
    );
  }

  final int id;

  /// 기록을 낸 레벨. 기록만 따로 열 때 레벨을 찾는 데 쓴다.
  final int? levelId;
  final int playerId;
  final String playerName;

  /// 프로필 사진. TUF에 올린 사진이 먼저이고, 그게 안 열리면 [playerAvatarFallback](디스코드 사진)을 쓴다.
  final String? playerAvatar;
  final String? playerAvatarFallback;

  /// 두 글자 국가 코드 (예: "KR").
  final String? country;

  final double score;

  /// 0~1.
  final double accuracy;
  final double speed;
  final PassJudgements? judgements;
  final String? videoLink;
  final String? videoTitle;
  final DateTime? clearedAt;

  /// 기록을 낸 사람이 느낀 난이도 (예: "U16").
  final String? feelingRating;

  /// 심사에서 예상한 난이도. 없으면 null.
  final String? expectedRating;

  final bool isWorldsFirst;

  /// 세계 최초 완벽한 플레이(정확도 100%).
  final bool isWorldsFirstPP;

  /// 쓴 키 수. 예전 기록은 이 값 없이 [is12K]/[is16K]만 있다.
  final int? keyCount;
  final bool is12K;
  final bool is16K;
  final bool isNoHoldTap;

  /// 기록을 낸 게임 버전 시기.
  final AdofaiEra era;

  /// 3.4.0의 X-Perfect 판정(정확−, 정확, 정확+)으로 낸 기록.
  final bool isXPerfectMode;

  /// 게임에서 바로 제출된 기록 (영상 제출이 아님).
  final bool isAutoSubmitted;

  /// "16키"처럼 보여줄 키 수. 표시할 게 없으면 null.
  String? get keyCountLabel => switch (keyCount) {
    final count? => tr('$count키', '${count}K'),
    null when is16K => tr('16키', '16K'),
    null when is12K => tr('12키', '12K'),
    _ => null,
  };

  /// 정확−/정확+ 칸까지 보여줄지. X-Perfect 기록이거나 그 칸에 값이 있으면 보여준다 (사이트와 같다).
  bool get showsXPerfect => isXPerfectMode || (judgements?.hasXPerfectCounts ?? false);

  /// X-Perfect 기록인데 모든 판정이 가운데 정확 (퓨어 X-퍼펙트).
  bool get isPureXPerfect {
    final counts = judgements;
    return isXPerfectMode && counts != null && counts.total > 0 && counts.perfect == counts.total;
  }

  /// 정확도 100% (퓨어 퍼펙트). 퓨어 X-퍼펙트면 그쪽으로 본다.
  bool get isPurePerfect => accuracy >= 1 && !isPureXPerfect;
}

/// 기록을 낸 게임 버전 시기. TUF는 판정 방식이 바뀐 때를 기준으로 나눈다.
enum AdofaiEra {
  /// v2.9.8까지. 타이밍 엔진이 바뀌기 전.
  v2,

  /// v3.3.1까지. X-Perfect 판정이 생기기 전.
  pre340,

  /// v3.4.0부터.
  latest;

  /// API의 adofaiVersion 값 (1, 2, 3). 모르는 값이면 null.
  static AdofaiEra? fromApi(Object? value) => switch (asIntOrNull(value)) {
    1 => v2,
    2 => pre340,
    3 => latest,
    _ => null,
  };
}

/// 프로필 사진 주소. 사이트처럼 TUF에 올린 사진을 먼저 쓰고, 디스코드 사진(pfp)을 대신 쓸 주소로 둔다.
class AvatarUrls {
  const AvatarUrls({this.primary, this.fallback});

  /// 플레이어 정보([json])에서 고른다. 사진은 플레이어나 그 계정(user)에 붙어 있다.
  factory AvatarUrls.of(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : null;
    final pfp = asStringOrNull(json['pfp']) ?? asStringOrNull(user?['pfp']);
    final uploaded = asStringOrNull(json['avatarUrl']) ?? asStringOrNull(user?['avatarUrl']);
    if (uploaded == null) return AvatarUrls(primary: pfp);
    return AvatarUrls(primary: _staticUnlessAllowed(_medium(uploaded.trim()), user ?? json), fallback: pfp);
  }

  /// TUF에 올린 사진은 크기별로 있다. 원본은 200KB쯤이라 작게 보여줄 때는 중간 크기(20KB쯤)를 받는다.
  static String _medium(String url) => url.contains('/images/profile/')
      ? url.replaceAll(RegExp(r'/(?:small|medium|large|original)(?=/|\.|\?|#|$)'), '/medium')
      : url;

  final String? primary;
  final String? fallback;

  /// 움직이는 사진은 후원(TUF Stellar) 중인 사람만 보인다. 아니면 멈춘 사진(_static)을 쓴다.
  static String _staticUnlessAllowed(String url, Map<String, dynamic> owner) {
    if (owner['avatarIsGif'] != true) return url;
    final expires = DateTime.tryParse(asStringOrNull(owner['tufStellarSubscriptionExpiresAt']) ?? '');
    if (expires != null && expires.isAfter(DateTime.now())) return url;
    return url.contains('_animated') ? url.replaceAll('_animated', '_static') : '${url}_static';
  }
}

/// 기록 하나를 자세히 본 결과. GET /v2/database/passes/{id}
/// 이 기록이 그 사람의 랭킹 점수에 얼마나 보탰는지까지 알려준다.
class PassDetail {
  const PassDetail({required this.pass, this.score, this.rank = 0});

  factory PassDetail.fromJson(Map<String, dynamic> json) {
    final score = json['scoreInfo'];
    final ranks = json['ranks'];
    return PassDetail(
      pass: LevelPass.fromJson(json),
      score: score is Map<String, dynamic> ? PassScoreImpact.fromJson(score) : null,
      rank: ranks is Map<String, dynamic> ? asInt(ranks['rankedScoreRank']) : 0,
    );
  }

  final LevelPass pass;
  final PassScoreImpact? score;

  /// 기록을 낸 사람의 전체 랭킹 순위.
  final int rank;
}

/// 이 기록이 랭킹 점수에 보탠 몫.
class PassScoreImpact {
  const PassScoreImpact({
    this.current = 0,
    this.previous = 0,
    this.impact = 0,
    this.countsForRanked = true,
    this.potentialImpact = 0,
  });

  factory PassScoreImpact.fromJson(Map<String, dynamic> json) => PassScoreImpact(
    current: asDoubleOrNull(json['currentRankedScore']) ?? 0,
    previous: asDoubleOrNull(json['previousRankedScore']) ?? 0,
    impact: asDoubleOrNull(json['impact']) ?? 0,
    countsForRanked: asBool(json['countsForRanked']),
    potentialImpact: asDoubleOrNull(json['potentialImpact']) ?? 0,
  );

  /// 지금 랭킹 점수와, 이 기록이 없었을 때의 점수.
  final double current;
  final double previous;

  /// 이 기록이 보탠 점수.
  final double impact;

  /// 랭킹 점수에 들어가는 기록인지. 아니면 [potentialImpact]만큼 보탤 수 있었다는 뜻이다.
  final bool countsForRanked;
  final double potentialImpact;
}

/// 기록을 낸 사람. GET /v2/database/players/{id}
class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    this.country,
    this.avatar,
    this.avatarFallback,
    this.rankedScore = 0,
    this.rank = 0,
    this.topDifficulty,
    this.averageAccuracy = 0,
    this.totalPasses = 0,
    this.worldsFirstCount = 0,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    // 점수와 순위는 stats 안에 있고, 없으면 바깥 값으로 채운다.
    final stats = json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : const {};
    final topDiff = stats['topDiff'] ?? json['topDiff'];
    return PlayerProfile(
      id: asInt(json['id']),
      name: asStringOrNull(json['name']) ?? tr('알 수 없음', 'Unknown'),
      country: asStringOrNull(json['country']),
      avatar: AvatarUrls.of(json).primary,
      avatarFallback: AvatarUrls.of(json).fallback,
      rankedScore: asDoubleOrNull(stats['rankedScore']) ?? asDoubleOrNull(json['rankedScore']) ?? 0,
      rank: asInt(stats['rankedScoreRank']),
      topDifficulty: topDiff is Map<String, dynamic> ? asStringOrNull(topDiff['name']) : null,
      averageAccuracy: asDoubleOrNull(stats['averageXacc']) ?? asDoubleOrNull(json['averageXacc']) ?? 0,
      totalPasses: asInt(stats['totalPasses'] ?? json['totalPasses']),
      worldsFirstCount: asInt(stats['worldsFirstCount'] ?? json['worldsFirstCount']),
    );
  }

  final int id;
  final String name;
  final String? country;

  /// 프로필 사진과, 그게 안 열릴 때 쓸 사진.
  final String? avatar;
  final String? avatarFallback;

  /// 랭킹에 쓰는 점수와 그 순위.
  final double rankedScore;
  final int rank;

  /// 이 사람이 깬 가장 높은 난이도 (예: "U16").
  final String? topDifficulty;
  final double averageAccuracy;
  final int totalPasses;
  final int worldsFirstCount;
}

/// 판정 개수. 웹 리더보드와 같은 순서로 보여준다.
///
/// 3.4.0부터는 X-Perfect 판정을 고를 수 있어서, 정확이 정확−/정확/정확+ 셋으로 나뉜다.
class PassJudgements {
  const PassJudgements({
    this.earlyDouble = 0,
    this.earlySingle = 0,
    this.earlyPerfect = 0,
    this.perfectMinus = 0,
    this.perfect = 0,
    this.perfectPlus = 0,
    this.latePerfect = 0,
    this.lateSingle = 0,
    this.lateDouble = 0,
  });

  factory PassJudgements.fromJson(Map<String, dynamic> json) => PassJudgements(
    earlyDouble: asInt(json['earlyDouble']),
    earlySingle: asInt(json['earlySingle']),
    earlyPerfect: asInt(json['ePerfect']),
    perfectMinus: asInt(json['perfectMinus']),
    perfect: asInt(json['perfect']),
    perfectPlus: asInt(json['perfectPlus']),
    latePerfect: asInt(json['lPerfect']),
    lateSingle: asInt(json['lateSingle']),
    lateDouble: asInt(json['lateDouble']),
  );

  final int earlyDouble;
  final int earlySingle;
  final int earlyPerfect;

  /// X-Perfect 판정의 조금 이르고 늦은 정확. 정확도는 정확과 같게 친다.
  final int perfectMinus;
  final int perfect;
  final int perfectPlus;

  final int latePerfect;
  final int lateSingle;
  final int lateDouble;

  bool get hasXPerfectCounts => perfectMinus > 0 || perfectPlus > 0;

  int get total =>
      earlyDouble +
      earlySingle +
      earlyPerfect +
      perfectMinus +
      perfect +
      perfectPlus +
      latePerfect +
      lateSingle +
      lateDouble;

  /// 이른 판정부터 늦은 판정까지 차례대로. [xPerfect]면 정확−/정확+ 칸도 넣는다.
  List<(Judgement, int)> ordered({required bool xPerfect}) => [
    (Judgement.tooEarly, earlyDouble),
    (Judgement.early, earlySingle),
    (Judgement.earlyPerfect, earlyPerfect),
    if (xPerfect) (Judgement.perfectMinus, perfectMinus),
    (Judgement.perfect, perfect),
    if (xPerfect) (Judgement.perfectPlus, perfectPlus),
    (Judgement.latePerfect, latePerfect),
    (Judgement.late, lateSingle),
    (Judgement.tooLate, lateDouble),
  ];
}

/// 판정 종류. 이름은 사이트의 한국어 표기와 게임의 영어 표기를 따른다.
enum Judgement {
  tooEarly('너무 빠름', 'Too Early'),
  early('빠름!', 'Early!'),
  earlyPerfect('빠름', 'EPerfect'),
  perfectMinus('정확−', 'Perfect−'),
  perfect('정확', 'Perfect'),
  perfectPlus('정확+', 'Perfect+'),
  latePerfect('느림', 'LPerfect'),
  late('느림!', 'Late!'),
  tooLate('너무 느림', 'Too Late');

  const Judgement(this._ko, this._en);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
}

/// 기록들에서 뽑아내는 요약 (최초 클리어, 최고 점수 등).
class LevelPassSummary {
  const LevelPassSummary({required this.passes, this.firstClear, this.bestScore, this.bestSpeed, this.bestAccuracy});

  factory LevelPassSummary.of(List<LevelPass> passes) {
    if (passes.isEmpty) return const LevelPassSummary(passes: []);

    LevelPass best(LevelPass Function(LevelPass a, LevelPass b) pick) => passes.reduce(pick);
    final dated = passes.where((pass) => pass.clearedAt != null).toList();

    return LevelPassSummary(
      passes: passes,
      firstClear: dated.isEmpty ? null : dated.reduce((a, b) => a.clearedAt!.isBefore(b.clearedAt!) ? a : b),
      bestScore: best((a, b) => b.score > a.score ? b : a),
      bestSpeed: best((a, b) => b.speed > a.speed ? b : a),
      bestAccuracy: best((a, b) => b.accuracy > a.accuracy ? b : a),
    );
  }

  final List<LevelPass> passes;
  final LevelPass? firstClear;
  final LevelPass? bestScore;
  final LevelPass? bestSpeed;
  final LevelPass? bestAccuracy;

  int get totalClears => passes.length;
  int get uniquePlayers => {for (final pass in passes) pass.playerName}.length;

  /// 점수가 높은 순. 같은 사람은 가장 좋은 기록만 남긴다.
  List<LevelPass> get leaderboard {
    final best = <String, LevelPass>{};
    for (final pass in passes) {
      final current = best[pass.playerName];
      if (current == null || pass.score > current.score) best[pass.playerName] = pass;
    }
    return best.values.toList()..sort((a, b) => b.score.compareTo(a.score));
  }
}

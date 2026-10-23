import '../json.dart';
import '../l10n.dart';

/// A pass on a level. GET /v2/database/passes/level/{id}
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
      playerName: (player is Map<String, dynamic> ? asStringOrNull(player['name']) : null) ?? l10n.unknown,
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
      // Old passes only say whether they were on ADOFAI 2, without a version number.
      era: AdofaiEra.fromApi(json['adofaiVersion']) ?? (asBool(json['isAdofaiV2']) ? AdofaiEra.v2 : AdofaiEra.pre340),
      isXPerfectMode: asBool(json['isXPerfectMode']),
      isAutoSubmitted: json['submissionSource'] == 'auto_submission',
    );
  }

  final int id;

  /// The level of the pass, used to find it when a pass is opened on its own.
  final int? levelId;
  final int playerId;
  final String playerName;

  /// Profile picture. The picture uploaded to TUF comes first; if it
  /// fails to load, [playerAvatarFallback] (Discord) is used.
  final String? playerAvatar;
  final String? playerAvatarFallback;

  /// Two-letter country code (e.g. "KR").
  final String? country;

  final double score;

  /// 0~1.
  final double accuracy;
  final double speed;
  final PassJudgements? judgements;
  final String? videoLink;
  final String? videoTitle;
  final DateTime? clearedAt;

  /// Difficulty as felt by the player (e.g. "U16").
  final String? feelingRating;

  /// Difficulty expected by reviewers, or null.
  final String? expectedRating;

  final bool isWorldsFirst;

  /// World's first pure perfect (100% accuracy).
  final bool isWorldsFirstPP;

  /// Number of keys used. Old passes only have [is12K]/[is16K].
  final int? keyCount;
  final bool is12K;
  final bool is16K;
  final bool isNoHoldTap;

  final AdofaiEra era;

  /// Played with 3.4.0's X-Perfect judgements (Perfect−, Perfect, Perfect+).
  final bool isXPerfectMode;

  /// Submitted straight from the game (not a video submission).
  final bool isAutoSubmitted;

  /// Key count label like "16K", or null if there is nothing to show.
  String? get keyCountLabel => switch (keyCount) {
    final count? => l10n.keyCount(count),
    null when is16K => l10n.keys16,
    null when is12K => l10n.keys12,
    _ => null,
  };

  /// Whether to show the Perfect−/Perfect+ columns: for X-Perfect passes or when they have values (as on the website).
  bool get showsXPerfect => isXPerfectMode || (judgements?.hasXPerfectCounts ?? false);

  /// An X-Perfect pass where every judgement is the center Perfect (pure X-Perfect).
  bool get isPureXPerfect {
    final counts = judgements;
    return isXPerfectMode && counts != null && counts.total > 0 && counts.perfect == counts.total;
  }

  /// 100% accuracy (pure perfect), unless it counts as pure X-Perfect.
  bool get isPurePerfect => accuracy >= 1 && !isPureXPerfect;
}

/// Game version era of a pass. TUF splits eras where the judgement system changed.
enum AdofaiEra {
  /// Up to v2.9.8, before the timing engine change.
  v2,

  /// Up to v3.3.1, before X-Perfect judgements.
  pre340,

  /// v3.4.0 and later.
  latest;

  /// The API's adofaiVersion value (1, 2, 3), or null if unknown.
  static AdofaiEra? fromApi(Object? value) => switch (asIntOrNull(value)) {
    1 => v2,
    2 => pre340,
    3 => latest,
    _ => null,
  };
}

/// Profile picture URLs. Like the website, the picture uploaded to TUF
/// comes first, with the Discord picture (pfp) as a fallback.
class AvatarUrls {
  const AvatarUrls({this.primary, this.fallback});

  /// Picked from player info ([json]); pictures sit on the player or its user account.
  factory AvatarUrls.of(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : null;
    final pfp = asStringOrNull(json['pfp']) ?? asStringOrNull(user?['pfp']);
    final uploaded = asStringOrNull(json['avatarUrl']) ?? asStringOrNull(user?['avatarUrl']);
    if (uploaded == null) return AvatarUrls(primary: pfp);
    return AvatarUrls(primary: _staticUnlessAllowed(_medium(uploaded.trim()), user ?? json), fallback: pfp);
  }

  /// TUF stores pictures in several sizes. The original is about 200 KB,
  /// so small avatars use the medium size (about 20 KB).
  static String _medium(String url) => url.contains('/images/profile/')
      ? url.replaceAll(RegExp(r'/(?:small|medium|large|original)(?=/|\.|\?|#|$)'), '/medium')
      : url;

  final String? primary;
  final String? fallback;

  /// Animated pictures are only shown for TUF Stellar supporters; others get the still version (_static).
  static String _staticUnlessAllowed(String url, Map<String, dynamic> owner) {
    if (owner['avatarIsGif'] != true) return url;
    final expires = DateTime.tryParse(asStringOrNull(owner['tufStellarSubscriptionExpiresAt']) ?? '');
    if (expires != null && expires.isAfter(DateTime.now())) return url;
    return url.contains('_animated') ? url.replaceAll('_animated', '_static') : '${url}_static';
  }
}

/// Details of a single pass. GET /v2/database/passes/{id}
/// Includes how much the pass adds to the player's ranked score.
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

  /// The player's overall rank.
  final int rank;
}

/// What a pass adds to the ranked score.
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

  /// Current ranked score, and the score without this pass.
  final double current;
  final double previous;

  /// Score added by this pass.
  final double impact;

  /// Whether the pass counts toward the ranked score. If not, it could have added [potentialImpact].
  final bool countsForRanked;
  final double potentialImpact;
}

/// The player behind a pass. GET /v2/database/players/{id}
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
    // Scores and rank live in stats; fall back to the top-level values.
    final stats = json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : const {};
    final topDiff = stats['topDiff'] ?? json['topDiff'];
    return PlayerProfile(
      id: asInt(json['id']),
      name: asStringOrNull(json['name']) ?? l10n.unknown,
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

  /// Profile picture, and the one to use if it fails to load.
  final String? avatar;
  final String? avatarFallback;

  /// Ranked score and its rank.
  final double rankedScore;
  final int rank;

  /// Highest difficulty cleared (e.g. "U16").
  final String? topDifficulty;
  final double averageAccuracy;
  final int totalPasses;
  final int worldsFirstCount;
}

/// Judgement counts, in the same order as the website's leaderboard.
///
/// From 3.4.0, X-Perfect judgements split Perfect into Perfect−, Perfect and Perfect+.
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

  /// Slightly early and late Perfect in X-Perfect mode; they count as Perfect for accuracy.
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

  /// From earliest to latest. With [xPerfect], the Perfect−/Perfect+ columns are included.
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

/// Judgement kinds, named like the website (Korean) and the game (English).
enum Judgement {
  tooEarly,
  early,
  earlyPerfect,
  perfectMinus,
  perfect,
  perfectPlus,
  latePerfect,
  late,
  tooLate;

  String get label => switch (this) {
    tooEarly => l10n.judgementTooEarly,
    early => l10n.judgementEarly,
    earlyPerfect => l10n.judgementEarlyPerfect,
    perfectMinus => l10n.judgementPerfectMinus,
    perfect => l10n.judgementPerfect,
    perfectPlus => l10n.judgementPerfectPlus,
    latePerfect => l10n.judgementLatePerfect,
    late => l10n.judgementLate,
    tooLate => l10n.judgementTooLate,
  };
}

/// Summary of a level's passes (first clear, best score, ...).
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

  /// Highest score first, keeping only each player's best pass.
  List<LevelPass> get leaderboard {
    final best = <String, LevelPass>{};
    for (final pass in passes) {
      final current = best[pass.playerName];
      if (current == null || pass.score > current.score) best[pass.playerName] = pass;
    }
    return best.values.toList()..sort((a, b) => b.score.compareTo(a.score));
  }
}

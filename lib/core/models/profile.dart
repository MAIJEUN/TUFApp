import '../json.dart';
import '../l10n.dart';
import 'level.dart';
import 'pack.dart';
import 'pass.dart';

/// 플레이어 페이지. GET /v3/players/{id}/profile
class PlayerProfileDetail {
  const PlayerProfileDetail({
    required this.id,
    required this.name,
    this.country,
    this.avatar = const AvatarUrls(),
    this.handle,
    this.rank = 0,
    this.highestRank,
    this.followerCount,
    this.showFollowerCount = true,
    this.bio = const ProfileBio(),
    this.scores = const {},
    this.topScores = const {},
    this.potentialTopScores = const {},
    this.placements = const [],
    this.placementOrderIds = const [],
    this.modules = const ProfileModules(),
    this.creatorId,
    this.banner = const ProfileBanner(),
    this.aliases = const [],
    this.youtubeChannels = const [],
    this.funFacts = const {},
    this.createdAt,
  });

  factory PlayerProfileDetail.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final highest = _map(json['highestRankedScore']);
    final highestDate = DateTime.tryParse(asStringOrNull(highest?['date']) ?? '');
    final highestRank = asInt(highest?['rank']);
    return PlayerProfileDetail(
      id: asInt(json['id']),
      name: asStringOrNull(json['name']) ?? tr('알 수 없음', 'Unknown'),
      country: asStringOrNull(json['country']),
      avatar: AvatarUrls.of(json),
      handle: asStringOrNull(user?['username']),
      rank: asInt(json['rankedScoreRank']),
      highestRank: highestRank > 0 && highestDate != null ? (rank: highestRank, date: highestDate) : null,
      followerCount: asIntOrNull(json['followerCount']),
      showFollowerCount: json['showFollowerCount'] != false,
      bio: ProfileBio.fromJson(json, stellar: isStellarActive(user)),
      scores: {for (final key in PlayerScoreKey.values) key: ?asDoubleOrNull(json[key.name])},
      topScores: _impacts(json['topScores']),
      potentialTopScores: _impacts(json['potentialTopScores']),
      placements: [for (final row in asObjectList(json['tournamentPlacements'])) TournamentPlacement.fromJson(row)],
      placementOrderIds: _ids(json['placementOrderIds']),
      modules: ProfileModules.fromJson(json),
      creatorId: asIntOrNull(_map(user?['creator'])?['id']),
      banner: ProfileBanner.fromJson(json, user),
      aliases: _aliasNames(json['aliases']),
      youtubeChannels: [for (final row in asObjectList(json['youtubeChannels'])) ?YoutubeChannel.fromJson(row)],
      funFacts: _map(json['funFacts']) ?? const {},
      createdAt: DateTime.tryParse(asStringOrNull(json['createdAt']) ?? ''),
    );
  }

  final int id;
  final String name;
  final String? country;
  final AvatarUrls avatar;

  /// TUF 계정 이름 (@로 보여준다). 계정과 연결되지 않았으면 null.
  final String? handle;

  /// 랭크 점수 순위. 0이면 순위 없음.
  final int rank;

  /// 지금까지 가장 높았던 순위와 그 날.
  final ({int rank, DateTime date})? highestRank;
  final int? followerCount;
  final bool showFollowerCount;
  final ProfileBio bio;
  final Map<PlayerScoreKey, double> scores;

  /// 랭크 점수에 들어간 기록 (기록 id → 보탠 점수).
  final Map<int, double> topScores;

  /// 레벨 파일이 없어 반영되지 않았지만 들어갈 수 있었던 기록.
  final Map<int, double> potentialTopScores;
  final List<TournamentPlacement> placements;
  final List<int> placementOrderIds;
  final ProfileModules modules;

  /// 같은 사람의 제작자 페이지.
  final int? creatorId;
  final ProfileBanner banner;
  final List<String> aliases;
  final List<YoutubeChannel> youtubeChannels;

  /// 재미있는 통계 (클리어 수, 판정 합계, 기록 등). 사이트가 주는 그대로 둔다.
  final Map<String, dynamic> funFacts;
  final DateTime? createdAt;

  double score(PlayerScoreKey key) => scores[key] ?? 0;
}

/// 플레이어 점수 종류. 이름은 API 필드 이름과 같다.
enum PlayerScoreKey {
  rankedScore(
    '랭크 점수',
    'Ranked Score',
    '상위 20개 클리어 점수 합산 (순위 낮을수록 감소, 재클리어 제외)',
    'Decaying sum of 20 best clears (excluding reclears)',
  ),
  totalScoreV2('총 점수', 'Total Score', '모든 클리어 점수 합산 (재클리어 제외)', 'Sum of all clears without reclears'),
  generalScore('일반 점수', 'General Score', '모든 클리어 점수 합산 (재클리어 포함)', 'Sum of all clears including reclears'),
  ppScore(
    '완벽한 플레이 점수',
    'PP Score',
    '랭크 점수와 같지만, 모든 클리어가 완벽한 플레이',
    'Ranked Score, but all clears must also be pure perfects',
  ),
  wfScore('세계 최초 점수', 'WF Score', '세계 최초 클리어한 레벨 기본 점수 합산', "Sum of all level base scores from world's first passes"),
  wfPPScore(
    '세계 최초 완플 점수',
    'WF PP Score',
    '세계 최초 완벽한 플레이 클리어한 레벨 기본 점수 합산',
    "Sum of all level base scores from world's first pure perfect passes",
  ),
  score12K('12키 점수', '12K Score', '랭크 점수와 같지만, 12키 클리어 한정', 'Ranked Score, but all clears must be 12K'),
  averageXacc('평균 절대정확도', 'Average X-acc', '상위 20개 클리어의 평균 정확도', 'Average accuracy of top 20 passes');

  const PlayerScoreKey(this._ko, this._en, this._descriptionKo, this._descriptionEn);

  final String _ko;
  final String _en;
  final String _descriptionKo;
  final String _descriptionEn;

  String get label => tr(_ko, _en);
  String get description => tr(_descriptionKo, _descriptionEn);
}

/// 제작자 페이지. GET /v3/creators/{id}/profile
class CreatorProfileDetail {
  const CreatorProfileDetail({
    required this.id,
    required this.name,
    this.country,
    this.avatar = const AvatarUrls(),
    this.handle,
    this.verification = CreatorVerification.pending,
    this.uploadConditions,
    this.followerCount,
    this.showFollowerCount = true,
    this.chartsTotal = 0,
    this.totalChartClears = 0,
    this.curationTypeCounts = const {},
    this.displayCurationTypeIds = const [],
    this.playerId,
    this.bio = const ProfileBio(),
    this.placements = const [],
    this.placementOrderIds = const [],
    this.modules = const ProfileModules(),
    this.banner = const ProfileBanner(),
    this.aliases = const [],
    this.youtubeChannels = const [],
    this.funFacts = const {},
  });

  factory CreatorProfileDetail.fromJson(Map<String, dynamic> json) {
    // 응답이 제작자 문서를 감싸서 올 때도 있다.
    final doc = _map(json['creator']) ?? _map(json['doc']) ?? json;
    final user = _map(json['user']) ?? _map(doc['user']);
    final stats = _map(json['stats']) ?? doc;
    return CreatorProfileDetail(
      id: asInt(doc['id']),
      name: asStringOrNull(doc['name']) ?? tr('알 수 없음', 'Unknown'),
      country: asStringOrNull(user?['country']) ?? asStringOrNull(doc['country']),
      avatar: AvatarUrls.of({...doc, 'user': ?user}),
      handle: asStringOrNull(user?['username']),
      verification: CreatorVerification.fromApi(doc['verificationStatus'] ?? json['verificationStatus']),
      uploadConditions: asStringOrNull(json['uploadConditions'])?.trim(),
      followerCount: asIntOrNull(json['followerCount']),
      showFollowerCount: json['showFollowerCount'] != false,
      chartsTotal: asInt(stats['chartsTotal'] ?? json['chartsTotal']),
      totalChartClears: asInt(stats['totalChartClears'] ?? json['totalChartClears']),
      curationTypeCounts: {
        for (final entry in (_map(json['curationTypeCounts']) ?? const {}).entries)
          ?int.tryParse(entry.key): asInt(entry.value),
      },
      displayCurationTypeIds: _ids(json['displayCurationTypeIds']),
      playerId: asIntOrNull(user?['playerId']),
      bio: ProfileBio.fromJson(json, stellar: isStellarActive(user)),
      placements: [for (final row in asObjectList(json['tournamentPlacements'])) TournamentPlacement.fromJson(row)],
      placementOrderIds: _ids(json['placementOrderIds']),
      modules: ProfileModules.fromJson(json),
      banner: ProfileBanner.fromJson(json, user),
      aliases: _aliasNames(json['creatorAliases'] ?? json['aliases']),
      youtubeChannels: [
        for (final row in asObjectList(doc['youtubeChannels'] ?? json['youtubeChannels']))
          ?YoutubeChannel.fromJson(row),
      ],
      funFacts: _map(json['funFacts']) ?? const {},
    );
  }

  final int id;
  final String name;
  final String? country;
  final AvatarUrls avatar;
  final String? handle;
  final CreatorVerification verification;

  /// 레벨을 올릴 때 지켜 달라는 조건 (제작자가 적어 둔 글).
  final String? uploadConditions;
  final int? followerCount;
  final bool showFollowerCount;
  final int chartsTotal;
  final int totalChartClears;

  /// 큐레이션 유형 id → 그 유형이 붙은 레벨 수.
  final Map<int, int> curationTypeCounts;

  /// 제작자가 머리글에 보이도록 고른 큐레이션 유형 (없으면 자동으로 고른다).
  final List<int> displayCurationTypeIds;

  /// 같은 사람의 플레이어 페이지.
  final int? playerId;
  final ProfileBio bio;
  final List<TournamentPlacement> placements;
  final List<int> placementOrderIds;
  final ProfileModules modules;
  final ProfileBanner banner;
  final List<String> aliases;
  final List<YoutubeChannel> youtubeChannels;
  final Map<String, dynamic> funFacts;

  /// 큐레이션 유형이 하나라도 붙은 레벨 수.
  int get curatedLevels => asInt(_map(funFacts['curation'])?['curatedLevels']);
}

/// 제작자가 TUF에 레벨을 올리는 것을 허락했는지.
enum CreatorVerification {
  allowed('허가', 'Allowed'),
  conditional('조건 있음', 'Conditional'),
  pending('대기 중', 'Pending'),
  declined('거절', 'Declined');

  const CreatorVerification(this._ko, this._en);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);

  static CreatorVerification fromApi(Object? value) =>
      values.where((status) => status.name == value).firstOrNull ?? pending;
}

/// 자기소개. 후원자(TUF Stellar)는 글·링크·그림을 블록으로 꾸밀 수 있고, 아니면 글만 보인다.
class ProfileBio {
  const ProfileBio({this.text, this.blocks = const []});

  factory ProfileBio.fromJson(Map<String, dynamic> json, {required bool stellar}) {
    final canvas = _map(json['bioCanvas']);
    final rawBlocks = asObjectList(canvas?['blocks']);
    final assets = _map(json['bioCanvasImageAssets']) ?? const {};
    final blocks = [for (final block in rawBlocks) ?BioBlock.fromJson(block, assets)];

    // 블록으로 꾸몄는데 후원이 끝났으면, 글·링크 블록만 글로 바꿔 보여준다 (사이트와 같다).
    if (blocks.isNotEmpty && stellar) return ProfileBio(blocks: blocks);
    if (blocks.isNotEmpty) {
      final text = [
        for (final block in blocks)
          if (block.plainText case final plain? when plain.trim().isNotEmpty) plain.trim(),
      ].join('\n\n');
      return ProfileBio(text: text.isEmpty ? null : text);
    }
    return ProfileBio(text: asStringOrNull(json['bio'])?.trim());
  }

  final String? text;
  final List<BioBlock> blocks;

  bool get isEmpty => blocks.isEmpty && (text == null || text!.isEmpty);
}

/// 자기소개 블록 하나.
sealed class BioBlock {
  const BioBlock();

  static BioBlock? fromJson(Map<String, dynamic> json, Map<String, dynamic> assets) {
    final data = _map(json['data']) ?? const {};
    final id = asStringOrNull(json['id']);
    return switch (json['type']) {
      'text' => BioTextBlock(heading: asStringOrNull(data['heading']), body: asStringOrNull(data['body'])),
      'link' => switch (asStringOrNull(data['url'])) {
        final url? => BioLinkBlock(label: asStringOrNull(data['label']) ?? url, url: url),
        null => null,
      },
      'social' => BioSocialBlock(
        links: [
          for (final link in asObjectList(data['links']))
            if (asStringOrNull(link['url']) case final url?)
              (platform: asStringOrNull(link['platform']) ?? '', url: url),
        ],
      ),
      'image' => switch (asStringOrNull(_map(assets[id])?['url']) ?? asStringOrNull(data['url'])) {
        final url? => BioImageBlock(url: url, alt: asStringOrNull(data['alt'])),
        null => null,
      },
      'embed' => switch (asStringOrNull(data['url'])) {
        final url? => BioEmbedBlock(url: url, title: asStringOrNull(data['title'])),
        null => null,
      },
      'featuredLevels' => BioFeaturedBlock(
        passes: data['mode'] == 'passes',
        ids: _ids(data['mode'] == 'passes' ? data['passIds'] : data['levelIds']),
      ),
      _ => null,
    };
  }

  /// 후원이 끝났을 때 글로 바꿔 보여줄 내용. 글로 보여주지 않는 블록은 null.
  String? get plainText => null;
}

class BioTextBlock extends BioBlock {
  const BioTextBlock({this.heading, this.body});

  final String? heading;
  final String? body;

  @override
  String? get plainText => [?heading?.trim(), ?body?.trim()].where((part) => part.isNotEmpty).join('\n');
}

class BioLinkBlock extends BioBlock {
  const BioLinkBlock({required this.label, required this.url});

  final String label;
  final String url;

  @override
  String? get plainText => '$label ($url)';
}

class BioSocialBlock extends BioBlock {
  const BioSocialBlock({required this.links});

  final List<({String platform, String url})> links;

  @override
  String? get plainText => links.map((link) => '${link.platform}: ${link.url}').join(' | ');
}

class BioImageBlock extends BioBlock {
  const BioImageBlock({required this.url, this.alt});

  final String url;
  final String? alt;
}

class BioEmbedBlock extends BioBlock {
  const BioEmbedBlock({required this.url, this.title});

  final String url;
  final String? title;
}

/// 고른 레벨이나 기록 목록.
class BioFeaturedBlock extends BioBlock {
  const BioFeaturedBlock({required this.passes, required this.ids});

  final bool passes;
  final List<int> ids;
}

/// 머리글 위쪽 배너. 사이트의 기본 배너 그림 중 하나이거나, 후원자가 올린 그림.
class ProfileBanner {
  const ProfileBanner({this.imageUrl});

  factory ProfileBanner.fromJson(Map<String, dynamic> json, Map<String, dynamic>? user) {
    final custom = asStringOrNull(json['customBannerUrl'])?.trim();
    if (custom != null && custom.startsWith('http') && isStellarActive(user)) return ProfileBanner(imageUrl: custom);
    final preset = asStringOrNull(json['bannerPreset'])?.trim().replaceFirst(RegExp(r'^/+'), '');
    // 기본 배너(default.svg)는 단순한 그라데이션이라 앱에서 직접 그린다.
    if (preset == null || preset == defaultPreset) return const ProfileBanner();
    return ProfileBanner(imageUrl: 'https://tuforums.com/$preset');
  }

  static const defaultPreset = 'banners/default.svg';

  /// null이면 기본 배너.
  final String? imageUrl;
}

/// 프로필에 연결된 YouTube 채널.
class YoutubeChannel {
  const YoutubeChannel({required this.url, required this.label});

  static YoutubeChannel? fromJson(Map<String, dynamic> json) {
    final id = asStringOrNull(json['channelId']);
    final handle = asStringOrNull(json['handle'])?.replaceFirst('@', '');
    final url =
        asStringOrNull(json['url']) ??
        (handle != null ? 'https://www.youtube.com/@$handle' : null) ??
        (id != null ? 'https://www.youtube.com/channel/$id' : null);
    if (url == null) return null;
    return YoutubeChannel(url: url, label: handle != null ? '@$handle' : asStringOrNull(json['title']) ?? 'YouTube');
  }

  final String url;
  final String label;
}

/// 대회 입상 하나.
class TournamentPlacement {
  const TournamentPlacement({
    required this.id,
    required this.tierLabel,
    this.tierRankWeight,
    this.tournamentId,
    this.tournamentName = '',
    this.tournamentSortWeight = 0,
    this.sortYear,
    this.showBestTiersOnly = true,
    this.iconUrl,
    this.seriesId,
    this.seriesName,
    this.seriesSortWeight = unseriesedSortWeight,
    this.packRef,
    this.teamName,
    this.levelId,
    this.levelName,
    this.isPublic = true,
  });

  factory TournamentPlacement.fromJson(Map<String, dynamic> json) {
    final tier = _map(json['tier']) ?? const {};
    final tournament = _map(json['tournament']);
    final series = _map(tournament?['series']);
    final level = _map(json['level']);
    return TournamentPlacement(
      id: asInt(json['creditId'] ?? json['id']),
      tierLabel: asStringOrNull(tier['label']) ?? asStringOrNull(tier['code']) ?? '',
      tierRankWeight: asIntOrNull(tier['rankWeight']),
      tournamentId: asIntOrNull(tournament?['id']),
      tournamentName: asStringOrNull(tournament?['fullName']) ?? asStringOrNull(tournament?['shortName']) ?? '',
      tournamentSortWeight: asInt(tournament?['sortWeight']),
      sortYear: asIntOrNull(tournament?['sortYear']),
      showBestTiersOnly: tournament?['showBestTiersOnly'] != false,
      iconUrl:
          asStringOrNull(json['resolvedTournamentIconUrl']) ??
          asStringOrNull(tournament?['iconUrl']) ??
          asStringOrNull(series?['logoUrl']) ??
          asStringOrNull(tier['iconUrl']),
      seriesId: asIntOrNull(series?['id']),
      seriesName: asStringOrNull(series?['name']),
      seriesSortWeight: asIntOrNull(series?['sortWeight']) ?? unseriesedSortWeight,
      packRef: asStringOrNull(json['packRef']),
      teamName: asStringOrNull(json['teamName']),
      levelId: asIntOrNull(json['levelId']) ?? asIntOrNull(level?['id']),
      levelName: asStringOrNull(level?['song']) ?? asStringOrNull(level?['name']),
      isPublic:
          json['isPending'] != true &&
          json['withdrew'] != true &&
          json['disqualified'] != true &&
          json['isProfileHidden'] != true,
    );
  }

  /// 시리즈가 없는 대회는 맨 뒤로 보낸다.
  static const unseriesedSortWeight = 100;

  final int id;

  /// 예: "1st Place"
  final String tierLabel;

  /// 작을수록 높은 순위.
  final int? tierRankWeight;
  final int? tournamentId;
  final String tournamentName;
  final int tournamentSortWeight;
  final int? sortYear;

  /// 한 대회에서 여러 번 입상했으면 가장 좋은 것만 보여준다.
  final bool showBestTiersOnly;
  final String? iconUrl;
  final int? seriesId;
  final String? seriesName;
  final int seriesSortWeight;

  /// 대회 팩 (팩 화면에서 연다).
  final String? packRef;
  final String? teamName;
  final int? levelId;
  final String? levelName;

  /// 대기 중·기권·실격·숨김이 아닌 입상.
  final bool isPublic;
}

/// 사이트의 프로필 모듈 배치. 저장된 배치가 없으면 기본 순서를 쓴다.
class ProfileModules {
  const ProfileModules({this.stored, this.favorites = const {}});

  factory ProfileModules.fromJson(Map<String, dynamic> json) {
    final document = _map(json['profileModules']);
    final rows = asObjectList(document?['modules']);
    final seen = <String>{};
    final modules = <({String id, String type})>[];
    for (final row in rows) {
      final id = asStringOrNull(row['id']);
      final type = asStringOrNull(row['type'])?.trim();
      if (id == null || type == null || !seen.add(type)) continue;
      modules.add((id: id, type: type));
    }

    final resolved = _map(json['profileModulesResolved']) ?? const {};
    return ProfileModules(
      stored: document == null || document['modules'] is! List ? null : modules,
      favorites: {
        for (final entry in resolved.entries)
          entry.key: [for (final item in asObjectList(_map(entry.value)?['items'])) ?FavoriteItem.fromJson(item)],
      },
    );
  }

  /// 사용자가 저장한 배치. null이면 기본 배치.
  final List<({String id, String type})>? stored;

  /// 즐겨찾기 모듈 id → 담긴 항목.
  final Map<String, List<FavoriteItem>> favorites;

  static const playerStock = ['bio', 'tournaments', 'scoreBreakdown', 'difficulty', 'rankHistory', 'scores'];
  static const playerTypes = {...playerStock, 'favorite', 'keyboards'};
  static const creatorStock = ['bio', 'tournaments', 'difficulty', 'charts'];
  static const creatorTypes = {...creatorStock, 'favorite'};

  /// 보여줄 모듈 순서. 꼭 있어야 하는 모듈(플레이어는 기록, 제작자는 레벨)은 없으면 끝에 붙인다.
  List<({String id, String type})> layoutFor({required bool player}) {
    final stock = player ? playerStock : creatorStock;
    final allowed = player ? playerTypes : creatorTypes;
    final required = player ? 'scores' : 'charts';
    final saved = stored;
    if (saved == null) return [for (final type in stock) (id: 'stock-$type', type: type)];
    final layout = [
      for (final module in saved)
        if (allowed.contains(module.type)) module,
    ];
    if (!layout.any((module) => module.type == required)) layout.add((id: 'stock-$required', type: required));
    return layout;
  }
}

/// 즐겨찾기 모듈의 항목 하나 (기록, 레벨, 팩, 플레이어, 제작자).
sealed class FavoriteItem {
  const FavoriteItem();

  static FavoriteItem? fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final entity = _map(json[kind]);
    if (entity == null) return null;
    return switch (kind) {
      'pass' => FavoritePass(PlayerPassEntry.fromJson(entity)),
      'level' => FavoriteLevel(Level.fromJson(entity)),
      'pack' => FavoritePack(LevelPack.fromJson(entity)),
      'player' => FavoritePlayer(
        id: asInt(entity['id']),
        name: asStringOrNull(entity['name']) ?? tr('알 수 없음', 'Unknown'),
        country: asStringOrNull(entity['country']),
        avatar: AvatarUrls.of(entity),
        rankedScore: asDoubleOrNull(_map(entity['stats'])?['rankedScore']) ?? asDoubleOrNull(entity['rankedScore']),
        rank: asIntOrNull(_map(entity['stats'])?['rankedScoreRank']),
      ),
      'creator' => FavoriteCreator(
        id: asInt(entity['id']),
        name: asStringOrNull(entity['name']) ?? tr('알 수 없음', 'Unknown'),
        avatar: AvatarUrls.of(entity),
        chartsTotal: asIntOrNull(entity['chartsTotal']),
      ),
      _ => null,
    };
  }
}

class FavoritePass extends FavoriteItem {
  const FavoritePass(this.entry);

  final PlayerPassEntry entry;
}

class FavoriteLevel extends FavoriteItem {
  const FavoriteLevel(this.level);

  final Level level;
}

class FavoritePack extends FavoriteItem {
  const FavoritePack(this.pack);

  final LevelPack pack;
}

class FavoritePlayer extends FavoriteItem {
  const FavoritePlayer({
    required this.id,
    required this.name,
    this.country,
    required this.avatar,
    this.rankedScore,
    this.rank,
  });

  final int id;
  final String name;
  final String? country;
  final AvatarUrls avatar;
  final double? rankedScore;
  final int? rank;
}

class FavoriteCreator extends FavoriteItem {
  const FavoriteCreator({required this.id, required this.name, required this.avatar, this.chartsTotal});

  final int id;
  final String name;
  final AvatarUrls avatar;
  final int? chartsTotal;
}

/// 플레이어 페이지의 기록 목록 한 줄: 기록과 그 레벨. GET /v3/players/{id}/passes
class PlayerPassEntry {
  const PlayerPassEntry({required this.pass, required this.level, this.levelHidden = false, this.playerId});

  factory PlayerPassEntry.fromJson(Map<String, dynamic> json) {
    final level = _map(json['level']) ?? const {};
    return PlayerPassEntry(
      pass: LevelPass.fromJson(json),
      level: Level.fromJson({...level, 'id': level['id'] ?? json['levelId']}),
      levelHidden: level['isHidden'] == true,
      playerId: asIntOrNull(_map(json['player'])?['id']) ?? asIntOrNull(json['playerId']),
    );
  }

  final LevelPass pass;
  final Level level;

  /// 숨겨진 레벨이면 이름과 아이콘을 가린다.
  final bool levelHidden;
  final int? playerId;
}

/// 기록 목록 정렬. 이름은 API 값과 같다.
enum PlayerPassSort {
  score('점수', 'Score'),
  impact('랭크', 'Impact'),
  speed('속도', 'Speed'),
  date('날짜', 'Date'),
  xacc('절대정확도', 'X-Accuracy'),
  difficulty('난이도', 'Difficulty');

  const PlayerPassSort(this._ko, this._en);

  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
}

/// 순위 변화 한 점. GET /v3/players/{id}/rank-history
class RankHistoryPoint {
  const RankHistoryPoint({required this.date, this.rankedRank, this.generalRank});

  factory RankHistoryPoint.fromJson(Map<String, dynamic> json) => RankHistoryPoint(
    // 날짜만 오므로 (YYYY-MM-DD) UTC 하루로 읽는다.
    date:
        DateTime.tryParse('${asStringOrNull(json['date'])}T00:00:00Z') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    rankedRank: asIntOrNull(json['rankedScoreRank']),
    generalRank: asIntOrNull(json['generalScoreRank']),
  );

  final DateTime date;
  final int? rankedRank;
  final int? generalRank;
}

/// 후원(TUF Stellar) 중인지. 후원자만 움직이는 사진·직접 올린 배너·꾸민 소개를 보여준다.
bool isStellarActive(Map<String, dynamic>? user) {
  if (user == null) return false;
  final expires = DateTime.tryParse(asStringOrNull(user['tufStellarSubscriptionExpiresAt']) ?? '');
  if (expires != null && expires.isAfter(DateTime.now())) return true;
  // 최고 관리자는 늘 쓸 수 있다 (권한 비트 62).
  final flags = BigInt.tryParse('${user['permissionFlags'] ?? ''}');
  return flags != null && (flags >> 62) & BigInt.one == BigInt.one;
}

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;

List<int> _ids(Object? value) => value is List ? [for (final id in value) ?asIntOrNull(id)] : const [];

Map<int, double> _impacts(Object? value) => {
  for (final row in asObjectList(value)) ?asIntOrNull(row['id']): asDoubleOrNull(row['impact']) ?? 0,
};

List<String> _aliasNames(Object? value) => [
  for (final row in value is List ? value : const [])
    if (row is String) row else if (row is Map<String, dynamic>) ?asStringOrNull(row['name'] ?? row['alias']),
];

import '../json.dart';
import '../l10n.dart';
import 'level.dart';
import 'pack.dart';
import 'pass.dart';

/// Player page. GET /v3/players/{id}/profile
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

  /// TUF account name (shown with @), or null if no account is linked.
  final String? handle;

  /// Ranked score rank; 0 if unranked.
  final int rank;

  /// Highest rank so far and when it was reached.
  final ({int rank, DateTime date})? highestRank;
  final int? followerCount;
  final bool showFollowerCount;
  final ProfileBio bio;
  final Map<PlayerScoreKey, double> scores;

  /// Passes counted in the ranked score (pass id → score added).
  final Map<int, double> topScores;

  /// Passes that could have counted but don't because the level file is missing.
  final Map<int, double> potentialTopScores;
  final List<TournamentPlacement> placements;
  final List<int> placementOrderIds;
  final ProfileModules modules;

  /// The same person's creator page.
  final int? creatorId;
  final ProfileBanner banner;
  final List<String> aliases;
  final List<YoutubeChannel> youtubeChannels;

  /// Fun facts (clear counts, judgement totals, records, ...), kept as the website sends them.
  final Map<String, dynamic> funFacts;
  final DateTime? createdAt;

  double score(PlayerScoreKey key) => scores[key] ?? 0;
}

/// Player score kinds. Names match the API fields.
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

/// Creator page. GET /v3/creators/{id}/profile
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
    // The creator document is sometimes wrapped.
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

  /// Conditions the creator asks uploaders to follow (free text).
  final String? uploadConditions;
  final int? followerCount;
  final bool showFollowerCount;
  final int chartsTotal;
  final int totalChartClears;

  /// Curation type id → number of levels with that type.
  final Map<int, int> curationTypeCounts;

  /// Curation types the creator picked for the header (chosen automatically if empty).
  final List<int> displayCurationTypeIds;

  /// The same person's player page.
  final int? playerId;
  final ProfileBio bio;
  final List<TournamentPlacement> placements;
  final List<int> placementOrderIds;
  final ProfileModules modules;
  final ProfileBanner banner;
  final List<String> aliases;
  final List<YoutubeChannel> youtubeChannels;
  final Map<String, dynamic> funFacts;

  /// Number of levels with at least one curation type.
  int get curatedLevels => asInt(_map(funFacts['curation'])?['curatedLevels']);
}

/// Whether the creator allows their levels to be uploaded to TUF.
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

/// Bio. TUF Stellar supporters compose it on a canvas of freely placed blocks; otherwise it is plain text.
class ProfileBio {
  const ProfileBio({this.text, this.blocks = const []});

  factory ProfileBio.fromJson(Map<String, dynamic> json, {required bool stellar}) {
    final canvas = _map(json['bioCanvas']);
    final rawBlocks = asObjectList(canvas?['blocks']);
    final assets = _map(json['bioCanvasImageAssets']) ?? const {};
    final blocks = <BioBlock>[];
    // Blocks saved with the old stacked layout are placed one under another, like the website does.
    var stackY = BioLayout.stagePadding;
    for (final raw in rawBlocks) {
      final block = BioBlock.fromJson(raw, assets, stackY: stackY);
      if (block == null) continue;
      blocks.add(block);
      stackY = block.layout.y + block.layout.h + BioLayout.blockGap;
    }

    // If the supporter status ended, block bios show their text, link and social blocks as plain text (as on the website).
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

  /// Canvas blocks in paint order (later blocks are drawn on top).
  final List<BioBlock> blocks;

  bool get isEmpty => blocks.isEmpty && (text == null || text!.isEmpty);
}

/// Where a block sits on the bio stage, following the website's normalizeLayout (utils/bioCanvas/layout.js).
class BioLayout {
  const BioLayout({required this.x, required this.y, required this.w, required this.h, this.rotation = 0});

  /// The website designs bios on a 1000×1200 stage and scales it down to fit narrower containers.
  static const stageWidth = 1000;
  static const stageHeight = 1200;
  static const stagePadding = 24;
  static const blockGap = 16;

  final int x;
  final int y;
  final int w;
  final int h;

  /// Clockwise rotation in degrees, around the block's center.
  final int rotation;

  factory BioLayout.fromJson(Object? raw, {required int defaultW, required int defaultH, required int stackY}) {
    final map = raw is Map<String, dynamic> ? raw : null;
    final legacy = map != null && (map.containsKey('align') || map.containsKey('width'));
    final freeform = map != null && const ['x', 'y', 'w', 'h'].any(map.containsKey);

    if (freeform && !legacy) {
      return BioLayout(
        x: _clampInt(map['x'], -stageWidth, stageWidth),
        y: _clampInt(map['y'], -stageHeight, stageHeight),
        w: _clampInt(map['w'], 40, stageWidth * 4),
        h: _clampInt(map['h'], 24, stageHeight * 4),
        rotation: _roundOrNull(map['rotation'])?.clamp(-360, 360) ?? 0,
      );
    }
    if (legacy) {
      // Old layouts only had a width (full or half) and an alignment, stacked top to bottom.
      final w = map['width'] == 'half' ? stageWidth ~/ 2 : stageWidth;
      final x = switch (map['align']) {
        'left' => 0,
        'right' => stageWidth - w,
        _ => (stageWidth - w) ~/ 2,
      };
      return BioLayout(x: x, y: stackY, w: w, h: defaultH);
    }
    return BioLayout(x: 0, y: 0, w: defaultW, h: defaultH);
  }

  /// Like the website's clampInt: a missing or invalid value becomes the minimum.
  static int _clampInt(Object? value, int min, int max) => (_roundOrNull(value) ?? min).clamp(min, max);

  static int? _roundOrNull(Object? value) {
    final n = asDoubleOrNull(value);
    return n == null || !n.isFinite ? null : n.round();
  }
}

/// One bio block.
sealed class BioBlock {
  const BioBlock(this.layout);

  final BioLayout layout;

  /// Whether the block's height is fixed. Link blocks only have a minimum height and grow with their content.
  bool get fixedHeight => true;

  static BioBlock? fromJson(Map<String, dynamic> json, Map<String, dynamic> assets, {required int stackY}) {
    final data = _map(json['data']) ?? const {};
    BioLayout layout(int w, int h) => BioLayout.fromJson(json['layout'], defaultW: w, defaultH: h, stackY: stackY);

    return switch (json['type']) {
      'text' => BioTextBlock(
        layout(600, 120),
        heading: asStringOrNull(data['heading'])?.trim(),
        body: data['body'] is String ? data['body'] as String : '',
        fontSize: _fontSize(data['fontSize'], 16),
        headingFontSize: _fontSize(data['headingFontSize'], 20),
        align: _align(data['align'], 'left'),
        color: _hexColor(data['color']),
      ),
      'link' => switch ((asStringOrNull(data['label'])?.trim(), _safeUrl(data['url']))) {
        (final label?, final url?) => BioLinkBlock(layout(320, 56), label: label, url: url),
        _ => null,
      },
      'social' => BioSocialBlock(
        layout(360, 64),
        links: [
          for (final link in asObjectList(data['links']))
            if (_safeUrl(link['url']) case final url?)
              (platform: asStringOrNull(link['platform']) ?? 'other', url: url, label: asStringOrNull(link['label'])),
        ],
        iconSize: _roundInRange(data['iconSize'], 24, 96, 40),
        gap: _roundInRange(data['gap'], 0, 48, 12),
        shape: switch (data['shape']) {
          'rounded' => 'rounded',
          'square' => 'square',
          _ => 'circle',
        },
        align: _align(data['align'], 'center'),
        showLabels: asBool(data['showLabels']),
      ),
      'image' => switch (asStringOrNull(_map(assets[asStringOrNull(json['id'])])?['url'])) {
        final url? => BioImageBlock(
          layout(600, 400),
          url: url,
          alt: asStringOrNull(data['alt'])?.trim(),
          crop: BioImageCrop.fromJson(_map(data['crop'])),
        ),
        null => null,
      },
      'embed' => switch (_safeUrl(data['url'])) {
        final url? => BioEmbedBlock(layout(640, 360), url: url, title: asStringOrNull(data['title'])?.trim()),
        null => null,
      },
      'featuredLevels' => BioFeaturedBlock(
        layout(700, 260),
        passes: data['mode'] == 'passes',
        ids: {
          for (final id in _ids(data['mode'] == 'passes' ? data['passIds'] : data['levelIds']))
            if (id > 0) id,
        }.take(6).toList(),
      ),
      _ => null,
    };
  }

  /// Plain text shown once the supporter status ended, or null for blocks not shown as text.
  String? get plainText => null;

  static int _fontSize(Object? value, int fallback) => _roundInRange(value, 12, 72, fallback);

  static int _roundInRange(Object? value, int min, int max, int fallback) {
    final n = asDoubleOrNull(value);
    return n == null || !n.isFinite ? fallback : n.round().clamp(min, max);
  }

  static String _align(Object? value, String fallback) =>
      value == 'left' || value == 'center' || value == 'right' ? value as String : fallback;

  /// "#abc" or "#aabbcc", like the website's parseTextBlockColor.
  static String? _hexColor(Object? value) {
    final text = asStringOrNull(value)?.trim();
    return text != null && RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$', caseSensitive: false).hasMatch(text)
        ? text.toLowerCase()
        : null;
  }

  /// Only http and https links, like the website's parseSafeUrl.
  static String? _safeUrl(Object? value) {
    final text = asStringOrNull(value)?.trim();
    final uri = text == null ? null : Uri.tryParse(text);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? text : null;
  }
}

class BioTextBlock extends BioBlock {
  const BioTextBlock(
    super.layout, {
    this.heading,
    required this.body,
    this.fontSize = 16,
    this.headingFontSize = 20,
    this.align = 'left',
    this.color,
  });

  final String? heading;

  /// Shown as an italic "Sample text" placeholder when empty, like the website.
  final String body;
  final int fontSize;
  final int headingFontSize;

  /// 'left', 'center' or 'right'.
  final String align;

  /// "#rrggbb" or "#rgb"; null uses the default colors.
  final String? color;

  @override
  String? get plainText => [?heading, body.trim()].where((part) => part.isNotEmpty).join('\n');
}

class BioLinkBlock extends BioBlock {
  const BioLinkBlock(super.layout, {required this.label, required this.url});

  final String label;
  final String url;

  @override
  bool get fixedHeight => false;

  @override
  String? get plainText => '$label ($url)';
}

class BioSocialBlock extends BioBlock {
  const BioSocialBlock(
    super.layout, {
    required this.links,
    this.iconSize = 40,
    this.gap = 12,
    this.shape = 'circle',
    this.align = 'center',
    this.showLabels = false,
  });

  final List<({String platform, String url, String? label})> links;
  final int iconSize;
  final int gap;

  /// 'circle', 'rounded' or 'square'.
  final String shape;

  /// 'left', 'center' or 'right'.
  final String align;
  final bool showLabels;

  @override
  String? get plainText => links.map((link) => '${link.platform}: ${link.url}').join(' | ');
}

/// How an image fills its frame: CSS object-fit and object-position, then zoomed around the focal point.
class BioImageCrop {
  const BioImageCrop({this.contain = false, this.focalX = 50, this.focalY = 50, this.zoom = 1});

  factory BioImageCrop.fromJson(Map<String, dynamic>? json) {
    double inRange(Object? value, double min, double max, double fallback) {
      final n = asDoubleOrNull(value);
      return n == null || !n.isFinite || n < min || n > max ? fallback : n;
    }

    return BioImageCrop(
      contain: json?['fit'] == 'contain',
      focalX: inRange(json?['focalX'], 0, 100, 50),
      focalY: inRange(json?['focalY'], 0, 100, 50),
      zoom: inRange(json?['zoom'], 1, 4, 1),
    );
  }

  /// object-fit: contain instead of cover.
  final bool contain;

  /// Focal point in percent (0–100).
  final double focalX;
  final double focalY;

  /// 1–4.
  final double zoom;
}

class BioImageBlock extends BioBlock {
  const BioImageBlock(super.layout, {required this.url, this.alt, this.crop = const BioImageCrop()});

  final String url;
  final String? alt;
  final BioImageCrop crop;
}

class BioEmbedBlock extends BioBlock {
  const BioEmbedBlock(super.layout, {required this.url, this.title});

  final String url;
  final String? title;
}

/// A list of up to six featured levels or passes, loaded by id.
class BioFeaturedBlock extends BioBlock {
  const BioFeaturedBlock(super.layout, {required this.passes, required this.ids});

  final bool passes;
  final List<int> ids;
}

/// Header banner: one of the website's preset images, or an image uploaded by a supporter.
class ProfileBanner {
  const ProfileBanner({this.imageUrl});

  factory ProfileBanner.fromJson(Map<String, dynamic> json, Map<String, dynamic>? user) {
    final custom = asStringOrNull(json['customBannerUrl'])?.trim();
    if (custom != null && custom.startsWith('http') && isStellarActive(user)) return ProfileBanner(imageUrl: custom);
    final preset = asStringOrNull(json['bannerPreset'])?.trim().replaceFirst(RegExp(r'^/+'), '');
    // The default banner (default.svg) is a simple gradient, drawn by the app itself.
    if (preset == null || preset == defaultPreset) return const ProfileBanner();
    return ProfileBanner(imageUrl: 'https://tuforums.com/$preset');
  }

  static const defaultPreset = 'banners/default.svg';

  /// null for the default banner.
  final String? imageUrl;
}

/// A YouTube channel linked to the profile.
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

/// One tournament placement.
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

  /// Tournaments without a series go last.
  static const unseriesedSortWeight = 100;

  final int id;

  /// e.g. "1st Place"
  final String tierLabel;

  /// Lower means a better placement.
  final int? tierRankWeight;
  final int? tournamentId;
  final String tournamentName;
  final int tournamentSortWeight;
  final int? sortYear;

  /// Show only the best placement when someone placed several times in one tournament.
  final bool showBestTiersOnly;
  final String? iconUrl;
  final int? seriesId;
  final String? seriesName;
  final int seriesSortWeight;

  /// Tournament pack (opened on the packs page).
  final String? packRef;
  final String? teamName;
  final int? levelId;
  final String? levelName;

  /// A placement that isn't pending, withdrawn, disqualified or hidden.
  final bool isPublic;
}

/// Profile module layout from the website. Falls back to the default order without a saved layout.
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

  /// Layout saved by the user, or null for the default.
  final List<({String id, String type})>? stored;

  /// Favorites module id → its items.
  final Map<String, List<FavoriteItem>> favorites;

  static const playerStock = ['bio', 'tournaments', 'scoreBreakdown', 'difficulty', 'rankHistory', 'scores'];
  static const playerTypes = {...playerStock, 'favorite', 'keyboards'};
  static const creatorStock = ['bio', 'tournaments', 'difficulty', 'charts'];
  static const creatorTypes = {...creatorStock, 'favorite'};

  /// Module order to show. Required modules (passes for players, levels for creators) are appended if missing.
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

/// One item of a favorites module (pass, level, pack, player or creator).
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

/// One row of a player's pass list: the pass and its level. GET /v3/players/{id}/passes
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

  /// Hidden levels have their name and icon masked.
  final bool levelHidden;
  final int? playerId;
}

/// Pass list sort. Names match the API values.
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

/// One point of rank history. GET /v3/players/{id}/rank-history
class RankHistoryPoint {
  const RankHistoryPoint({required this.date, this.rankedRank, this.generalRank});

  factory RankHistoryPoint.fromJson(Map<String, dynamic> json) => RankHistoryPoint(
    // Only a date arrives (YYYY-MM-DD), so read it as a UTC day.
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

/// Whether the user is a TUF Stellar supporter. Only supporters get animated avatars, custom banners and block bios.
bool isStellarActive(Map<String, dynamic>? user) {
  if (user == null) return false;
  final expires = DateTime.tryParse(asStringOrNull(user['tufStellarSubscriptionExpiresAt']) ?? '');
  if (expires != null && expires.isAfter(DateTime.now())) return true;
  // Super admins always have it (permission bit 62).
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

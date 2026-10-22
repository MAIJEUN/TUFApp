import '../json.dart';
import 'difficulty.dart';

/// TUF 레벨. API 응답에는 훨씬 많은 필드가 있지만 필요한 것만 읽는다.
class Level {
  const Level({
    required this.id,
    required this.song,
    required this.artist,
    this.creator,
    this.team,
    this.diffId = 0,
    this.difficulty,
    this.baseScore,
    this.dlLink,
    this.fileId,
    this.legacyDllink,
    this.workshopLink,
    this.videoLink,
    this.bpm,
    this.tilecount,
    this.levelLengthInMs,
    this.clears = 0,
    this.uniqueClears = 0,
    this.likes = 0,
    this.downloadCount = 0,
    this.isDeleted = false,
    this.tags = const [],
    this.credits = const [],
    this.curationTypeIds = const [],
    this.ratedDifficultyId,
    this.aliases = const [],
    this.createdAt,
  });

  factory Level.fromJson(Map<String, dynamic> json) {
    final difficulty = json['difficulty'];
    return Level(
      id: asInt(json['id']),
      song: json['song'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      creator: asStringOrNull(json['creator']),
      // 자세히 보기 응답에는 team이 비어 있고 팀 정보(teamObject)만 온다.
      team:
          asStringOrNull(json['team']) ??
          switch (json['teamObject']) {
            final Map<String, dynamic> team => asStringOrNull(team['name']),
            _ => null,
          },
      diffId: asInt(json['diffId']),
      difficulty: difficulty is Map<String, dynamic> ? Difficulty.fromJson(difficulty) : null,
      baseScore: asIntOrNull(json['baseScore']),
      dlLink: asStringOrNull(json['dlLink']),
      fileId: asStringOrNull(json['fileId']),
      legacyDllink: asStringOrNull(json['legacyDllink']),
      workshopLink: asStringOrNull(json['workshopLink']),
      videoLink: asStringOrNull(json['videoLink']),
      bpm: asDoubleOrNull(json['bpm']),
      tilecount: asIntOrNull(json['tilecount']),
      levelLengthInMs: asDoubleOrNull(json['levelLengthInMs']),
      clears: asInt(json['clears']),
      uniqueClears: asInt(json['uniqueClears']),
      likes: asInt(json['likes']),
      downloadCount: asInt(json['downloadCount']),
      isDeleted: asBool(json['isDeleted']),
      tags: asObjectList(json['tags']).map(LevelTag.fromJson).toList(),
      credits: asObjectList(json['levelCredits']).map(LevelCredit.fromJson).toList(),
      curationTypeIds: _readCurationTypeIds(json),
      aliases: asObjectList(json['aliases']).map(LevelAlias.fromJson).toList(),
      createdAt: DateTime.tryParse(asStringOrNull(json['createdAt']) ?? ''),
      ratedDifficultyId: switch (json['rating']) {
        final Map<String, dynamic> rating => asIntOrNull(rating['averageDifficultyId']),
        _ => null,
      },
    );
  }

  final int id;
  final String song;
  final String artist;

  /// 검색 결과에서 "차터 | VFX" 형태로 합쳐진 제작자 문자열.
  final String? creator;
  final String? team;
  final int diffId;
  final Difficulty? difficulty;

  /// 이 레벨에만 따로 정해진 기반 점수(PP). 난이도의 기본값을 대신한다.
  final int? baseScore;

  /// TUF CDN 다운로드 링크 (zip). 없으면 창작마당이나 예전 링크를 확인한다.
  final String? dlLink;

  /// CDN 파일 ID. 레벨 파일이 다시 올라가면 바뀌므로 업데이트 확인에 쓴다.
  final String? fileId;
  final String? legacyDllink;
  final String? workshopLink;
  final String? videoLink;

  final double? bpm;
  final int? tilecount;
  final double? levelLengthInMs;

  final int clears;
  final int uniqueClears;
  final int likes;

  /// 사이트에서 받은 횟수.
  final int downloadCount;
  final bool isDeleted;

  final List<LevelTag> tags;
  final List<LevelCredit> credits;

  /// 이 레벨에 매겨진 큐레이션 유형 id (C2, V1 등). 아이콘은 큐레이션 목록에서 찾는다.
  final List<int> curationTypeIds;

  /// 평가에서 매겨진 예상 난이도 id (평균). Q 레벨이 어느 PGU 난이도쯤인지 보여줄 때 쓴다.
  final int? ratedDifficultyId;

  /// 곡이나 작곡가를 부르는 다른 이름들 (검색에 쓰인다).
  final List<LevelAlias> aliases;

  /// TUF에 등록된 날짜.
  final DateTime? createdAt;

  /// 응답마다 모양이 다르다.
  /// - 검색 결과: curation.typeIds
  /// - 단일 레벨: curations[].types[].id
  /// - 팩 내용: curations[].typeIds
  static List<int> _readCurationTypeIds(Map<String, dynamic> json) {
    final ids = <int>{};

    void addTypeIds(Object? curation) {
      if (curation is! Map<String, dynamic> || curation['typeIds'] is! List) return;
      for (final id in curation['typeIds'] as List) {
        if (asIntOrNull(id) case final value?) ids.add(value);
      }
    }

    addTypeIds(json['curation']);
    addTypeIds(json['curations']);
    for (final entry in asObjectList(json['curations'])) {
      addTypeIds(entry);
      for (final type in asObjectList(entry['types'])) {
        if (asIntOrNull(type['id']) case final value?) ids.add(value);
      }
    }

    return ids.toList();
  }

  /// 팩 응답처럼 난이도·태그가 id로만 온 레벨을 목록에서 찾은 값으로 채울 때 쓴다.
  Level copyWith({Difficulty? difficulty, List<LevelTag>? tags}) => Level(
    id: id,
    song: song,
    artist: artist,
    creator: creator,
    team: team,
    diffId: diffId,
    difficulty: difficulty ?? this.difficulty,
    baseScore: baseScore,
    dlLink: dlLink,
    fileId: fileId,
    legacyDllink: legacyDllink,
    workshopLink: workshopLink,
    videoLink: videoLink,
    bpm: bpm,
    tilecount: tilecount,
    levelLengthInMs: levelLengthInMs,
    clears: clears,
    uniqueClears: uniqueClears,
    likes: likes,
    downloadCount: downloadCount,
    isDeleted: isDeleted,
    tags: tags ?? this.tags,
    credits: credits,
    curationTypeIds: curationTypeIds,
    ratedDifficultyId: ratedDifficultyId,
    aliases: aliases,
    createdAt: createdAt,
  );

  /// 난이도의 기본값과 다르게 정해진 기반 점수(PP). 변동이 없으면 null.
  int? get baseScoreOverride {
    final score = baseScore;
    if (score == null || score <= 0) return null;
    return score == difficulty?.baseScore ? null : score;
  }

  /// 레벨 길이. 정보가 없으면 null.
  Duration? get length {
    final ms = levelLengthInMs;
    return ms != null && ms > 0 ? Duration(milliseconds: ms.round()) : null;
  }

  /// 표시용 제작자 이름. 웹 프론트엔드의 formatCreatorDisplay와 같은 규칙:
  /// 팀 → 차터/VFX 크레딧 ("A & B", "A | B", "A & 2 more | B") → 검색 결과의 creator 문자열.
  String? get creatorDisplay {
    if (team != null) return team;

    final sorted = [...credits]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    List<String> namesFor(String role) =>
        sorted.where((c) => c.role?.toLowerCase() == role).map((c) => c.creatorName).whereType<String>().toList();

    final charters = namesFor('charter');
    final vfxers = namesFor('vfxer');
    final primaryCount = charters.length + vfxers.length;

    if (primaryCount >= 3) {
      return [
        if (charters.isNotEmpty) charters.length == 1 ? charters[0] : '${charters[0]} & ${charters.length - 1} more',
        if (vfxers.isNotEmpty) vfxers.length == 1 ? vfxers[0] : '${vfxers[0]} & ${vfxers.length - 1} more',
      ].join(' | ');
    }

    if (primaryCount == 2) {
      if (charters.length == 2) return '${charters[0]} & ${charters[1]}';
      if (charters.length == 1 && vfxers.length == 1) return '${charters[0]} | ${vfxers[0]}';
    }

    if (charters.isNotEmpty) return charters.first;
    if (vfxers.isNotEmpty) return vfxers.first;
    return creator;
  }
}

/// 곡·작곡가를 부르는 다른 이름. 예: field "artist", alias "cametek".
class LevelAlias {
  const LevelAlias({required this.field, required this.alias});

  factory LevelAlias.fromJson(Map<String, dynamic> json) =>
      LevelAlias(field: asStringOrNull(json['field']) ?? '', alias: asStringOrNull(json['alias']) ?? '');

  final String field;
  final String alias;
}

class LevelTag {
  const LevelTag({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.description,
    this.isCommunity = false,
    this.score,
  });

  factory LevelTag.fromJson(Map<String, dynamic> json) => LevelTag(
    id: asInt(json['id']),
    name: json['name'] as String? ?? '',
    icon: asStringOrNull(json['icon']),
    color: asStringOrNull(json['color']),
    description: asStringOrNull(json['description']),
    isCommunity: json['isCommunity'] == true,
    score: asDoubleOrNull(json['score']),
  );

  final int id;
  final String name;
  final String? icon;
  final String? color;
  final String? description;

  /// 플레이어들이 투표로 붙인 태그인지 (웹의 커뮤니티 태그). 관리자가 붙인 태그는 false.
  final bool isCommunity;

  /// 커뮤니티 태그의 신뢰도 (0~1). 웹은 이만큼 태그 둘레에 초록 테를 채운다.
  final double? score;

  /// 다른 정보(이름, 아이콘)로 바꾸되 투표 정보는 그대로 둔다.
  LevelTag withInfo({required String name, String? icon, String? color, String? description}) => LevelTag(
    id: id,
    name: name,
    icon: icon,
    color: color,
    description: description ?? this.description,
    isCommunity: isCommunity,
    score: score,
  );
}

class LevelCredit {
  const LevelCredit({this.role, this.sortOrder = 0, this.creatorId, this.creatorName, this.creatorAliases = const []});

  factory LevelCredit.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'];
    return LevelCredit(
      role: asStringOrNull(json['role']),
      sortOrder: asInt(json['sortOrder']),
      creatorId:
          asIntOrNull(json['creatorId']) ?? (creator is Map<String, dynamic> ? asIntOrNull(creator['id']) : null),
      creatorName: creator is Map<String, dynamic> ? asStringOrNull(creator['name']) : null,
      creatorAliases: creator is Map<String, dynamic>
          ? [for (final alias in asObjectList(creator['creatorAliases'])) ?asStringOrNull(alias['name'])]
          : const [],
    );
  }

  /// 예: "charter", "vfxer"
  final String? role;
  final int sortOrder;

  /// 제작자 페이지를 열 때 쓴다. 검색 결과에는 없을 수 있다.
  final int? creatorId;
  final String? creatorName;

  /// 그 사람이 쓰는 다른 이름들.
  final List<String> creatorAliases;
}

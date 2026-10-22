import '../json.dart';
import '../l10n.dart';
import 'level.dart';

/// 커뮤니티 레벨 팩 (목록 한 칸).
/// GET /v2/database/levels/packs 의 packs[] 항목.
class LevelPack {
  const LevelPack({
    required this.id,
    required this.name,
    this.description,
    this.iconUrl,
    this.levelCount = 0,
    this.favoritesCount = 0,
    this.isPinned = false,
    this.owner,
    this.preview = const [],
  });

  factory LevelPack.fromJson(Map<String, dynamic> json) {
    final owner = json['packOwner'];
    return LevelPack(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      description: asStringOrNull(json['description']),
      iconUrl: asStringOrNull(json['iconUrl']),
      levelCount: asInt(json['levelCount']),
      favoritesCount: asInt(json['favoritesCount']),
      isPinned: asBool(json['isPinned']),
      owner: owner is Map<String, dynamic> ? PackOwner.fromJson(owner) : null,
      preview: [
        for (final item in asObjectList(json['packItems']))
          if (item['referencedLevel'] case final Map<String, dynamic> level) PackPreviewLevel.fromJson(level),
      ],
    );
  }

  /// 예: "HXvV76zK". 웹 주소(/packs/{id})에도 그대로 쓴다.
  final String id;
  final String name;
  final String? description;
  final String? iconUrl;
  final int levelCount;
  final int favoritesCount;

  /// 운영진이 고정한 팩 (공식 팩 등).
  final bool isPinned;
  final PackOwner? owner;

  /// 목록 카드에 미리 보여줄 앞쪽 레벨 몇 개.
  final List<PackPreviewLevel> preview;

  String get webUrl => 'https://tuforums.com/packs/$id';
}

class PackOwner {
  const PackOwner({required this.name, this.avatarUrl});

  factory PackOwner.fromJson(Map<String, dynamic> json) => PackOwner(
    name: asStringOrNull(json['nickname']) ?? asStringOrNull(json['username']) ?? '',
    avatarUrl: asStringOrNull(json['avatarUrl']),
  );

  final String name;
  final String? avatarUrl;
}

/// 목록 카드 미리보기용 레벨 (id, 곡 이름, 난이도 id만 온다).
class PackPreviewLevel {
  const PackPreviewLevel({required this.id, required this.song, required this.diffId});

  factory PackPreviewLevel.fromJson(Map<String, dynamic> json) =>
      PackPreviewLevel(id: asInt(json['id']), song: json['song'] as String? ?? '', diffId: asInt(json['diffId']));

  final int id;
  final String song;
  final int diffId;
}

/// 팩 안의 항목: 폴더이거나 레벨이다.
sealed class PackNode {
  const PackNode({required this.id});

  final int id;
}

class PackFolder extends PackNode {
  const PackFolder({required super.id, required this.name, this.children = const []});

  final String name;
  final List<PackNode> children;

  /// 이 폴더 아래(하위 폴더 포함)의 모든 레벨.
  Iterable<PackLevelEntry> get allLevels => packLevelsIn(children);
}

class PackLevelEntry extends PackNode {
  const PackLevelEntry({required super.id, required this.level});

  final Level level;
}

/// 여러 항목 아래의 모든 레벨을 순서대로.
Iterable<PackLevelEntry> packLevelsIn(List<PackNode> nodes) sync* {
  for (final node in nodes) {
    switch (node) {
      case PackLevelEntry():
        yield node;
      case PackFolder():
        yield* node.allLevels;
    }
  }
}

/// 팩 상세 (폴더 구조 포함). GET /v2/database/levels/packs/{id}?tree=true
class LevelPackDetail {
  const LevelPackDetail({required this.pack, required this.items});

  /// [resolveLevel]은 팩 응답의 간단한 레벨(난이도·태그가 id뿐)을 카드에 보여줄 수 있게 채운다.
  factory LevelPackDetail.fromJson(Map<String, dynamic> json, {Level Function(Level level)? resolveLevel}) {
    List<PackNode> parse(List<Map<String, dynamic>> items) {
      final sorted = [...items]..sort((a, b) => asInt(a['sortOrder']).compareTo(asInt(b['sortOrder'])));
      return [
        for (final item in sorted)
          if (item['type'] == 'folder')
            PackFolder(
              id: asInt(item['id']),
              name: item['name'] as String? ?? '',
              children: parse(asObjectList(item['children'])),
            )
          else if (item['referencedLevel'] case final Map<String, dynamic> level)
            PackLevelEntry(id: asInt(item['id']), level: (resolveLevel ?? (level) => level)(Level.fromJson(level))),
      ];
    }

    return LevelPackDetail(pack: LevelPack.fromJson(json), items: parse(asObjectList(json['items'])));
  }

  final LevelPack pack;
  final List<PackNode> items;

  Iterable<PackLevelEntry> get allLevels => packLevelsIn(items);
}

enum PackSort {
  recent('RECENT', '최신', 'Recent'),
  name('NAME', '이름', 'Name'),
  levels('LEVELS', '레벨 수', 'Level Count'),
  favorites('FAVORITES', '좋아요 수', 'Favorites');

  const PackSort(this.apiValue, this._ko, this._en);

  final String apiValue;
  final String _ko;
  final String _en;
  String get label => tr(_ko, _en);
}

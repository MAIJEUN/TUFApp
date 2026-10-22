import '../json.dart';
import '../l10n.dart';
import 'level.dart';

/// A community level pack (one list card).
/// An item of packs[] from GET /v2/database/levels/packs.
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

  /// e.g. "HXvV76zK", also used in the website URL (/packs/{id}).
  final String id;
  final String name;
  final String? description;
  final String? iconUrl;
  final int levelCount;
  final int favoritesCount;

  /// Pinned by staff (official packs etc.).
  final bool isPinned;
  final PackOwner? owner;

  /// The first few levels previewed on the list card.
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

/// Level preview for a list card (only id, song and difficulty id).
class PackPreviewLevel {
  const PackPreviewLevel({required this.id, required this.song, required this.diffId});

  factory PackPreviewLevel.fromJson(Map<String, dynamic> json) =>
      PackPreviewLevel(id: asInt(json['id']), song: json['song'] as String? ?? '', diffId: asInt(json['diffId']));

  final int id;
  final String song;
  final int diffId;
}

/// An item in a pack: a folder or a level.
sealed class PackNode {
  const PackNode({required this.id});

  final int id;
}

class PackFolder extends PackNode {
  const PackFolder({required super.id, required this.name, this.children = const []});

  final String name;
  final List<PackNode> children;

  /// Every level under this folder, including subfolders.
  Iterable<PackLevelEntry> get allLevels => packLevelsIn(children);
}

class PackLevelEntry extends PackNode {
  const PackLevelEntry({required super.id, required this.level});

  final Level level;
}

/// Every level under the given items, in order.
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

/// Pack details with folder structure. GET /v2/database/levels/packs/{id}?tree=true
class LevelPackDetail {
  const LevelPackDetail({required this.pack, required this.items});

  /// [resolveLevel] fills in the pack's bare levels (difficulty and tags as ids only) so cards can show them.
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

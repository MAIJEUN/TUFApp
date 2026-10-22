import 'dart:convert';

import '../json.dart';
import '../l10n.dart';

/// A tag or curation type. Both lists share the same response shape.
/// GET /v2/database/difficulties/tags, GET /v2/admin/curations/types
class FacetItem {
  const FacetItem({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.group,
    this.groupSortOrder = 0,
    this.sortOrder = 0,
  });

  factory FacetItem.fromJson(Map<String, dynamic> json) => FacetItem(
    id: asInt(json['id']),
    name: json['name'] as String? ?? '',
    icon: asStringOrNull(json['icon']),
    color: asStringOrNull(json['color']),
    group: asStringOrNull(json['group']),
    groupSortOrder: asInt(json['groupSortOrder']),
    sortOrder: asInt(json['sortOrder']),
  );

  final int id;
  final String name;
  final String? icon;
  final String? color;

  /// e.g. "Play Style", "Key Limit", "Chart". Items without one go under "Other".
  final String? group;
  final int groupSortOrder;
  final int sortOrder;
}

/// Curation types not drawn around difficulty icons.
/// Matches the website's HIDDEN_CURATION_ARC_TYPE_NAMES: only C0 and V0 are hidden (names like O0 still show).
const hiddenCurationArcTypeNames = {'C0', 'V0'};

bool isHiddenCurationArcType(FacetItem item) => hiddenCurationArcTypeNames.contains(item.name);

/// Items of one group.
class FacetGroup {
  const FacetGroup(this.name, this.items);

  /// Group name from the server; null for items without a group.
  final String? name;
  final List<FacetItem> items;

  /// Resolved when shown, so it follows language changes.
  String get title => name ?? tr('기타', 'Other');
}

/// Tags or curation types arranged in group order.
class FacetCatalog {
  FacetCatalog(List<FacetItem> items)
    : all = List.unmodifiable(items),
      groups = _group(items),
      _byId = {for (final item in items) item.id: item};

  final List<FacetItem> all;
  final List<FacetGroup> groups;
  final Map<int, FacetItem> _byId;

  FacetItem? byId(int id) => _byId[id];

  /// Returns the given ids in group and sort order, skipping unknown ids.
  List<FacetItem> resolve(Iterable<int> ids) {
    final items = [for (final id in ids) ?_byId[id]];
    items.sort((a, b) {
      final byGroup = a.groupSortOrder.compareTo(b.groupSortOrder);
      return byGroup != 0 ? byGroup : a.sortOrder.compareTo(b.sortOrder);
    });
    return items;
  }

  static List<FacetGroup> _group(List<FacetItem> items) {
    // Items without a group go last, under "Other".
    int groupRank(FacetItem item) => item.group == null ? 1 << 30 : item.groupSortOrder;

    final sorted = [...items]
      ..sort((a, b) {
        final byGroup = groupRank(a).compareTo(groupRank(b));
        if (byGroup != 0) return byGroup;
        final byName = (a.group ?? '').compareTo(b.group ?? '');
        if (byName != 0) return byName;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    final groups = <String?, List<FacetItem>>{};
    for (final item in sorted) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }
    return [for (final entry in groups.entries) FacetGroup(entry.key, List.unmodifiable(entry.value))];
  }
}

/// Selected tags (or curation types). [matchAll] finds levels with all of them, otherwise levels with any.
class FacetSelection {
  const FacetSelection({this.ids = const {}, this.matchAll = false});

  final Set<int> ids;
  final bool matchAll;

  bool get isEmpty => ids.isEmpty;

  /// The server's format: {"mode":"simple","op":"and|or","ids":[...]}
  Map<String, Object?> toJson() => {'mode': 'simple', 'op': matchAll ? 'and' : 'or', 'ids': ids.toList()..sort()};
}

/// facetQuery (v1) value combining tags and curation types.
/// When both are set, levels must match both. null if nothing is selected.
String? buildFacetQuery({FacetSelection? tags, FacetSelection? curationTypes}) {
  final hasTags = tags != null && !tags.isEmpty;
  final hasCurations = curationTypes != null && !curationTypes.isEmpty;
  if (!hasTags && !hasCurations) return null;

  return jsonEncode({
    'v': 1,
    if (hasTags) 'tags': tags.toJson(),
    if (hasCurations) 'curationTypes': curationTypes.toJson(),
    if (hasTags && hasCurations) 'combine': 'and',
  });
}

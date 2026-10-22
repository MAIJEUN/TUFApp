import 'dart:convert';

import '../json.dart';
import '../l10n.dart';

/// 태그나 큐레이션 유형 하나. 두 목록의 응답 모양이 같아서 함께 쓴다.
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

  /// 예: "Play Style", "Key Limit", "Chart". 없으면 '기타'로 묶는다.
  final String? group;
  final int groupSortOrder;
  final int sortOrder;
}

/// 난이도 아이콘 둘레에 표시하지 않는 큐레이션 유형.
/// 웹의 HIDDEN_CURATION_ARC_TYPE_NAMES와 같게 C0, V0 둘만 숨긴다 (O0 같은 이름은 그대로 보여준다).
const hiddenCurationArcTypeNames = {'C0', 'V0'};

bool isHiddenCurationArcType(FacetItem item) => hiddenCurationArcTypeNames.contains(item.name);

/// 한 묶음(그룹)의 항목들.
class FacetGroup {
  const FacetGroup(this.title, this.items);

  final String title;
  final List<FacetItem> items;
}

/// 태그/큐레이션 목록을 그룹 순서대로 정리해 둔다.
class FacetCatalog {
  FacetCatalog(List<FacetItem> items)
    : all = List.unmodifiable(items),
      groups = _group(items),
      _byId = {for (final item in items) item.id: item};

  final List<FacetItem> all;
  final List<FacetGroup> groups;
  final Map<int, FacetItem> _byId;

  FacetItem? byId(int id) => _byId[id];

  /// 주어진 id들을 그룹·정렬 순서대로 정리해 돌려준다. 모르는 id는 건너뛴다.
  List<FacetItem> resolve(Iterable<int> ids) {
    final items = [for (final id in ids) ?_byId[id]];
    items.sort((a, b) {
      final byGroup = a.groupSortOrder.compareTo(b.groupSortOrder);
      return byGroup != 0 ? byGroup : a.sortOrder.compareTo(b.sortOrder);
    });
    return items;
  }

  static List<FacetGroup> _group(List<FacetItem> items) {
    // 그룹이 없는 항목은 맨 뒤 '기타'로 모은다.
    int groupRank(FacetItem item) => item.group == null ? 1 << 30 : item.groupSortOrder;

    final sorted = [...items]
      ..sort((a, b) {
        final byGroup = groupRank(a).compareTo(groupRank(b));
        if (byGroup != 0) return byGroup;
        final byName = (a.group ?? '').compareTo(b.group ?? '');
        if (byName != 0) return byName;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    final groups = <String, List<FacetItem>>{};
    for (final item in sorted) {
      groups.putIfAbsent(item.group ?? tr('기타', 'Other'), () => []).add(item);
    }
    return [for (final entry in groups.entries) FacetGroup(entry.key, List.unmodifiable(entry.value))];
  }
}

/// 고른 태그(또는 큐레이션 유형)들. [matchAll]이면 모두 가진 레벨만, 아니면 하나라도 가진 레벨.
class FacetSelection {
  const FacetSelection({this.ids = const {}, this.matchAll = false});

  final Set<int> ids;
  final bool matchAll;

  bool get isEmpty => ids.isEmpty;

  /// 서버가 받는 모양: {"mode":"simple","op":"and|or","ids":[...]}
  Map<String, Object?> toJson() => {'mode': 'simple', 'op': matchAll ? 'and' : 'or', 'ids': ids.toList()..sort()};
}

/// 태그와 큐레이션 유형을 함께 보내는 facetQuery(v1) 값.
/// 둘 다 고르면 둘 다 만족하는 레벨만 찾는다. 아무것도 없으면 null.
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

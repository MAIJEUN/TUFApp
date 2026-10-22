import '../json.dart';

class Difficulty {
  const Difficulty({
    required this.id,
    required this.name,
    this.type,
    this.color,
    this.icon,
    this.sortOrder = 0,
    this.baseScore = 0,
  });

  factory Difficulty.fromJson(Map<String, dynamic> json) => Difficulty(
    id: asInt(json['id']),
    name: json['name'] as String? ?? '',
    type: asStringOrNull(json['type']),
    color: asStringOrNull(json['color']),
    icon: asStringOrNull(json['icon']),
    sortOrder: asInt(json['sortOrder']),
    baseScore: asInt(json['baseScore']),
  );

  final int id;

  /// 예: "U5", "GQ0 (G1~G4)", "Unranked"
  final String name;

  /// 예: "PGU", "SPECIAL", "LEGACY"
  final String? type;

  /// 예: "#613E8C"
  final String? color;
  final String? icon;
  final int sortOrder;

  /// 이 난이도의 기본 PP 점수. 0이면 정해진 값이 없다.
  final int baseScore;

  /// "GQ0 (G1~G4)" → "GQ0"
  String get shortName {
    final paren = name.indexOf(' (');
    return paren < 0 ? name : name.substring(0, paren);
  }
}

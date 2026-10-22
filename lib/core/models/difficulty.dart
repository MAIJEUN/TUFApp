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

  /// e.g. "U5", "GQ0 (G1~G4)", "Unranked"
  final String name;

  /// e.g. "PGU", "SPECIAL", "LEGACY"
  final String? type;

  /// e.g. "#613E8C"
  final String? color;
  final String? icon;
  final int sortOrder;

  /// Base PP score of this difficulty; 0 if none.
  final int baseScore;

  /// "GQ0 (G1~G4)" → "GQ0"
  String get shortName {
    final paren = name.indexOf(' (');
    return paren < 0 ? name : name.substring(0, paren);
  }
}

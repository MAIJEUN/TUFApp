// API 응답은 숫자가 문자열로 오거나 빈 문자열이 null 대신 오기도 해서, 읽을 때 한 번 정리한다.

int asInt(Object? value, [int fallback = 0]) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v) ?? fallback,
  _ => fallback,
};

int? asIntOrNull(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v),
  _ => null,
};

double? asDoubleOrNull(Object? value) => switch (value) {
  num v => v.toDouble(),
  String v => double.tryParse(v),
  _ => null,
};

/// 빈 문자열은 null로 본다 (예: workshopLink: "").
String? asStringOrNull(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

bool asBool(Object? value) => value == true;

List<Map<String, dynamic>> asObjectList(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

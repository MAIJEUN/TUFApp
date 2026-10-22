// API responses sometimes send numbers as strings or empty strings instead of null, so values are normalized when read.

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

/// Treats empty strings as null (e.g. workshopLink: "").
String? asStringOrNull(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

bool asBool(Object? value) => value == true;

List<Map<String, dynamic>> asObjectList(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

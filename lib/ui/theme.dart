import 'package:flutter/material.dart';

/// Material 3 dark theme seeded with the TUF purple.
ThemeData buildAppTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D70FF), brightness: Brightness.dark),
  // Same font as the website (bundled Roboto).
  fontFamily: 'Roboto',
  // Like the website, characters missing from Roboto (Korean/Chinese/Japanese song names, ...) use these system fonts
  // in order.
  fontFamilyFallback: const ['Malgun Gothic', 'Microsoft YaHei UI', 'Yu Gothic UI', 'Segoe UI'],
);

/// "#613E8C" → Color, or null if malformed.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim().replaceFirst('#', '');
  if (value.length == 3) value = value.split('').map((c) => '$c$c').join();
  if (value.length == 6) value = 'FF$value';
  if (value.length == 8 && hex.trim().length == 9) {
    // CSS #RRGGBBAA → AARRGGBB
    value = value.substring(6) + value.substring(0, 6);
  }
  final parsed = int.tryParse(value, radix: 16);
  return value.length == 8 && parsed != null ? Color(parsed) : null;
}

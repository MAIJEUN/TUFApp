import 'package:flutter/material.dart';

/// 기본 Material 3 테마. TUF 보라색을 시드 색으로 쓰고 어두운 모드로 만든다.
ThemeData buildAppTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D70FF), brightness: Brightness.dark),
  // 웹과 같은 글꼴 (앱에 함께 넣은 Roboto).
  fontFamily: 'Roboto',
  // 웹처럼 Roboto에 없는 글자(한국어/중국어/일본어 곡 이름 등)는 이 순서로 시스템 글꼴을 쓴다.
  fontFamilyFallback: const ['Malgun Gothic', 'Microsoft YaHei UI', 'Yu Gothic UI', 'Segoe UI'],
);

/// "#613E8C" → Color. 형식이 틀리면 null.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim().replaceFirst('#', '');
  if (value.length == 3) value = value.split('').map((c) => '$c$c').join();
  if (value.length == 6) value = 'FF$value';
  if (value.length == 8 && hex.trim().length == 9) {
    // CSS의 #RRGGBBAA → AARRGGBB
    value = value.substring(6) + value.substring(0, 6);
  }
  final parsed = int.tryParse(value, radix: 16);
  return value.length == 8 && parsed != null ? Color(parsed) : null;
}

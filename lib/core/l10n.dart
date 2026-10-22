import 'dart:ui' show PlatformDispatcher;

/// UI language.
enum AppLanguage {
  ko('ko', '한국어'),
  en('en', 'English');

  const AppLanguage(this.code, this.nativeName);

  /// Value stored in the settings file.
  final String code;

  /// Name shown in the language menu, always written in that language.
  final String nativeName;

  static AppLanguage? fromCode(Object? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// Korean if the system language is Korean, otherwise English.
  static AppLanguage get system => PlatformDispatcher.instance.locale.languageCode == 'ko' ? ko : en;
}

/// Current UI language. Change it through [AppController.setLanguage], which rebuilds the whole tree.
AppLanguage appLanguage = AppLanguage.ko;

/// Picks the Korean or English text for the current language.
String tr(String ko, String en) => appLanguage == AppLanguage.en ? en : ko;

/// English singular/plural: plural(1, 'level') → "level", plural(3, 'level') → "levels".
String plural(int count, String one, [String? many]) => count == 1 ? one : many ?? '${one}s';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 2026-05-05 → "2026년 5월 5일" / "May 5, 2026"
String formatLongDate(DateTime date) =>
    tr('${date.year}년 ${date.month}월 ${date.day}일', '${_months[date.month - 1]} ${date.day}, ${date.year}');

/// 2026-05-05 → "5월 5일" / "May 5"
String formatMonthDay(DateTime date) => tr('${date.month}월 ${date.day}일', '${_months[date.month - 1]} ${date.day}');

/// 2026-05 → "26년 5월" / "May '26"
String formatShortMonth(DateTime date) {
  final year = (date.year % 100).toString().padLeft(2, '0');
  return tr('$year년 ${date.month}월', "${_months[date.month - 1]} '$year");
}

import 'dart:ui' show PlatformDispatcher;

/// 화면에 쓰는 언어.
enum AppLanguage {
  ko('ko', '한국어'),
  en('en', 'English');

  const AppLanguage(this.code, this.nativeName);

  /// 설정 파일에 적는 값.
  final String code;

  /// 언어 고르기 메뉴에 보이는 이름 (언어와 상관없이 그 언어로 적는다).
  final String nativeName;

  static AppLanguage? fromCode(Object? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// 시스템 언어가 한국어면 한국어, 아니면 영어.
  static AppLanguage get system => PlatformDispatcher.instance.locale.languageCode == 'ko' ? ko : en;
}

/// 지금 화면 언어. 바꿀 때는 [AppController.setLanguage]를 쓴다 (화면 전체를 다시 그린다).
AppLanguage appLanguage = AppLanguage.ko;

/// 한국어 글과 영어 글 중 지금 언어의 것.
String tr(String ko, String en) => appLanguage == AppLanguage.en ? en : ko;

/// 영어 단어의 단수·복수: plural(1, 'level') → "level", plural(3, 'level') → "levels".
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

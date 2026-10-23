import 'dart:ui' show Locale, PlatformDispatcher;

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart' show AppLocalizations;

/// UI language. There is one per translation file in lib/l10n (app_<code>.arb); adding a file adds a language.
class AppLanguage {
  AppLanguage._(this.code) : strings = lookupAppLocalizations(Locale(code));

  /// Value stored in the settings file.
  final String code;

  /// Every UI text in this language.
  final AppLocalizations strings;

  /// Name shown in the language menu, always written in that language.
  String get nativeName => strings.languageName;

  static final List<AppLanguage> values = [
    for (final locale in AppLocalizations.supportedLocales) AppLanguage._(locale.languageCode),
  ];

  static final AppLanguage en = fromCode('en')!;
  static final AppLanguage ko = fromCode('ko')!;

  static AppLanguage? fromCode(Object? code) => values.where((language) => language.code == code).firstOrNull;

  /// The system language if there is a translation for it, otherwise English.
  static AppLanguage get system => fromCode(PlatformDispatcher.instance.locale.languageCode) ?? en;

  @override
  String toString() => code;
}

/// Current UI language. Change it through [AppController.setLanguage], which rebuilds the whole tree.
AppLanguage appLanguage = AppLanguage.ko;

/// UI text in the current language, e.g. `l10n.retry`. Messages live in lib/l10n/app_<code>.arb.
AppLocalizations get l10n => appLanguage.strings;

List<String> _monthNames() => l10n.monthNames.split('|');

/// 2026-05-05 → "2026년 5월 5일" / "May 5, 2026"
String formatLongDate(DateTime date) => l10n.longDate(date.year, date.month, _monthNames()[date.month - 1], date.day);

/// 2026-05-05 → "5월 5일" / "May 5"
String formatMonthDay(DateTime date) => l10n.monthDay(date.month, _monthNames()[date.month - 1], date.day);

/// 2026-05 → "26년 5월" / "May '26"
String formatShortMonth(DateTime date) {
  final year = (date.year % 100).toString().padLeft(2, '0');
  return l10n.shortMonth(year, date.month, _monthNames()[date.month - 1]);
}

import 'dart:math';

import 'json.dart';
import 'l10n.dart';
import 'models/difficulty.dart';
import 'models/facet.dart';
import 'models/pass.dart';
import 'models/profile.dart';
import 'models/search_models.dart';

/// Values shown in profile headers and modules. Same rules as the website (utils/profileStatGroups.js,
/// profileIconSlots.js).

/// One stat line. With [passId], a button links to that pass.
class StatRow {
  const StatRow(this.label, this.value, {this.tooltip, this.passId});

  final String label;
  final String value;
  final String? tooltip;
  final int? passId;
}

class StatGroup {
  const StatGroup(this.label, this.rows);

  final String label;
  final List<StatRow> rows;
}

/// One icon slot in a profile header (top difficulty, curation type, etc.).
class IconSlot {
  const IconSlot({required this.letter, this.iconUrl, this.badge = 0, this.tooltip});

  /// Text shown when there is no icon (P, G, GQ, ...).
  final String letter;
  final String? iconUrl;
  final int badge;
  final String? tooltip;
}

// ───────────────────────── Number formatting ─────────────────────────

String formatCount(Object? value) => _group(asDoubleOrNull(value)?.truncate() ?? 0);

String formatFixed(Object? value, int digits) => (asDoubleOrNull(value) ?? 0).toStringAsFixed(digits);

/// Two decimals with thousands separators, e.g. 460,778.52
String formatPoints(Object? value) {
  final number = asDoubleOrNull(value) ?? 0;
  final fixed = number.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  return '${number < 0 ? '-' : ''}${_group(int.parse(fixed.substring(0, dot)))}${fixed.substring(dot)}';
}

String _group(int value) => value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');

/// Accuracy (0–1) as a percentage. Values very close to 100% keep their nines (like 99.9996%), as on the website.
String formatAccuracyRatio(Object? value, {int minDecimals = 2}) {
  final ratio = asDoubleOrNull(value);
  if (ratio == null) return '0%';
  if (ratio >= 1) return '100%';
  if (ratio <= 0) return '${0.toStringAsFixed(minDecimals)}%';

  final fixed = (ratio * 100).toStringAsFixed(12);
  final parts = fixed.split('.');
  final integer = parts[0];
  final decimals = parts.length > 1 ? parts[1] : '';
  if ((int.tryParse(integer) ?? 0) >= 100) return '100%';

  var nines = 0;
  if (integer == '99') {
    while (nines < decimals.length && decimals[nines] == '9') {
      nines++;
    }
  }
  final rounded = (ratio * 100).toStringAsFixed(minDecimals);
  final nearPerfect = (double.tryParse(rounded) ?? 0) >= 100 || (integer == '99' && nines >= minDecimals);
  if (nearPerfect) {
    final keep = min(12, max(minDecimals, nines + 1));
    return '$integer.${decimals.substring(0, keep).padRight(keep, '0')}%';
  }
  return '$rounded%';
}

/// Milliseconds → "1h 23m", "4m 5s", "12.3 s"
String formatDurationMs(Object? value) {
  final ms = asDoubleOrNull(value) ?? 0;
  if (ms <= 0) return '0';
  final seconds = ms / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)} s';
  final minutes = seconds ~/ 60;
  final rest = seconds - minutes * 60;
  if (minutes < 60) return '${minutes}m ${rest.round()}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String formatStatDate(Object? value) {
  final date = DateTime.tryParse(asStringOrNull(value) ?? '')?.toLocal();
  if (date == null) return '—';
  return formatLongDate(date);
}

// ───────────────────────── Stat groups ─────────────────────────

Map<String, dynamic> _section(Map<String, dynamic> facts, String key) =>
    facts[key] is Map<String, dynamic> ? facts[key] as Map<String, dynamic> : const {};

/// Splits clear counts into P/G/U/special (only difficulties named like P1 or G12 count as PGU).
Map<String, int> bucketByDifficultyName(Map<String, dynamic>? counts, DifficultyCatalog? catalog) {
  final buckets = {'PLANETARY': 0, 'GALACTIC': 0, 'UNIVERSAL': 0, 'SPECIAL': 0};
  for (final entry in (counts ?? const {}).entries) {
    final count = asInt(entry.value);
    if (count <= 0) continue;
    final name = catalog?.byId(int.tryParse(entry.key))?.name;
    final match = name == null ? null : RegExp(r'^([PGU])(\d+)$', caseSensitive: false).firstMatch(name.trim());
    final bucket = switch (match?.group(1)?.toUpperCase()) {
      'P' => 'PLANETARY',
      'G' => 'GALACTIC',
      'U' => 'UNIVERSAL',
      _ => 'SPECIAL',
    };
    buckets[bucket] = buckets[bucket]! + count;
  }
  return buckets;
}

/// Stat groups shown when a player header is expanded.
List<StatGroup> playerStatGroups(PlayerProfileDetail player, DifficultyCatalog? catalog) {
  final facts = player.funFacts;
  if (facts.isEmpty) return const [];
  final counts = _section(facts, 'counts');
  final judgements = _section(facts, 'judgements');
  final cleared = _section(facts, 'levelsCleared');
  final extremes = _section(facts, 'extremes');
  final activity = _section(facts, 'activity');
  final total = bucketByDifficultyName(_section(facts, 'clearsByDifficulty'), catalog);
  final unique = bucketByDifficultyName(
    facts['clearsByDifficultyNoDupes'] is Map<String, dynamic>
        ? facts['clearsByDifficultyNoDupes'] as Map<String, dynamic>
        : _section(facts, 'clearsByDifficulty'),
    catalog,
  );

  StatRow extreme(String label, String key, String Function(Object? value) format) => StatRow(
    label,
    extremes[key] == null ? '—' : format(extremes[key]),
    passId: asIntOrNull(extremes['${key}PassId']),
  );

  return [
    StatGroup(l10n.scores, [
      for (final key in [
        PlayerScoreKey.rankedScore,
        PlayerScoreKey.totalScoreV2,
        PlayerScoreKey.ppScore,
        PlayerScoreKey.wfScore,
        PlayerScoreKey.wfPPScore,
        PlayerScoreKey.score12K,
      ])
        if (player.scores.containsKey(key)) StatRow(key.label, formatPoints(player.score(key))),
      StatRow(PlayerScoreKey.averageXacc.label, formatAccuracyRatio(player.score(PlayerScoreKey.averageXacc))),
    ]),
    StatGroup(l10n.passCounts, [
      StatRow(l10n.totalPasses, formatCount(counts['totalPasses'])),
      StatRow(l10n.uniqueLevelsCleared, formatCount(counts['uniqueLevelsCleared'])),
      StatRow(l10n.worldsFirstClears, formatCount(counts['worldsFirstCount'])),
      StatRow(l10n.worldsFirstPPClears, formatCount(counts['worldsFirstPPCount'])),
      StatRow(l10n.clears12k, formatCount(counts['clears12K'])),
      StatRow(l10n.clears16k, formatCount(counts['clears16K'])),
      StatRow(l10n.totalPurePerfects, formatCount(counts['totalPurePerfectClears'])),
      StatRow(l10n.reclears, formatCount(counts['duplicatePasses'])),
    ]),
    StatGroup(l10n.judgements, [
      StatRow(l10n.totalTilesHit, formatCount(judgements['totalTilesHit'])),
      StatRow(Judgement.tooEarly.label, formatCount(judgements['earlyDouble'])),
      StatRow(Judgement.early.label, formatCount(judgements['earlySingle'])),
      StatRow(Judgement.earlyPerfect.label, formatCount(judgements['ePerfect'])),
      StatRow(Judgement.perfect.label, formatCount(judgements['perfect'])),
      StatRow(Judgement.latePerfect.label, formatCount(judgements['lPerfect'])),
      StatRow(Judgement.late.label, formatCount(judgements['lateSingle'])),
      StatRow(l10n.generalAccuracy, _xaccOf(judgements)),
      StatRow(l10n.earlyVsLateBias, formatFixed(judgements['earlyVsLateBias'], 4)),
    ]),
    StatGroup(l10n.levelsCleared, [
      StatRow(l10n.totalTilecountCleared, formatCount(cleared['totalTilecountCleared'])),
      StatRow(l10n.estimatedPlaytime, formatDurationMs(cleared['totalPlaytimeMs'])),
      StatRow(l10n.avgBPMClearedLevels, formatFixed(cleared['averageBpm'], 2)),
      StatRow(l10n.rawSumOfAll, formatPoints(cleared['totalRawScoreV2'])),
    ]),
    StatGroup(l10n.records, [
      extreme(l10n.firstPass, 'firstPassAt', formatStatDate),
      extreme(l10n.latestPass, 'latestPassAt', formatStatDate),
      extreme(l10n.bestAccuracy, 'bestAccuracy', formatAccuracyRatio),
      extreme(l10n.worstAccuracy, 'worstAccuracy', formatAccuracyRatio),
      extreme(l10n.topSpeed, 'topSpeed', (value) => _trimNumber(asDoubleOrNull(value) ?? 0, 3)),
      extreme(l10n.highestTilecount, 'highestTilecountCleared', formatCount),
      extreme(l10n.longestLevel, 'longestLevelMs', formatDurationMs),
      extreme(l10n.highestBPMCleared, 'highestBpmCleared', (value) => formatFixed(value, 2)),
    ]),
    StatGroup(l10n.activity, [
      StatRow(l10n.accountAgeDays, formatCount(activity['accountAgeDays'])),
      StatRow(l10n.passesLast30Days, formatCount(activity['passesLast30Days'])),
      StatRow(l10n.levelsLiked, formatCount(activity['uniqueLevelsLiked'])),
      StatRow(l10n.packsOwned, formatCount(activity['packsOwned'])),
      StatRow(l10n.packsFavorited, formatCount(activity['packsFavorited'])),
    ]),
    StatGroup(l10n.clearsByDifficultyType, [
      for (final bucket in const ['PLANETARY', 'GALACTIC', 'UNIVERSAL', 'SPECIAL'])
        StatRow(
          bucket,
          total[bucket]! > unique[bucket]!
              ? '${formatCount(unique[bucket])} (${formatCount(total[bucket])})'
              : formatCount(unique[bucket]),
          tooltip: total[bucket]! > unique[bucket]!
              ? l10n.uniqueLevelsClearedTotal(unique[bucket]!, total[bucket]!)
              : l10n.uniqueLevelsClearedCount(unique[bucket]!),
        ),
    ]),
  ];
}

/// Accuracy from judgement totals (same weights as the website's calcAcc).
String _xaccOf(Map<String, dynamic> j) {
  final ed = asInt(j['earlyDouble']);
  final es = asInt(j['earlySingle']);
  final ep = asInt(j['ePerfect']);
  final p = asInt(j['perfect']) + asInt(j['perfectMinus']) + asInt(j['perfectPlus']);
  final lp = asInt(j['lPerfect']);
  final ls = asInt(j['lateSingle']);
  final ld = asInt(j['lateDouble']);
  final total = ed + es + ep + p + lp + ls + ld;
  if (total <= 0) return '—';
  return formatAccuracyRatio((p + (ep + lp) * 0.75 + (es + ls) * 0.4 + (ed + ld) * 0.2) / total);
}

String _trimNumber(double value, int digits) {
  final text = value.toStringAsFixed(digits);
  return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
}

/// Stat groups shown when a creator header is expanded.
List<StatGroup> creatorStatGroups(CreatorProfileDetail creator, DifficultyCatalog? catalog) {
  final facts = creator.funFacts;
  if (facts.isEmpty) return const [];
  final identity = _section(facts, 'identity');
  final credits = _section(facts, 'credits');
  final content = _section(facts, 'content');
  final audience = _section(facts, 'audience');
  final timeline = _section(facts, 'timeline');
  final byType = bucketByDifficultyName(_section(facts, 'levelsByDifficulty'), catalog);

  return [
    StatGroup(l10n.identity, [
      StatRow(l10n.aliases, formatCount(identity['aliasCount'])),
      StatRow(l10n.teamsJoined, formatCount(identity['teamsJoined'])),
    ]),
    StatGroup(l10n.credits, [
      StatRow(l10n.levelsAsCharter, formatCount(credits['levelsAsCharter'])),
      StatRow(l10n.levelsAsVFX, formatCount(credits['levelsAsVfxer'])),
    ]),
    StatGroup(l10n.chartContent, [
      StatRow(l10n.tilesPlaced, formatCount(content['totalTilesMade'])),
      StatRow(l10n.totalChartDuration, formatDurationMs(content['totalLevelDurationMs'])),
      StatRow(l10n.avgTilecount, formatFixed(content['averageTilecount'], 2)),
      StatRow(l10n.avgLevelLength, formatDurationMs(content['averageLevelLengthMs'])),
      StatRow(l10n.avgBPM, formatFixed(content['averageBpm'], 2)),
      StatRow(l10n.totalClearsOnCharts, formatCount(content['totalClearsOnLevels'])),
      StatRow(l10n.totalLikesOnCharts, formatCount(content['totalLikesOnLevels'])),
      StatRow(l10n.totalDownloadsOnCharts, formatCount(content['totalDownloadsOnLevels'])),
    ]),
    StatGroup(l10n.audience, [
      StatRow(l10n.uniquePlayersWhoCleared, formatCount(audience['uniquePlayersCleared'])),
      StatRow(l10n.wfsOnCharts, formatCount(audience['worldsFirstsOnLevels'])),
      StatRow(l10n.wfPpsOnCharts, formatCount(audience['worldsFirstPPsOnLevels'])),
      StatRow(l10n.totalTilesHitOnCharts, formatCount(audience['totalTilesPlayedOnLevels'])),
    ]),
    StatGroup(l10n.timeline, [
      StatRow(l10n.firstChart, formatStatDate(timeline['firstLevelAt'])),
      StatRow(l10n.latestChart, formatStatDate(timeline['latestLevelAt'])),
    ]),
    StatGroup(l10n.levelsByDifficultyType, [
      StatRow('P', formatCount(byType['PLANETARY'])),
      StatRow('G', formatCount(byType['GALACTIC'])),
      StatRow('U', formatCount(byType['UNIVERSAL'])),
      StatRow(l10n.special, formatCount(byType['SPECIAL'])),
    ]),
  ];
}

// ───────────────────────── Icon slots ─────────────────────────

/// P1–P4 → 0, P5–P8 → 1, … (for grouping into GQ/UQ tiers).
int? qTierOf(int number) => number < 1 || number > 20 ? null : min((number - 1) ~/ 4, 4);

({String letter, int number})? _parsePgu(String? name) {
  final match = name == null ? null : RegExp(r'^([PGU])(\d{1,2})$', caseSensitive: false).firstMatch(name.trim());
  if (match == null) return null;
  final number = int.parse(match.group(2)!);
  if (number < 1 || number > 20) return null;
  return (letter: match.group(1)!.toUpperCase(), number: number);
}

/// The five slots of a player header: highest P, G and U cleared, and the GQ/UQ tiers from world's first G/U clears.
List<IconSlot> playerIconSlots(PlayerProfileDetail player, DifficultyCatalog? catalog) {
  final facts = player.funFacts;
  final clears = facts['clearsByDifficultyNoDupes'] is Map<String, dynamic>
      ? facts['clearsByDifficultyNoDupes'] as Map<String, dynamic>
      : _section(facts, 'clearsByDifficulty');
  final wfs = _section(facts, 'worldsFirstByDifficulty');

  final top = <String, ({int number, int count, Difficulty? difficulty})>{};
  for (final entry in clears.entries) {
    final count = asInt(entry.value);
    final difficulty = catalog?.byId(int.tryParse(entry.key));
    final parsed = _parsePgu(difficulty?.name);
    if (count <= 0 || parsed == null) continue;
    final current = top[parsed.letter];
    if (current == null || parsed.number > current.number) {
      top[parsed.letter] = (number: parsed.number, count: count, difficulty: difficulty);
    } else if (parsed.number == current.number) {
      top[parsed.letter] = (number: current.number, count: current.count + count, difficulty: current.difficulty);
    }
  }

  final qTop = <String, ({int tier, int count})>{};
  for (final entry in wfs.entries) {
    final count = asInt(entry.value);
    final parsed = _parsePgu(catalog?.byId(int.tryParse(entry.key))?.name);
    if (count <= 0 || parsed == null || parsed.letter == 'P') continue;
    final tier = qTierOf(parsed.number);
    if (tier == null) continue;
    final current = qTop[parsed.letter];
    if (current == null || tier > current.tier) {
      qTop[parsed.letter] = (tier: tier, count: count);
    } else if (tier == current.tier) {
      qTop[parsed.letter] = (tier: tier, count: current.count + count);
    }
  }

  IconSlot pgu(String letter) => switch (top[letter]) {
    final best? => IconSlot(
      letter: letter,
      iconUrl: best.difficulty?.icon,
      badge: best.count,
      tooltip: l10n.topClear(letter, best.number, best.count),
    ),
    null => IconSlot(letter: letter, tooltip: l10n.letterNoClears(letter)),
  };

  IconSlot q(String letter) => switch (qTop[letter]) {
    final best? => IconSlot(
      letter: '${letter}Q',
      iconUrl: catalog?.all.where((d) => d.name.startsWith('${letter}Q${best.tier}')).firstOrNull?.icon,
      badge: best.count,
      tooltip: l10n.qFromWorldsFirst(letter, best.tier, best.count),
    ),
    null => IconSlot(letter: '${letter}Q', tooltip: l10n.qNoWorldsFirst(letter)),
  };

  return [pgu('P'), pgu('G'), pgu('U'), q('G'), q('U')];
}

/// Clears per difficulty for the expanded header. World's first G/U clears also count toward their GQ/UQ tier.
Map<int, int> playerClearsByDifficulty(PlayerProfileDetail player, DifficultyCatalog? catalog) {
  final facts = player.funFacts;
  final clears = facts['clearsByDifficultyNoDupes'] is Map<String, dynamic>
      ? facts['clearsByDifficultyNoDupes'] as Map<String, dynamic>
      : _section(facts, 'clearsByDifficulty');
  final result = {for (final entry in clears.entries) ?int.tryParse(entry.key): asInt(entry.value)};

  for (final entry in _section(facts, 'worldsFirstByDifficulty').entries) {
    final count = asInt(entry.value);
    final parsed = _parsePgu(catalog?.byId(int.tryParse(entry.key))?.name);
    final tier = parsed == null ? null : qTierOf(parsed.number);
    if (count <= 0 || parsed == null || parsed.letter == 'P' || tier == null) continue;
    final q = catalog?.all.where((d) => d.name.startsWith('${parsed.letter}Q$tier')).firstOrNull;
    if (q != null) result[q.id] = (result[q.id] ?? 0) + count;
  }
  return result;
}

/// Creator header slots: the highest tier of each curation group (C, V, O, H), then the rest in turn, up to 5.
List<IconSlot> creatorIconSlots(CreatorProfileDetail creator, FacetCatalog? curationTypes) =>
    curationIconSlots(creator.curationTypeCounts, creator.displayCurationTypeIds, curationTypes);

/// Same rules as [creatorIconSlots] from curation counts only (for list cards without a full profile).
List<IconSlot> curationIconSlots(
  Map<int, int> curationTypeCounts,
  List<int> displayCurationTypeIds,
  FacetCatalog? curationTypes,
) {
  IconSlot slotOf(FacetItem type, int count) => IconSlot(
    letter: type.name.length <= 3 ? type.name : type.name.substring(0, 2),
    iconUrl: type.icon,
    badge: count,
    tooltip: l10n.typeLevelCount(type.name, count),
  );

  final manual = displayCurationTypeIds.toSet().take(5).toList();
  if (manual.isNotEmpty) {
    return [
      for (final id in manual)
        switch (curationTypes?.byId(id)) {
          final type? => slotOf(type, curationTypeCounts[id] ?? 0),
          null => IconSlot(letter: '#$id', badge: curationTypeCounts[id] ?? 0),
        },
    ];
  }

  const families = ['C', 'V', 'O', 'H'];
  final byFamily = {for (final family in families) family: <({FacetItem type, int count, int tier})>[]};
  final misc = <({FacetItem type, int count})>[];
  for (final entry in curationTypeCounts.entries) {
    final type = curationTypes?.byId(entry.key);
    if (type == null || entry.value <= 0 || type.name.isEmpty) continue;
    final match = RegExp(r'^([CVOH])(\d*)$', caseSensitive: false).firstMatch(type.name.trim());
    if (match == null) {
      misc.add((type: type, count: entry.value));
    } else {
      final digits = match.group(2)!;
      byFamily[match.group(1)!.toUpperCase()]!.add((
        type: type,
        count: entry.value,
        tier: digits.isEmpty ? 0 : int.parse(digits),
      ));
    }
  }

  final slots = <IconSlot>[];
  final used = <int>{};
  final queues = <String, List<({FacetItem type, int count, int tier})>>{};
  for (final family in families) {
    final list = [...byFamily[family]!]
      ..sort((a, b) => b.tier != a.tier ? b.tier.compareTo(a.tier) : b.count.compareTo(a.count));
    if (list.isEmpty) continue;
    slots.add(slotOf(list.first.type, list.first.count));
    used.add(list.first.type.id);
    queues[family] = list.skip(1).toList();
  }
  misc.sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.type.id.compareTo(b.type.id));
  for (final entry in misc) {
    if (slots.length >= 5) break;
    if (used.add(entry.type.id)) slots.add(slotOf(entry.type, entry.count));
  }
  // Fill the remaining slots one group at a time.
  var added = true;
  while (slots.length < 5 && added) {
    added = false;
    for (final family in families) {
      final queue = queues[family];
      if (slots.length >= 5 || queue == null || queue.isEmpty) continue;
      final entry = queue.removeAt(0);
      if (used.add(entry.type.id)) {
        slots.add(slotOf(entry.type, entry.count));
        added = true;
      }
    }
  }
  return slots.take(5).toList();
}

// ───────────────────────── Difficulty chart ─────────────────────────

/// One bar of the difficulty chart.
class DifficultyBar {
  const DifficultyBar({required this.difficulty, required this.label, required this.count});

  final Difficulty difficulty;
  final String label;
  final int count;
}

/// Counts per difficulty as bars, listing every PGU difficulty (level charts also include Q, P0, Unranked and
/// Impossible).
/// Difficulties ending in J are added to the same difficulty without the J.
List<DifficultyBar> difficultyBars(Map<String, dynamic>? counts, DifficultyCatalog? catalog, {required bool levels}) {
  if (catalog == null) return const [];
  final rows = <({Difficulty difficulty, String label, int count, num sort})>[];
  for (final difficulty in catalog.all) {
    final name = difficulty.name;
    final special =
        difficulty.type == 'SPECIAL' &&
        (name.contains('Q') || name.contains('P0') || name.contains('Impossible') || name.contains('Unranked'));
    if (difficulty.type != 'PGU' && !(levels && special)) continue;

    var label = name.contains('Q') ? name.split(' ').first : name;
    num sort = difficulty.sortOrder;
    if (name.contains('Impossible')) label = '∞';
    if (name.contains('P0')) sort = -1;
    if (name.contains('Unranked')) {
      sort = -2;
      label = '0';
    }
    rows.add((difficulty: difficulty, label: label, count: asInt(counts?['${difficulty.id}']), sort: sort));
  }
  rows.sort((a, b) => a.sort.compareTo(b.sort));

  final bars = <DifficultyBar>[];
  for (final row in rows) {
    if (row.label.endsWith('J')) {
      final parent = bars.indexWhere((bar) => bar.label == row.label.substring(0, row.label.length - 1));
      if (parent >= 0) {
        final bar = bars[parent];
        bars[parent] = DifficultyBar(difficulty: bar.difficulty, label: bar.label, count: bar.count + row.count);
      }
      continue;
    }
    bars.add(DifficultyBar(difficulty: row.difficulty, label: row.label, count: row.count));
  }
  return bars;
}

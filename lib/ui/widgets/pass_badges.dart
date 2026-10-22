import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/models/pass.dart';
import 'hover_tip.dart';

/// Judgement colors. Early and late sides share colors, getting greener toward the center (same layout as the website).
abstract final class JudgementColors {
  static const perfect = Color(0xFF6BD68A);
  static const near = Color(0xFFF2D06B);
  static const far = Color(0xFFF4A259);
  static const worst = Color(0xFFF2545B);

  /// Center Perfect of X-Perfect passes, white to stand apart from Perfect−/Perfect+ (green).
  static const xPerfect = Color(0xFFFFFFFF);

  /// Platinum for special values like the accuracy of a pure X-Perfect.
  static const platinum = Color(0xFFE6EEF6);
  static const platinumGlow = Color(0xFFA8CCE8);

  static Color of(Judgement judgement, {required bool xPerfect}) => switch (judgement) {
    Judgement.tooEarly || Judgement.tooLate => worst,
    Judgement.early || Judgement.late => far,
    Judgement.earlyPerfect || Judgement.latePerfect => near,
    Judgement.perfectMinus || Judgement.perfectPlus => perfect,
    Judgement.perfect => xPerfect ? JudgementColors.xPerfect : perfect,
  };
}

/// Flags on a pass (same order and names as the website's PassFlags):
/// world's first, auto-submitted, key count, hold setting, game version, X-Perfect.
List<({String label, String? tip})> passFlags(LevelPass pass) => [
  if (pass.isWorldsFirst) (label: 'WF', tip: tr('세계 최초 클리어!', "World's First Clear!")),
  if (pass.isWorldsFirstPP) (label: 'WF PP', tip: tr('세계 최초 PP 클리어!', "World's First Pure Perfect!")),
  if (pass.isAutoSubmitted)
    (label: tr('자동 제출', 'Auto-submitted'), tip: tr('게임에서 바로 제출된 기록', 'Submitted straight from the game')),
  if (pass.keyCountLabel case final keys?) (label: keys, tip: null),
  if (pass.isNoHoldTap) (label: tr('홀드 설정 꺼짐', 'No Hold'), tip: tr('기본 외 홀드 타일 동작', 'Alt. hold option')),
  if (pass.era == AdofaiEra.v2)
    (
      label: 'v2',
      tip: tr(
        '엔진 변경 이전 버전입니다 (v2.9.8까지).\n타이밍 엔진 문제로 안정성과 정밀도가 낮았습니다.',
        'Before the engine change (up to v2.9.8).\nTiming engine issues made it less stable and precise.',
      ),
    ),
  if (pass.era == AdofaiEra.pre340)
    (label: '<3.4.0', tip: tr('X-Perfect 이전 버전입니다 (v3.3.1까지).', 'Before X-Perfect (up to v3.3.1).')),
  if (pass.isXPerfectMode) (label: 'X-Perfect', tip: null),
];

/// One flag (a small rounded chip). Shows its description on hover if it has one.
class PassFlagChip extends StatelessWidget {
  const PassFlagChip({super.key, required this.label, this.tip, this.compact = false});

  final String label;
  final String? tip;

  /// Smaller size for tight places like leaderboard rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(label, style: compact ? theme.textTheme.labelSmall : theme.textTheme.labelLarge),
    );
    final message = tip;
    return message == null ? chip : HoverTip(message: message, child: chip);
  }
}

/// Ranked score contribution. Green is actually added, gray is what it could have added.
class ImpactChip extends StatelessWidget {
  const ImpactChip({super.key, required this.text, required this.positive});

  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF6BD68A);
    final color = positive ? green : theme.colorScheme.onSurfaceVariant;

    return HoverTip(
      message: positive
          ? tr('이 기록이 랭킹 점수에 보탠 몫', 'What this pass adds to the ranked score')
          : tr('랭킹 점수에 들어가지 않는 기록이에요 (보탤 수 있었던 몫)', "Doesn't count toward the ranked score (what it could have added)"),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

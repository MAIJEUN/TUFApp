import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/pass.dart';
import 'common.dart';
import 'hover_tip.dart';
import 'level_card.dart';
import 'motion.dart';
import 'pass_badges.dart';
import 'slide_overflow.dart';
import 'video_backdrop.dart';

/// 클리어 기록 한 줄의 공통 틀. 레벨 리더보드, '클리어' 목록, 플레이어 페이지의 기록이 함께 쓴다.
///
/// 레벨 카드와 같은 크기(여백 12, 안쪽 높이 72, 왼쪽 칸 72, 칸 사이 16)이고, 같은 짜임이다:
/// 왼쪽 칸 → 세 줄(위 흐린 줄, 가운데 제목, 아래 제작자·판정과 오른쪽 끝의 표시) → [extra] → 점수·정확도·배속 → 영상과 날짜.
/// 점수·정확도·배속은 웹처럼 이름을 위에 작게 적은 칸으로, 줄마다 같은 자리에 온다.
class PassRow extends StatelessWidget {
  const PassRow({
    super.key,
    required this.pass,
    required this.leading,
    required this.title,
    required this.onTap,
    this.top,
    this.bottomText,
    this.showJudgements = false,
    this.extra,
    this.impact,
    this.potentialImpact,
    this.showDate = true,
    this.videoBackdrop = true,
    this.rank,
  });

  final LevelPass pass;

  /// 왼쪽 칸 (난이도 아이콘, 순위와 사진 등). 레벨 카드의 난이도 칸과 같은 폭이다.
  final Widget leading;

  /// 위 흐린 줄.
  final String? top;

  /// 가운데 줄 (곡 이름, 플레이어 이름 등).
  final Widget title;

  /// 아래 줄 맨 앞의 흐린 글 (레벨 제작자 등).
  final String? bottomText;

  /// 아래 줄에 판정 묶음을 표시 앞에 둘지 (레벨 리더보드처럼 같은 레벨끼리 비교할 때).
  final bool showJudgements;

  /// 세 줄과 점수 칸 사이에 놓는 칸 ('클리어' 목록의 플레이어).
  final Widget? extra;

  /// 랭크 점수에 보탠 몫 (플레이어 페이지).
  final double? impact;

  /// 반영되지 않았지만 보탤 수 있었던 몫.
  final double? potentialImpact;
  final bool showDate;

  /// 배경에 영상 썸네일을 깔지 (숨겨진 레벨은 끈다).
  final bool videoBackdrop;

  /// 리더보드 순위. 있으면 웹처럼 줄 왼쪽에 카드 높이만 한 "#1"을 흐리게 깐다.
  final int? rank;
  final VoidCallback onTap;

  /// 레벨 카드의 줄 높이와 같다 (위 22, 가운데 26, 틈 4, 아래 20 = 72).
  static const topLine = 22.0;
  static const titleLine = 26.0;
  static const gap = 4.0;
  static const bottomLine = 20.0;

  /// 오른쪽 숫자 칸들의 폭.
  /// 가장 긴 값(점수 "67,016.00"과 몫 칩, "100.00%", "1.35x")에 맞춰서 칸 사이가 고르게 보이게 한다.
  static const scoreWidth = 108.0;
  static const accuracyWidth = 84.0;
  static const speedWidth = 52.0;
  static const tailWidth = 112.0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final video = pass.isAutoSubmitted || !videoBackdrop ? null : pass.videoLink;
    final top = this.top;
    final flags = passFlags(pass);
    final chip = switch ((impact, potentialImpact)) {
      (final value?, _) => ImpactChip(text: '+${formatScore(value)}', positive: true),
      (null, final value?) => ImpactChip(text: '+${formatScore(value)}', positive: false),
      _ => null,
    };

    return HoverCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      background: switch ((videoBackdrop ? pass.videoLink : null, rank)) {
        (null, null) => null,
        (final link, final rank) => (context, hovered) => Stack(
          fit: StackFit.expand,
          children: [
            if (link != null) VideoBackdrop(videoLink: link, hovered: hovered),
            if (rank != null) RankWatermark(rank: rank),
          ],
        ),
      },
      child: SizedBox(
        height: LevelCard.contentHeight,
        child: Row(
          spacing: 16,
          children: [
            SizedBox(width: 72, height: LevelCard.contentHeight, child: leading),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: topLine,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: top == null || top.isEmpty
                          ? const SizedBox.shrink()
                          : SlideOverflow(
                              child: slidingText(top, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                            ),
                    ),
                  ),
                  SizedBox(
                    height: titleLine,
                    child: Align(alignment: Alignment.centerLeft, child: title),
                  ),
                  const SizedBox(height: gap),
                  SizedBox(
                    height: bottomLine,
                    // 레벨 카드의 태그 줄처럼: 제작자·판정은 왼쪽에서 넘치면 흐르고,
                    // 표시 칩은 시간·타일·BPM처럼 오른쪽 끝에 붙는다.
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SlideOverflow(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 6,
                                  children: [
                                    if (bottomText case final text? when text.isNotEmpty)
                                      Text(text, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                                    if (showJudgements) JudgementStrip(pass: pass),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (flags.isNotEmpty) ...[
                            const SizedBox(width: 16),
                            // 좁은 창에서는 줄의 60%까지만 쓰고 넘치면 흐른다.
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
                              child: SlideOverflow(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 6,
                                  children: [
                                    for (final flag in flags)
                                      PassFlagChip(label: flag.label, tip: flag.tip, compact: true),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ?extra,
            SizedBox(
              width: scoreWidth,
              child: _Labeled(
                label: tr('점수', 'Score'),
                value: Text(
                  formatScore(pass.score),
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                // 칩이 붙는 줄은 점수 칸만 위로 올라간다. 정확도·배속은 다른 줄과 같은 자리에 있다.
                below: chip,
              ),
            ),
            SizedBox(
              width: accuracyWidth,
              child: _Labeled(
                label: tr('정확도', 'Accuracy'),
                value: _Accuracy(pass: pass),
              ),
            ),
            SizedBox(
              width: speedWidth,
              child: _Labeled(
                label: tr('배속', 'Speed'),
                value: Text('${formatSpeed(pass.speed)}x', style: theme.textTheme.titleMedium),
              ),
            ),
            // 레벨 카드의 받기 칸 자리. 영상 단추는 레벨 카드처럼 세로 가운데, 날짜는 오른쪽 아래 모서리.
            // 둘 다 자리가 정해져 있어서, 영상이 없거나 날짜가 짧아도 다른 것은 움직이지 않는다.
            SizedBox(
              width: tailWidth,
              height: LevelCard.contentHeight,
              child: Stack(
                children: [
                  if (video != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: HoverTip(
                        message: tr('영상 보기', 'Watch video'),
                        child: IconButton(
                          onPressed: () => app.openLink(video),
                          icon: const Icon(Icons.smart_display_outlined),
                        ),
                      ),
                    ),
                  if (showDate && pass.clearedAt != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Text(
                        formatDate(pass.clearedAt),
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 이름을 위에 작게 적은 값 칸 (웹의 '점수 / 정확도 / 배속').
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.value, this.below});

  final String label;
  final Widget value;

  /// 값 아래에 붙는 것 (점수의 몫 칩). 있으면 이 칸만 위쪽에 놓는다.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raised = below != null;
    // 점수 아래에 몫 칩까지 붙으면 줄 높이(72)를 넘을 수 있어서, 넘칠 때만 살짝 줄인다.
    return SizedBox(
      height: LevelCard.contentHeight,
      child: Align(
        alignment: raised ? Alignment.topLeft : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(top: raised ? 4 : 0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                value,
                if (below case final widget?) Padding(padding: const EdgeInsets.only(top: 2), child: widget),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 정확도. 클리어 화면처럼 완벽한 기록은 빛나게.
class _Accuracy extends StatelessWidget {
  const _Accuracy({required this.pass});

  final LevelPass pass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = pass.isPureXPerfect
        ? JudgementColors.platinum
        : pass.isPurePerfect
        ? JudgementColors.perfect
        : null;
    return Text(
      formatAccuracy(pass.accuracy),
      maxLines: 1,
      softWrap: false,
      style: theme.textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: color == null ? null : FontWeight.w700,
        shadows: color == null ? null : [Shadow(color: color, blurRadius: 8)],
      ),
    );
  }
}

/// 판정 개수를 한 칸에 묶은 것 (웹과 같은 순서와 색).
/// X-Perfect 기록이면 정확−/정확+까지 아홉 칸이고, 가운데 정확은 흰색이다.
class JudgementStrip extends StatelessWidget {
  const JudgementStrip({super.key, required this.pass});

  final LevelPass pass;

  @override
  Widget build(BuildContext context) {
    final judgements = pass.judgements;
    if (judgements == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final xPerfect = pass.showsXPerfect;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          for (final (judgement, value) in judgements.ordered(xPerfect: xPerfect))
            HoverTip(
              message: '${judgement.label}: ${formatNumber(value)}',
              child: Text(
                formatNumber(value),
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: JudgementColors.of(judgement, xPerfect: xPerfect),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 난이도 아이콘 칸 (플레이어 페이지와 '클리어' 목록). 숨겨진 레벨은 자물쇠.
class PassDifficultyIcon extends StatelessWidget {
  const PassDifficultyIcon({super.key, required this.icon, this.hidden = false});

  final String? icon;
  final bool hidden;

  @override
  Widget build(BuildContext context) => Center(
    child: hidden
        ? Icon(Icons.lock_outline, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant)
        : NetworkIcon(icon, size: 48),
  );
}

/// 웹의 리더보드 줄처럼 왼쪽에 카드 높이만 하게 깔리는 순위 ("#1").
/// 배경이라 다른 요소의 자리에는 영향이 없다. 1·2·3위는 금·은·빨강 (웹과 같은 색).
class RankWatermark extends StatelessWidget {
  const RankWatermark({super.key, required this.rank});

  final int rank;

  static Color colorOf(int rank, Color fallback) => switch (rank) {
    1 => const Color(0xFFFFD700),
    2 => const Color(0xFFC0C0C0),
    3 => const Color(0xFFFF6666),
    _ => fallback,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = rank >= 1 && rank <= 3;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '#$rank',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 88,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
              color: colorOf(rank, theme.colorScheme.onSurface).withValues(alpha: medal ? 0.22 : 0.1),
            ),
          ),
        ),
      ),
    );
  }
}

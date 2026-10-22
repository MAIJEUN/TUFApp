import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/level.dart';
import '../../core/models/pass.dart';
import '../../core/tuf_api_client.dart';
import '../widgets/common.dart';
import '../widgets/embedded_video.dart';
import '../widgets/side_by_side.dart';
import '../widgets/hover_tip.dart';
import '../widgets/level_card.dart';
import '../widgets/motion.dart';
import 'profile/profile_navigation.dart';
import '../widgets/pass_badges.dart';
import '../widgets/slide_overflow.dart';
import '../widgets/smooth_scroll.dart';
import 'level_viewer_page.dart' show sideGap, videoKey;

/// Pass details: level, player, score and judgements, video.
/// Opens when a row of a level's leaderboard is tapped.
class PassViewerPage extends StatefulWidget {
  const PassViewerPage({super.key, required this.level, required this.pass, this.detail});

  final Level level;
  final LevelPass pass;

  /// Pass details the caller already fetched (ranked score contribution, rank); skips refetching if given.
  final PassDetail? detail;

  static Future<void> open(BuildContext context, {required Level level, required LevelPass pass, PassDetail? detail}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PassViewerPage(level: level, pass: pass, detail: detail),
        ),
      );

  @override
  State<PassViewerPage> createState() => _PassViewerPageState();
}

class _PassViewerPageState extends State<PassViewerPage> {
  static const _maxWidth = pageMaxWidth;

  final _scroll = SmoothScrollController();
  PlayerProfile? _player;
  late PassDetail? _detail = widget.detail;
  bool _started = false;

  /// Whether both requests finished (successfully or not), so the score line stops saying "Loading".
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Ranked score and rank are fetched separately. On failure the pass itself is still shown.
  Future<void> _load() async {
    final api = AppScope.of(context).api;
    await Future.wait([if (_detail == null) _loadDetail(api), _loadPlayer(api)]);
    if (mounted) setState(() => _loaded = true);
  }

  /// What this pass adds to the ranked score, and the player's rank.
  Future<void> _loadDetail(TufApiClient api) async {
    try {
      final detail = await api.getPass(widget.pass.id);
      if (mounted) setState(() => _detail = detail);
    } on Object {
      // The pass is still shown without its score contribution.
    }
  }

  /// The player's top difficulty and pass count.
  Future<void> _loadPlayer(TufApiClient api) async {
    try {
      final player = await api.getPlayer(widget.pass.playerId);
      if (mounted) setState(() => _player = player);
    } on Object {
      // Name and country are already in the pass.
    }
  }

  Widget _section(Widget child) => SliverToBoxAdapter(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pass = widget.pass;
    final video = pass.videoLink;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr('뒤로', 'Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(tr('${pass.playerName}의 클리어', "${pass.playerName}'s pass")),
      ),
      body: SmoothScrollbar(
        controller: _scroll,
        builder: (context, behavior) => CustomScrollView(
          controller: _scroll,
          scrollBehavior: behavior,
          slivers: [
            _section(
              Padding(
                padding: const EdgeInsets.only(top: 16),
                // Tapping opens the level details.
                child: LevelCard(level: widget.level, compact: false),
              ),
            ),
            _section(
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 32),
                // Pass on the left, player at the top right with the video below.
                // The video fills the right column and the pass column on the left stretches to its height.
                child: SideBySide(
                  gap: sideGap,
                  left: _PassDetails(pass: pass),
                  right: (context, videoHeight) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PlayerCard(pass: pass, player: _player, detail: _detail, loading: !_loaded),
                      if (video != null) ...[
                        const SizedBox(height: sideGap),
                        // If the left column is taller, the video takes the extra space.
                        Expanded(
                          child: SizedBox(
                            key: videoKey,
                            height: videoHeight,
                            child: _PassVideo(videoLink: video),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The player behind the pass. Score and rank fill in as they arrive.
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.pass, required this.player, required this.detail, required this.loading});

  final LevelPass pass;
  final PlayerProfile? player;
  final PassDetail? detail;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final player = this.player;
    final score = detail?.score;

    // Tapping opens the player page.
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ProfileNavigation.openPlayer(context, pass.playerId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _Avatar(
                url: player?.avatar ?? pass.playerAvatar,
                fallback: player?.avatarFallback ?? pass.playerAvatarFallback,
                size: 56,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: SlideOverflow(child: slidingText(pass.playerName, style: theme.textTheme.titleLarge)),
                        ),
                        const SizedBox(width: 8),
                        CountryFlag(country: pass.country, height: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FadeSwitcher(
                      alignment: Alignment.centerLeft,
                      child: player == null && score == null
                          ? Text(
                              loading
                                  ? tr('점수 불러오는 중...', 'Loading score...')
                                  : tr('점수를 불러오지 못했어요', "Couldn't load the score"),
                              key: ValueKey(loading),
                              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                            )
                          : Row(
                              key: const ValueKey('score'),
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  formatScore(score?.current ?? player?.rankedScore ?? 0),
                                  style: theme.textTheme.titleMedium,
                                ),
                                // What this pass adds to the ranked score (same notation as the website).
                                if (score != null && score.countsForRanked && score.impact > 0) ...[
                                  const SizedBox(width: 8),
                                  ImpactChip(text: '+${formatScore(score.impact)}', positive: true),
                                ] else if (score != null && !score.countsForRanked && score.potentialImpact > 0) ...[
                                  const SizedBox(width: 8),
                                  ImpactChip(text: '+${formatScore(score.potentialImpact)}', positive: false),
                                ],
                                if (player?.topDifficulty case final top?) ...[
                                  const SizedBox(width: 12),
                                  HoverTip(
                                    message: tr('가장 높이 깬 난이도', 'Top difficulty cleared'),
                                    child: Text(top, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                                  ),
                                ],
                                if (player != null) ...[
                                  const SizedBox(width: 12),
                                  HoverTip(
                                    message: tr(
                                      '세계 최초 클리어 ${formatNumber(player.worldsFirstCount)}개',
                                      "${formatNumber(player.worldsFirstCount)} world's first ${plural(player.worldsFirstCount, 'clear')}",
                                    ),
                                    child: Text(
                                      tr(
                                        '클리어 ${formatNumber(player.totalPasses)}개',
                                        "${formatNumber(player.totalPasses)} ${plural(player.totalPasses, 'pass', 'passes')}",
                                      ),
                                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                    // Ranked score without this pass.
                    if (score != null && score.previous > 0)
                      HoverTip(
                        message: tr('이 기록이 없었을 때의 랭킹 점수', 'Ranked score without this pass'),
                        child: Text(
                          formatScore(score.previous),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                    if (pass.clearedAt case final date?) ...[
                      const SizedBox(height: 4),
                      Text(
                        tr('${formatDate(date)} 클리어', 'Cleared ${formatDate(date)}'),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Only one rank is shown: the overall rank, as on the website.
              FadeSwitcher(
                scale: true,
                child: (detail?.rank ?? 0) == 0
                    ? const SizedBox(key: ValueKey('none'))
                    : HoverTip(
                        key: const ValueKey('rank'),
                        message: tr('전체 랭킹 순위', 'Overall rank'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#${formatNumber(detail!.rank)}',
                            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Score, accuracy, speed, difficulty and judgements.
class _PassDetails extends StatelessWidget {
  const _PassDetails({required this.pass});

  final LevelPass pass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flags = passFlags(pass);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          // Same height as the right column, so the spare space is split above and below.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StatRow(label: tr('점수', 'Score'), value: formatScore(pass.score)),
            _StatRow(
              label: tr('정확도', 'Accuracy'),
              value: formatAccuracy(pass.accuracy),
              glow: pass.isPureXPerfect
                  ? (JudgementColors.platinum, JudgementColors.platinumGlow)
                  : pass.isPurePerfect
                  ? (JudgementColors.perfect, JudgementColors.perfect)
                  : null,
            ),
            _StatRow(
              label: tr('속도', 'Speed'),
              value: '${formatSpeed(pass.speed)}x',
              last: pass.feelingRating == null && pass.expectedRating == null,
            ),
            // Rows without a rating are left out, and the last row has no bottom padding.
            if (pass.feelingRating case final feeling?)
              _StatRow(label: tr('체감 난이도', 'Feeling rating'), value: feeling, last: pass.expectedRating == null),
            if (pass.expectedRating case final expected?)
              _StatRow(label: tr('예상 난이도', 'Expected rating'), value: expected, last: true),
            if (flags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [for (final flag in flags) PassFlagChip(label: flag.label, tip: flag.tip)],
              ),
            ],
            if (pass.judgements case final judgements?) ...[
              const SizedBox(height: 16),
              _JudgementBox(judgements: judgements, xPerfect: pass.showsXPerfect),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.last = false, this.glow});

  final String label;
  final String value;
  final bool last;

  /// Text color and glow color, to highlight special values like a pure perfect accuracy.
  final (Color, Color)? glow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                color: glow?.$1 ?? theme.colorScheme.onSecondaryContainer,
                fontWeight: glow == null ? null : FontWeight.w700,
                shadows: [if (glow case (_, final light)) Shadow(color: light.withValues(alpha: 0.8), blurRadius: 10)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Judgement counts. Like the website: early/perfect/late on top, the farther-off judgements below.
class _JudgementBox extends StatelessWidget {
  const _JudgementBox({required this.judgements, required this.xPerfect});

  final PassJudgements judgements;

  /// X-Perfect passes add Perfect−/Perfect+ to the top row (same layout as the website).
  final bool xPerfect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(Judgement judgement, int value) => _Judgement(
      label: judgement.label,
      value: value,
      color: JudgementColors.of(judgement, xPerfect: xPerfect),
      big: judgement == Judgement.perfect,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(tr('판정', 'Judgements'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              cell(Judgement.earlyPerfect, judgements.earlyPerfect),
              if (xPerfect) cell(Judgement.perfectMinus, judgements.perfectMinus),
              cell(Judgement.perfect, judgements.perfect),
              if (xPerfect) cell(Judgement.perfectPlus, judgements.perfectPlus),
              cell(Judgement.latePerfect, judgements.latePerfect),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              cell(Judgement.tooEarly, judgements.earlyDouble),
              cell(Judgement.early, judgements.earlySingle),
              cell(Judgement.late, judgements.lateSingle),
              cell(Judgement.tooLate, judgements.lateDouble),
            ],
          ),
        ],
      ),
    );
  }
}

class _Judgement extends StatelessWidget {
  const _Judgement({required this.label, required this.value, required this.color, this.big = false});

  final String label;
  final int value;
  final Color color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          formatNumber(value),
          style: (big ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Pass video, played in the app like on the level page.
class _PassVideo extends StatefulWidget {
  const _PassVideo({required this.videoLink});

  final String videoLink;

  @override
  State<_PassVideo> createState() => _PassVideoState();
}

class _PassVideoState extends State<_PassVideo> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final embed = !_failed && EmbeddedVideo.canPlay(widget.videoLink);

    // The player already shows the video title. Sized by the parent's box.
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.expand(
        child: embed
            ? ColoredBox(
                color: Colors.black,
                child: EmbeddedVideo(
                  videoLink: widget.videoLink,
                  onUnavailable: () {
                    if (mounted) setState(() => _failed = true);
                  },
                ),
              )
            : Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => app.openLink(widget.videoLink),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(tr('브라우저에서 영상 보기', 'Watch video in browser')),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size, this.fallback});

  final String? url;
  final String? fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: colors.surfaceContainerHighest,
        child: url == null
            ? Icon(Icons.person, size: size * 0.7, color: colors.onSurfaceVariant)
            : NetworkIcon(url, size: size, fallback: fallback),
      ),
    );
  }
}

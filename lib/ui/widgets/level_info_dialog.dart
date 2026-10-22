import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/models/level.dart';
import 'common.dart';
import '../pages/profile/creator_profile_page.dart';
import 'hover_tip.dart';
import 'slide_overflow.dart';
import 'smooth_scroll.dart';

/// All of a level's info in one dialog (the website's "Full info"):
/// values like difficulty, score and length, the charters and VFX artists, and aliases.
class LevelInfoDialog extends StatelessWidget {
  const LevelInfoDialog({super.key, required this.level});

  final Level level;

  static Future<void> show(BuildContext context, Level level) => showDialog(
    context: context,
    builder: (context) => LevelInfoDialog(level: level),
  );

  /// Credits for a role, in the server's order.
  List<LevelCredit> _creditsFor(String role) => ([
    ...level.credits,
  ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))).where((credit) => credit.role?.toLowerCase() == role).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppScope.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final charters = _creditsFor('charter');
    final vfxers = _creditsFor('vfxer');

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SlideOverflow(child: slidingText(level.song, style: theme.textTheme.headlineSmall)),
                  ),
                  IconButton(
                    tooltip: tr('닫기', 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              SlideOverflow(
                child: slidingText(level.artist, style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
              ),
              if (level.createdAt case final date?)
                Text(
                  tr('등록: ${formatDate(date)}', 'Added: ${formatDate(date)}'),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              const SizedBox(height: 16),
              Flexible(
                child: _Scrollable(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (level.team case final team?) _InfoRow(label: tr('팀', 'Team'), value: team),
                      _InfoRow(label: tr('난이도', 'Difficulty'), value: level.difficulty?.name ?? '#${level.diffId}'),
                      // Levels without their own base score send 0, so fall back to the difficulty's base score.
                      _InfoRow(
                        label: tr('기반 점수', 'Base score'),
                        value: '${formatNumber(level.baseScoreOverride ?? level.difficulty?.baseScore ?? 0)} PP',
                      ),
                      if (level.aliases.isNotEmpty)
                        _InfoRow(
                          label: tr('별칭', 'Aliases'),
                          value: level.aliases.map((alias) => '${alias.field}: ${alias.alias}').join(', '),
                        ),
                      if (charters.isNotEmpty || vfxers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (charters.isNotEmpty)
                              Expanded(
                                child: _People(title: tr('채보', 'Charters'), credits: charters),
                              ),
                            if (charters.isNotEmpty && vfxers.isNotEmpty) const SizedBox(width: 16),
                            if (vfxers.isNotEmpty)
                              Expanded(
                                child: _People(title: tr('이펙트', 'VFX'), credits: vfxers),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (level.videoLink case final video?)
                    TextButton.icon(
                      onPressed: () => app.openLink(video),
                      icon: const Icon(Icons.smart_display_outlined),
                      label: Text(tr('영상 보기', 'Watch video')),
                    ),
                  if (level.workshopLink case final workshop?) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => app.openLink(workshop),
                      icon: const Icon(Icons.sports_esports_outlined),
                      label: Text(tr('스팀 창작마당', 'Steam Workshop')),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('닫기', 'Close'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrolls long content (with the app's smooth scrolling).
class _Scrollable extends StatefulWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  State<_Scrollable> createState() => _ScrollableState();
}

class _ScrollableState extends State<_Scrollable> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SmoothScrollbar(
    controller: _scroll,
    builder: (context, behavior) => ScrollConfiguration(
      behavior: behavior,
      child: SingleChildScrollView(controller: _scroll, child: widget.child),
    ),
  );
}

/// One "Difficulty   U16" row.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// People who charted or did VFX.
class _People extends StatelessWidget {
  const _People({required this.title, required this.credits});

  final String title;
  final List<LevelCredit> credits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final credit in credits)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: HoverTip(
              message: credit.creatorAliases.isEmpty
                  ? ''
                  : tr(
                      '다른 이름: ${credit.creatorAliases.join(', ')}',
                      'Also known as: ${credit.creatorAliases.join(', ')}',
                    ),
              // Tapping opens the creator page.
              child: Material(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: switch (credit.creatorId) {
                    final id? => () {
                      // This dialog's context is unusable once it closes, so grab the navigator first.
                      final navigator = Navigator.of(context)..pop();
                      navigator.push(MaterialPageRoute(builder: (context) => CreatorProfilePage(creatorId: id)));
                    },
                    null => null,
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SlideOverflow(
                      child: slidingText(
                        credit.creatorAliases.isEmpty
                            ? credit.creatorName ?? tr('알 수 없음', 'Unknown')
                            : '${credit.creatorName ?? tr('알 수 없음', 'Unknown')} (${credit.creatorAliases.join(', ')})',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

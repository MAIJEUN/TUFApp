import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../widgets/motion.dart';

/// One profile module: title on the left, buttons on the right, collapsible (like the level page's "Leaderboard").
class ProfileSection extends StatefulWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing = const [],
    this.collapsible = true,
  });

  final String title;

  /// Dim text next to the title (a count, etc.).
  final String? subtitle;
  final Widget child;

  /// Buttons on the right of the title row.
  final List<Widget> trailing;
  final bool collapsible;

  @override
  State<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<ProfileSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ProfileSectionHeader(
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: [
          ...widget.trailing,
          if (widget.collapsible)
            IconButton(
              tooltip: _expanded ? tr('접기', 'Collapse') : tr('펼치기', 'Expand'),
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: AnimatedRotation(
                turns: _expanded ? 0 : 0.5,
                duration: Motion.medium,
                curve: Motion.curve,
                child: const Icon(Icons.expand_less),
              ),
            ),
        ],
      ),
      Reveal(visible: _expanded, child: widget.child),
    ],
  );
}

/// Module title row (same look as the level page's "Leaderboard" row).
class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({super.key, required this.title, this.subtitle, this.trailing = const []});

  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (subtitle case final text?) ...[
            const SizedBox(width: 12),
            Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const Spacer(),
          for (final (index, widget) in trailing.indexed) ...[if (index > 0) const SizedBox(width: 8), widget],
        ],
      ),
    );
  }
}

/// Small value box inside a module (same background as the judgement boxes on the pass page).
class ProfileTile extends StatelessWidget {
  const ProfileTile({super.key, required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../widgets/motion.dart';

/// 프로필의 모듈 하나. 레벨 화면의 '리더보드'처럼 제목은 왼쪽, 단추는 오른쪽에 두고, 접을 수 있다.
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

  /// 제목 옆의 흐린 글 (개수 등).
  final String? subtitle;
  final Widget child;

  /// 제목 줄 오른쪽에 놓는 단추들.
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

/// 모듈 제목 줄 (레벨 화면의 '리더보드' 줄과 같은 모양).
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

/// 칸 안의 작은 값 상자 (클리어 화면의 판정 상자와 같은 바탕).
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

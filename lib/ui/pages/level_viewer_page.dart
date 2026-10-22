import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/image_cache_store.dart';
import '../../core/l10n.dart';
import '../../core/models/level.dart';
import '../../core/models/pass.dart';
import '../../core/tuf_api_client.dart';
import '../widgets/common.dart';
import '../widgets/embedded_video.dart';
import '../widgets/side_by_side.dart';
import '../widgets/hover_tip.dart';
import '../widgets/level_card.dart';
import '../widgets/level_info_dialog.dart';
import 'pass_viewer_page.dart';
import 'profile/profile_navigation.dart';
import '../widgets/motion.dart';
import '../widgets/pass_row.dart';
import '../widgets/slide_overflow.dart';
import '../widgets/smooth_scroll.dart';

/// 레벨 하나를 자세히 본다: 카드, 기록 요약, 영상, 리더보드.
/// 목록이나 팩에서 레벨 카드를 누르면 이 화면이 그 위에 열린다.
class LevelViewerPage extends StatefulWidget {
  const LevelViewerPage({super.key, required this.level});

  final Level level;

  static Future<void> open(BuildContext context, Level level) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => LevelViewerPage(level: level)));

  @override
  State<LevelViewerPage> createState() => _LevelViewerPageState();
}

class _LevelViewerPageState extends State<LevelViewerPage> {
  static const _maxWidth = pageMaxWidth;

  final _scroll = SmoothScrollController();

  late Level _level = widget.level;
  LevelPassSummary? _summary;
  bool _loading = true;
  String? _error;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope는 initState에서 읽을 수 없다. 처음 한 번만 불러온다.
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = AppScope.of(context).api;
    // 팩에서 온 레벨은 정보가 일부만 있어서 다시 받는다. 실패해도 목록에서 받은 정보로 계속 보여준다.
    unawaited(_refreshLevel(api));

    try {
      final passes = await api.getLevelPasses(_level.id);
      if (!mounted) return;
      setState(() {
        _summary = LevelPassSummary.of(passes);
        _loading = false;
      });
    } on TufApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _refreshLevel(TufApiClient api) async {
    try {
      final full = await api.getLevel(_level.id);
      if (mounted) setState(() => _level = full);
    } on TufApiException {
      // 카드에 보여줄 정보는 이미 있다.
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
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr('뒤로', 'Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('#${_level.id}'),
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
                child: LevelCard(level: _level, compact: false, openable: false),
              ),
            ),
            _section(
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _Overview(level: _level, summary: summary),
              ),
            ),
            _section(
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 12),
                child: Row(
                  children: [
                    Text(tr('리더보드', 'Leaderboard'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: 12),
                    if (summary != null)
                      Text(
                        tr(
                          '${formatNumber(summary.uniquePlayers)}명'
                              '${summary.totalClears != summary.uniquePlayers ? ' (총 ${formatNumber(summary.totalClears)}회)' : ''}',
                          '${formatNumber(summary.uniquePlayers)} ${plural(summary.uniquePlayers, 'player')}'
                              '${summary.totalClears != summary.uniquePlayers ? ' (${formatNumber(summary.totalClears)} total)' : ''}',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    const Spacer(),
                    IconButton(tooltip: tr('새로고침', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
                  ],
                ),
              ),
            ),
            if (summary != null)
              SliverList.builder(
                itemCount: summary.leaderboard.length,
                itemBuilder: (context, index) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: _PassRow(level: _level, rank: index + 1, pass: summary.leaderboard[index]),
                    ),
                  ),
                ),
              ),
            _section(_Footer(loading: _loading, error: _error, summary: summary, onRetry: _load)),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.loading, required this.error, required this.summary, required this.onRetry});

  final bool loading;
  final String? error;
  final LevelPassSummary? summary;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (error case final message?) {
      content = Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: const Icon(Icons.cloud_off),
          title: tr('기록을 불러오지 못했어요', "Couldn't load passes"),
          message: message,
          action: FilledButton(onPressed: onRetry, child: Text(tr('다시 시도', 'Retry'))),
        ),
      );
    } else if (loading) {
      content = const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (summary?.passes.isEmpty ?? false) {
      content = Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(icon: const Icon(Icons.flag_outlined), title: tr('아직 클리어 기록이 없어요', 'No passes yet')),
      );
    } else {
      content = const SizedBox(key: ValueKey('none'), width: double.infinity);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: FadeSwitcher(alignment: Alignment.topCenter, child: content),
    );
  }
}

/// 왼쪽 칸과 오른쪽 칸(영상) 사이 간격. 자세히 보기 화면들이 같은 값을 쓴다.
const sideGap = 16.0;

/// 영상 자리 (크기를 확인하는 테스트에서 찾는다).
const videoKey = ValueKey('video');

/// 왼쪽에 기록 요약, 오른쪽에 영상.
class _Overview extends StatelessWidget {
  const _Overview({required this.level, required this.summary});

  final Level level;
  final LevelPassSummary? summary;

  @override
  Widget build(BuildContext context) {
    final video = level.videoLink;
    if (video == null) return _Records(level: level, summary: summary);

    // 영상이 오른쪽 칸을 꽉 채우고, 왼쪽 기록 칸이 그 높이에 맞춰 늘어난다.
    return SideBySide(
      gap: sideGap,
      left: _Records(level: level, summary: summary),
      right: (context, videoHeight) => SizedBox(
        key: videoKey,
        height: videoHeight,
        child: _VideoPreview(videoLink: video, title: level.song),
      ),
    );
  }
}

class _Records extends StatelessWidget {
  const _Records({required this.level, required this.summary});

  final Level level;
  final LevelPassSummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final best = summary?.bestScore;
    final speed = summary?.bestSpeed;
    final accuracy = summary?.bestAccuracy;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          // 칸을 꽉 채우도록 줄들을 고르게 벌린다 (오른쪽 영상과 높이가 같다).
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RecordRow(
              label: tr('최초 클리어', 'First clear'),
              who: summary?.firstClear?.playerName,
              value: formatDate(summary?.firstClear?.clearedAt),
              last: true,
            ),
            _RecordRow(
              label: tr('최고 점수', 'Highest score'),
              who: best?.playerName,
              value: best == null ? null : formatScore(best.score),
              last: true,
            ),
            _RecordRow(
              label: tr('최고 속도', 'Highest speed'),
              who: speed?.playerName,
              value: speed == null ? null : '${formatSpeed(speed.speed)}x',
              last: true,
            ),
            _RecordRow(
              label: tr('최고 정확도', 'Highest accuracy'),
              who: accuracy?.playerName,
              value: accuracy == null ? null : formatAccuracy(accuracy.accuracy),
              last: true,
            ),
            _RecordRow(
              label: tr('총 클리어 수', 'Total clears'),
              value: summary == null
                  ? null
                  : '${formatNumber(summary.uniquePlayers)}'
                        '${summary.totalClears != summary.uniquePlayers ? ' (${formatNumber(summary.totalClears)})' : ''}',
              last: true,
            ),
            // 사이트처럼 나머지 정보는 따로 창으로 본다.
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => LevelInfoDialog.show(context, level),
                icon: const Icon(Icons.info_outline),
                label: Text(tr('전체 정보', 'Full info')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "최고 점수  [Jipper | 67016.00]" 한 줄. 아직 모르면 빈 칸을 둔다.
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.label, this.who, this.value, this.last = false});

  final String label;
  final String? who;
  final String? value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = this.who;
    final value = this.value;
    final style = theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer);

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FadeSwitcher(
                alignment: Alignment.centerRight,
                child: who == null && value == null
                    ? const SizedBox(key: ValueKey('empty'), height: 32)
                    : Container(
                        key: ValueKey('$who|$value'),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 이름이 길면 이름만 흐르게 두고, 기록(날짜·점수 등)은 항상 그대로 보이게 한다.
                            if (who != null)
                              Flexible(
                                child: SlideOverflow(child: slidingText(who, style: style)),
                              ),
                            if (who != null && value != null) Text('  |  ', style: style),
                            if (value != null) Text(value, maxLines: 1, softWrap: false, style: style),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 영상 썸네일. 누르면 브라우저에서 연다.
/// 사이트처럼 영상 재생기를 바로 띄운다.
/// 앱에서 띄울 수 없으면(재생기를 쓸 수 없거나 YouTube·Bilibili가 아니면) 썸네일을 두고 브라우저로 연다.
class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.videoLink, required this.title});

  final String videoLink;
  final String title;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final embed = !_failed && EmbeddedVideo.canPlay(widget.videoLink);

    // 크기는 부모가 정해 준 칸(16:9)에 맞춘다.
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
            : _Thumbnail(videoLink: widget.videoLink, title: widget.title),
      ),
    );
  }
}

/// 앱에서 재생기를 띄울 수 없을 때 보여주는 썸네일. 누르면 브라우저에서 연다.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.videoLink, required this.title});

  final String videoLink;
  final String title;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);

    return HoverCard(
      padding: EdgeInsets.zero,
      onTap: () => app.openLink(videoLink),
      child: FutureBuilder<String?>(
        future: app.thumbnails.resolve(videoLink),
        initialData: app.thumbnails.peek(videoLink),
        builder: (context, snapshot) => Stack(
          fit: StackFit.expand,
          children: [
            if (snapshot.data case final url?)
              Image(image: DiskCachedImage(url, maxWidth: 640), fit: BoxFit.cover, gaplessPlayback: true),
            // 아이콘이 썸네일 위에서도 잘 보이게 아래를 어둡게 깐다.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.6)],
                ),
              ),
            ),
            Center(child: Icon(Icons.play_circle_fill, size: 56, color: Colors.white.withValues(alpha: 0.9))),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: SlideOverflow(
                child: slidingText(title, style: theme.textTheme.labelLarge?.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 리더보드 한 줄. 웹처럼 순위와 사진, 이름, 판정을 보여준다 (모양은 [PassRow]).
class _PassRow extends StatelessWidget {
  const _PassRow({required this.level, required this.rank, required this.pass});

  final Level level;
  final int rank;
  final LevelPass pass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feeling = pass.feelingRating;
    void openPlayer() => ProfileNavigation.openPlayer(context, pass.playerId);

    return PassRow(
      pass: pass,
      onTap: () => PassViewerPage.open(context, level: level, pass: pass),
      // 사진과 이름을 누르면 그 사람의 플레이어 페이지 (줄의 나머지는 클리어 페이지).
      leading: HoverTip(
        message: tr('플레이어 프로필 보기', 'View player profile'),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: openPlayer,
          child: Center(
            child: _PlayerAvatar(url: pass.playerAvatar, fallback: pass.playerAvatarFallback, size: 48),
          ),
        ),
      ),
      top: feeling == null || feeling.isEmpty ? null : tr('체감 $feeling', 'Feeling $feeling'),
      title: HoverTip(
        message: tr('플레이어 프로필 보기', 'View player profile'),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: openPlayer,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SlideOverflow(child: slidingText(pass.playerName, style: theme.textTheme.titleMedium)),
              ),
              if (pass.country != null) ...[const SizedBox(width: 8), CountryFlag(country: pass.country, height: 14)],
            ],
          ),
        ),
      ),
      showJudgements: true,
      rank: rank,
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.url, required this.size, this.fallback});

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

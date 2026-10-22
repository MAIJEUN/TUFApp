import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/l10n.dart';
import '../../core/level_downloader.dart';
import '../../core/models/difficulty.dart';
import '../../core/models/facet.dart';
import '../../core/models/level.dart';
import '../../core/models/search_models.dart';
import '../pages/level_viewer_page.dart';
import '../theme.dart';
import 'common.dart';
import 'hover_tip.dart';
import 'motion.dart';
import 'raster_snapshot.dart';
import 'slide_overflow.dart';
import 'video_backdrop.dart';

/// '레벨 찾기' 목록의 카드 하나.
class LevelCard extends StatelessWidget {
  const LevelCard({super.key, required this.level, required this.compact, this.openable = true});

  final Level level;
  final bool compact;

  /// 누르면 레벨 자세히 보기를 연다. 자세히 보기 화면 안의 카드는 끈다.
  final bool openable;

  /// 칸과 칸 사이 간격.
  static const _columnGap = 16.0;
  static const _creatorWidth = 176.0;
  static const _statsWidth = 104.0;

  bool get _hasStats => level.clears > 0 || level.likes > 0;

  /// 카드 안쪽 높이. 내용이 많든 적든 모든 카드가 같은 크기를 유지한다.
  static const contentHeight = 72.0;
  static const compactContentHeight = 40.0;

  @override
  Widget build(BuildContext context) => HoverCard(
    onTap: openable ? () => LevelViewerPage.open(context, level) : null,
    padding: compact ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.all(12),
    background: switch (level.videoLink) {
      final link? => (context, hovered) => VideoBackdrop(videoLink: link, hovered: hovered),
      null => null,
    },
    child: SizedBox(
      height: compact ? compactContentHeight : contentHeight,
      // 칸 사이 간격은 전부 같게 둔다.
      child: Row(
        spacing: _columnGap,
        children: [
          _DifficultyIcon(level: level, compact: compact),
          // 시간·타일·BPM은 태그 줄에만 있으므로, 제목과 작곡가 줄은 그 위 공간까지 이어서 쓴다.
          Expanded(
            child: _SongInfo(level: level, compact: compact),
          ),
          SizedBox(
            width: _creatorWidth + _columnGap + _statsWidth,
            child: Stack(
              children: [
                // 클리어·좋아요 칸이 비어 있으면 제작자가 그 자리까지 쓴다.
                // 그래도 넘칠 때만 옆으로 흐르게 한다.
                SizedBox(
                  width: _hasStats ? _creatorWidth : _creatorWidth + _columnGap + _statsWidth,
                  height: double.infinity,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _CreatorInfo(level: level, compact: compact),
                  ),
                ),
                if (_hasStats)
                  Positioned(
                    left: _creatorWidth + _columnGap,
                    top: 0,
                    bottom: 0,
                    width: _statsWidth,
                    child: _Stats(level: level),
                  ),
              ],
            ),
          ),
          SizedBox(width: 88, child: _Links(level: level)),
          SizedBox(
            width: 132,
            // 사이트처럼 받기 버튼 밑에 받은 횟수를 적는다 (간략히 보기는 자리가 없어 뺀다).
            // 받기 단추는 항상 세로 가운데에 두고, 받은 횟수는 그 아래에 따로 붙인다.
            // 횟수가 있든 없든 단추 자리는 바뀌지 않는다.
            child: compact || !(level.downloadCount > 0 || LevelDownloader.isTufCdnLink(level.dlLink))
                ? Center(child: _InstallButton(level: level))
                : SizedBox(
                    height: contentHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        _InstallButton(level: level),
                        Positioned(
                          left: 0,
                          right: 0,
                          // 단추(40) 아래 4만큼 띄운다. 카드 아래 여백까지 살짝 내려가도 된다.
                          top: contentHeight / 2 + 20 + 4,
                          child: Center(child: _DownloadInfo(level: level)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

/// 큐레이션 아이콘들이 놓일 각도(도). 0도가 오른쪽, 90도가 아래.
/// 웹과 같은 식: 가운데 45도에서 90/개수 만큼씩 벌린다.
@visibleForTesting
List<double> curationArcAngles(int count) {
  const arcCenter = 45.0;
  if (count <= 0) return const [];
  final offset = 90.0 / count;
  return [for (var i = 0; i < count; i++) arcCenter + i * offset - (count - 1) * offset / 2];
}

/// 난이도 아이콘. 기반 점수가 난이도 기본값과 다르게 정해진 레벨은 그 값을 아이콘 위에 보여준다.
class _DifficultyIcon extends StatelessWidget {
  const _DifficultyIcon({required this.level, required this.compact});

  final Level level;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    // 칸 폭이 같아야 카드마다 제목 위치가 어긋나지 않는다.
    // 큐레이션 아이콘이 원 밖으로 나오므로 난이도 아이콘보다 넉넉히 잡는다.
    width: compact ? 56 : 72,
    child: Center(
      child: _CuratedDifficultyIcon(
        level: level,
        size: compact ? 32 : 48,
        compact: compact,
        // 간략히 보기는 아이콘 위에 자리가 없어서 작곡가 줄에 적는다.
        baseScore: compact ? null : level.baseScoreOverride,
      ),
    ),
  );
}

/// 웹(.img-wrapper의 drop-shadow 0 0 3px 검정)처럼 아이콘 둘레에 그림자를 깐다.
/// 묶음 전체를 한 번 더 흐리게 그리는 대신 원 모양 그림자를 아이콘마다 둬서 가볍게 그린다 (목록에 수십 개가 놓인다).
class _Shadowed extends StatelessWidget {
  const _Shadowed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Color(0xCC000000), blurRadius: 3)],
    ),
    child: child,
  );
}

/// 난이도 아이콘 둘레에 큐레이션 아이콘(C2, V1 등)을 둘러 보여준다.
class _CuratedDifficultyIcon extends StatelessWidget {
  const _CuratedDifficultyIcon({required this.level, required this.size, required this.compact, this.baseScore});

  /// 한 바퀴에 최대 몇 개까지 두를지.
  static const _maxIcons = 4;

  /// 아래 수치는 웹(levelcard.css .curation-icon)과 같다.
  /// 자세히 보기: 난이도 3rem(48px), 아이콘 1.25rem(20px), 반지름 1.65rem(26.4px).
  /// 간략히 보기: 난이도 2rem(32px), 아이콘 1.1rem(17.6px), 반지름 1.65rem×0.7(18.48px).
  /// 반지름이 난이도 원 반지름(24, 16)보다 커서 아이콘이 원 밖에 살짝 떨어져 놓인다.
  static const _curationScale = 20 / 48;
  static const _radiusScale = 26.4 / 48;
  static const _compactCurationScale = 17.6 / 32;
  static const _compactRadiusScale = 18.48 / 32;

  /// 웹(levelcard.css .rating-icon): 난이도 3rem에 1.5rem 크기, 위·왼쪽으로 -11%.
  static const _ratingScale = 0.5;
  static const _ratingOffsetScale = -0.11;

  final Level level;
  final double size;
  final bool compact;

  /// 난이도 기본값 대신 정해진 기반 점수. 있으면 아이콘 위에 겹쳐 적는다.
  final int? baseScore;

  /// 웹과 같은 조건: 난이도 이름에 Q가 들어가고, 평가 결과가 PGU 난이도일 때만.
  Difficulty? _ratedDifficulty(DifficultyCatalog? catalog) {
    if (!(level.difficulty?.name.contains('Q') ?? false)) return null;
    final rated = catalog?.byId(level.ratedDifficultyId);
    return rated?.type == 'PGU' && rated?.icon != null ? rated : null;
  }

  @override
  Widget build(BuildContext context) {
    final levels = AppScope.of(context).levels;
    final catalog = levels.curationCatalog;
    final rated = _ratedDifficulty(levels.catalog);
    final curations = catalog == null || level.curationTypeIds.isEmpty
        ? const <FacetItem>[]
        : catalog
              .resolve(level.curationTypeIds)
              .where((curation) => !isHiddenCurationArcType(curation))
              .take(_maxIcons)
              .toList();

    // 난이도 아이콘은 큐레이션이 있든 없든 같은 크기를 유지한다.
    final difficulty = HoverTip(
      message: level.difficulty?.name ?? '#${level.diffId}',
      child: _Shadowed(child: NetworkIcon(level.difficulty?.icon, size: size)),
    );
    final baseScore = this.baseScore;
    if (curations.isEmpty && rated == null && baseScore == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: difficulty),
      );
    }

    final iconSize = size * (compact ? _compactCurationScale : _curationScale);
    final radius = size * (compact ? _compactRadiusScale : _radiusScale);
    final angles = curationArcAngles(curations.length);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        // 큐레이션 아이콘은 난이도 원 바깥으로 살짝 나간다 (칸에 여유가 있다).
        clipBehavior: Clip.none,
        children: [
          Center(child: difficulty),
          // Q 레벨이면 평가에서 매겨진 PGU 난이도를 왼쪽 위에 작게 겹친다 (웹 .rating-icon).
          if (rated != null)
            Positioned(
              left: size * _ratingOffsetScale,
              top: size * _ratingOffsetScale,
              width: size * _ratingScale,
              height: size * _ratingScale,
              child: HoverTip(
                message: tr('예상 난이도: ${rated.name}', 'Expected difficulty: ${rated.name}'),
                child: _Shadowed(child: NetworkIcon(rated.icon, size: size * _ratingScale)),
              ),
            ),
          for (final (index, curation) in curations.indexed)
            _positioned(
              angle: angles[index],
              radius: radius,
              iconSize: iconSize,
              child: HoverTip(
                message: tr('큐레이션: ${curation.name}', 'Curation: ${curation.name}'),
                child: _Shadowed(child: NetworkIcon(curation.icon, size: iconSize)),
              ),
            ),
          // 웹(.base-score-wrapper)처럼 아이콘 위쪽 가운데에 글자만 겹친다. 글자 높이의 85%만큼 위로 올린다.
          if (baseScore != null)
            Positioned(
              left: -size,
              right: -size,
              top: 0,
              child: FractionalTranslation(
                translation: const Offset(0, -0.85),
                child: Center(child: _BaseScoreBadge(score: baseScore)),
              ),
            ),
        ],
      ),
    );
  }

  /// 가운데를 기준으로 [angle]도 방향, [radius] 거리에 놓는다. 0도가 오른쪽, 90도가 아래.
  Widget _positioned({required double angle, required double radius, required double iconSize, required Widget child}) {
    final radians = angle * pi / 180;
    return Positioned(
      left: size / 2 + radius * cos(radians) - iconSize / 2,
      top: size / 2 + radius * sin(radians) - iconSize / 2,
      width: iconSize,
      height: iconSize,
      child: child,
    );
  }
}

/// 난이도 기본값 대신 이 레벨에 정해진 기반 점수(PP).
class _BaseScoreBadge extends StatelessWidget {
  const _BaseScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 웹과 같은 모양: 10px, 굵기 600, 불투명도 0.9, 둘레에 검은 그림자(10px).
    return HoverTip(
      message: tr(
        '기반 점수 변동: ${formatNumber(score)} PP (난이도 기본 점수 대신 적용됩니다)',
        "Base score override: ${formatNumber(score)} PP (used instead of the difficulty's base score)",
      ),
      child: Text(
        '$score PP',
        maxLines: 1,
        softWrap: false,
        // 글자 크기 설정을 크게 해 둬도 아이콘을 가리지 않게 크기를 고정한다.
        textScaler: TextScaler.noScaling,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.9),
          fontWeight: FontWeight.w600,
          fontSize: 10,
          height: 1.2,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 10),
            Shadow(color: Colors.black, blurRadius: 4),
          ],
        ),
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.level, required this.compact});

  /// 줄마다 높이를 고정해서 카드가 달라도 제목과 태그가 같은 자리에 온다.
  static const titleLine = 26.0;
  static const subtitleLine = 22.0;
  static const tagLine = 20.0;

  /// 작곡가 줄과 태그 줄 사이. 태그 아이콘이 글자보다 커서 붙어 보이지 않게 조금 띄운다.
  static const tagGap = 4.0;

  /// 간략히 보기의 두 줄. 글자 한 줄 높이(20)에 맞춘다.
  static const compactLine = 20.0;

  final Level level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 웹과 같은 순서: 위에 "#번호 - 작곡가", 아래에 곡 이름.
    final subtitle = [
      ['#${level.id}', if (level.artist.isNotEmpty) level.artist].join(' - '),
      // 뱃지를 넣을 자리가 없는 간략히 보기에서는 여기에 적는다.
      if (compact && level.baseScoreOverride != null) '${level.baseScoreOverride} PP',
    ].join('  ·  ');

    final title = SlideOverflow(
      child: slidingText(level.song, style: compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium),
    );
    final subtitleText = SlideOverflow(
      child: slidingText(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: compactLine, child: subtitleText),
          Row(
            children: [
              // 남는 자리를 곡 이름이 먼저 쓰고, 태그와 시간·타일·BPM은 오른쪽에 붙는다.
              Expanded(
                child: SizedBox(height: compactLine, child: title),
              ),
              if (level.tags.isNotEmpty) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  height: tagLine,
                  child: _Tags(tags: level.tags),
                ),
              ],
              const SizedBox(width: 16),
              _Meta(level: level),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: subtitleLine,
          child: Align(alignment: Alignment.centerLeft, child: subtitleText),
        ),
        SizedBox(
          height: titleLine,
          child: Align(alignment: Alignment.centerLeft, child: title),
        ),
        const SizedBox(height: tagGap),
        SizedBox(
          height: tagLine,
          child: Row(
            children: [
              Expanded(child: level.tags.isEmpty ? const SizedBox.shrink() : _Tags(tags: level.tags)),
              const SizedBox(width: 16),
              _Meta(level: level),
            ],
          ),
        ),
      ],
    );
  }
}

/// 시간, 타일 수, BPM. 태그와 같은 줄에서 오른쪽 끝에 붙고, 값 사이 간격은 항상 같다.
/// 값 길이에 맞춰 폭을 쓰므로 "486.06 BPM" 같은 긴 값도 잘리지 않는다.
class _Meta extends StatelessWidget {
  const _Meta({required this.level});

  /// 값 사이 간격.
  static const _gap = 16.0;

  /// 아주 긴 값이 겹칠 때만 줄여서 넣기 위한 최대 폭.
  static const _maxWidth = 260.0;

  final Level level;

  @override
  Widget build(BuildContext context) {
    final length = level.length;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MetaValue(
              icon: Icons.schedule,
              text: length == null ? null : formatDuration(length),
              tooltip: tr('길이', 'Length'),
            ),
            const SizedBox(width: _gap),
            _MetaValue(
              icon: Icons.linear_scale,
              text: level.tilecount == null ? null : formatNumber(level.tilecount!),
              tooltip: tr('타일 수', 'Tiles'),
            ),
            const SizedBox(width: _gap),
            _MetaValue(
              icon: Icons.music_note_outlined,
              text: level.bpm == null ? null : '${formatBpm(level.bpm!)} BPM',
              tooltip: 'BPM',
            ),
          ],
        ),
      ),
    );
  }
}

/// 레벨 태그 아이콘들. 칸을 넘치면 제목·제작자와 같은 방식으로 옆으로 미끄러진다.
class _Tags extends StatelessWidget {
  const _Tags({required this.tags});

  final List<LevelTag> tags;

  // 테를 두른 태그 아이콘이 많아 그리기가 비싸다. 한 장으로 구워 두고 스크롤할 때는 그것만 그린다.
  @override
  Widget build(BuildContext context) => RasterSnapshot(
    child: SlideOverflow(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tag in tags)
            // 태그마다 테 자리(양옆 1)를 두므로, 보이는 간격이 전과 같게(4) 2만 띄운다.
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _TagBadge(tag: tag),
            ),
        ],
      ),
    ),
  );
}

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.tag});

  static const size = 18.0;

  final LevelTag tag;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(tag.color) ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final Widget badge = tag.icon != null
        ? NetworkIcon(tag.icon, size: size)
        : CircleAvatar(
            radius: size / 2,
            backgroundColor: color.withValues(alpha: 0.3),
            child: Text(
              tag.name.isEmpty ? '?' : tag.name.substring(0, 1).toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
            ),
          );
    final score = tag.isCommunity ? (tag.score ?? 0).clamp(0.0, 1.0) : null;
    // 웹(communityTagHoverTitle)처럼 커뮤니티 태그는 신뢰도도 보여준다.
    final message = [
      tag.name,
      if (tag.description case final text? when text.trim().isNotEmpty) text.trim(),
      if (score != null) '${(score * 100).round()}%',
    ].join(' — ');
    // 테 자리를 모든 태그가 똑같이 비워 둔다. 테가 줄 밖으로 잘리지 않고, 태그 사이 간격도 같게 보인다.
    return HoverTip(
      message: message,
      child: score == null
          ? Padding(padding: const EdgeInsets.all(TagConfidenceOutline.stroke), child: badge)
          : TagConfidenceOutline(score: score, size: size, iconUrl: tag.icon, child: badge),
    );
  }
}

/// 커뮤니티 태그의 신뢰도 테 (웹의 TagConfidenceBar).
///
/// 웹은 태그 둘레에 둥근 네모를 그려서 아이콘 모양과 어긋난다. 여기서는 아이콘 자체의 모양을 따라
/// 바깥으로 [stroke]만큼 초록 테를 두르고, 신뢰도만큼만 채운다.
/// 채우는 방향도 웹과 같다: 오른쪽 아래(시계 135°)에서 끝나고, 신뢰도만큼 시계 반대 방향으로 거슬러 올라간다.
///
/// 테는 아이콘 그림을 초록으로 칠해 둘레로 조금씩 밀어 [_copies]번 그리고, 신뢰도만큼의 부채꼴로 잘라 낸 것이다.
/// 아이콘 하나하나가 매끄럽게 그려지므로 테 가장자리도 매끄럽고 둥글다.
/// 섞기 레이어 없이 캔버스에 바로 그려서 가볍고, 목록이 이 줄을 한 장으로 구울 때도 그대로 구워진다.
/// 아이콘이 없는 태그(글자 동그라미)는 동그라미 둘레에 호를 그린다.
/// 테 자리까지 이 위젯의 크기에 들어가므로 ([size] + 2×[stroke]) 줄 밖으로 잘리지 않는다.
class TagConfidenceOutline extends StatefulWidget {
  const TagConfidenceOutline({super.key, required this.score, required this.size, required this.child, this.iconUrl});

  /// 0~1.
  final double score;

  /// 아이콘 크기 ([child]의 크기).
  final double size;

  /// 테 모양을 딸 아이콘. 없으면 동그라미 둘레에 그린다.
  final String? iconUrl;
  final Widget child;

  /// 테 두께.
  static const stroke = 1.0;

  /// 웹과 같은 색 (#0f0).
  static const color = Color(0xFF00FF00);

  @override
  State<TagConfidenceOutline> createState() => _TagConfidenceOutlineState();
}

class _TagConfidenceOutlineState extends State<TagConfidenceOutline> {
  ImageStream? _stream;
  ImageInfo? _image;
  late final _listener = ImageStreamListener((info, _) {
    if (!mounted) return;
    setState(() {
      _image?.dispose();
      _image = info;
    });
  }, onError: (_, _) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(TagConfidenceOutline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconUrl != widget.iconUrl || oldWidget.size != widget.size) _resolve();
  }

  /// 아이콘이 쓰는 것과 같은 그림(같은 캐시 항목)을 받아 테 모양을 딴다.
  void _resolve() {
    final url = widget.iconUrl;
    final stream = url == null
        ? null
        : NetworkIcon.provider(context, url, widget.size).resolve(createLocalImageConfiguration(context));
    if (stream?.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream?..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const stroke = TagConfidenceOutline.stroke;
    final box = widget.size + stroke * 2;
    return SizedBox.square(
      dimension: box,
      child: CustomPaint(
        painter: widget.score <= 0
            ? null
            : _ConfidenceRingPainter(
                score: widget.score.clamp(0.0, 1.0),
                image: widget.iconUrl == null ? null : _image?.image,
                circle: widget.iconUrl == null,
              ),
        child: Padding(padding: const EdgeInsets.all(stroke), child: widget.child),
      ),
    );
  }
}

class _ConfidenceRingPainter extends CustomPainter {
  _ConfidenceRingPainter({required this.score, required this.image, required this.circle});

  final double score;
  final ui.Image? image;
  final bool circle;

  static const _copies = 8;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = TagConfidenceOutline.stroke;
    const color = TagConfidenceOutline.color;
    final center = size.center(Offset.zero);
    // 웹의 conic-gradient는 위(12시)에서 시계 방향으로 재고, 캔버스 각도는 오른쪽(3시)에서 잰다.
    // 웹: (135° - 신뢰도×360°)에서 시작해 135°에서 끝난다 → 캔버스: (45° - 신뢰도×360°)에서 시작.
    final start = (45 - score * 360) * pi / 180;
    final sweep = score * 2 * pi;

    if (circle) {
      // 글자 동그라미 둘레에 호를 그린다.
      final radius = size.shortestSide / 2 - stroke / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..isAntiAlias = true,
      );
      return;
    }

    final image = this.image;
    if (image == null) return;

    canvas.save();
    if (score < 1) {
      // 신뢰도만큼의 부채꼴만 남긴다. 반지름은 칸을 넉넉히 덮을 만큼.
      final reach = size.longestSide;
      canvas.clipPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(Rect.fromCircle(center: center, radius: reach), start, sweep, false)
          ..close(),
      );
    }
    final inner = size.width - stroke * 2;
    final source = Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    final paint = Paint()
      ..colorFilter = const ColorFilter.mode(color, BlendMode.srcIn)
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    for (var i = 0; i < _copies; i++) {
      final angle = 2 * pi * i / _copies;
      final topLeft = Offset(stroke + stroke * cos(angle), stroke + stroke * sin(angle));
      // 아이콘이 칸 안에서 비율을 지키며 가운데 놓이는 것(BoxFit.contain)과 같은 자리에 그린다.
      final fitted = applyBoxFit(BoxFit.contain, source.size, Size.square(inner));
      final dst = Alignment.center.inscribe(fitted.destination, topLeft & Size.square(inner));
      canvas.drawImageRect(image, source, dst, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConfidenceRingPainter old) => old.score != score || old.image != image || old.circle != circle;
}

/// 시간, 타일 수, BPM 한 칸. 값이 없으면 흐린 '-'로 자리를 지킨다.
class _MetaValue extends StatelessWidget {
  const _MetaValue({required this.icon, required this.text, required this.tooltip});

  final IconData icon;
  final String? text;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Opacity(
      opacity: text == null ? 0.35 : 1,
      child: HoverTip(
        message: tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: muted),
            const SizedBox(width: 4),
            Text(text ?? '-', maxLines: 1, softWrap: false, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}

class _CreatorInfo extends StatelessWidget {
  const _CreatorInfo({required this.level, required this.compact});

  final Level level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creator = level.creatorDisplay ?? tr('제작자 정보 없음', 'No creator info');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          Text(
            tr('제작자', 'Creator'),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        SizedBox(
          height: 20,
          child: HoverTip(
            message: creator,
            child: SlideOverflow(child: slidingText(creator, style: theme.textTheme.bodyMedium)),
          ),
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.level});

  final Level level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return Row(
      spacing: 12,
      children: [
        // 클리어가 없으면 자리는 유지한 채 숨긴다 (열 정렬 유지).
        Opacity(
          opacity: level.clears > 0 ? 1 : 0,
          child: HoverTip(
            message: tr(
              '클리어 ${formatNumber(level.uniqueClears)}명 (총 ${formatNumber(level.clears)}회)',
              "Cleared by ${formatNumber(level.uniqueClears)} ${plural(level.uniqueClears, 'player')} (${formatNumber(level.clears)} total)",
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag_outlined, size: 16, color: iconColor),
                const SizedBox(width: 4),
                Text(formatNumber(level.uniqueClears), style: theme.textTheme.labelLarge),
              ],
            ),
          ),
        ),
        if (level.likes > 0)
          HoverTip(
            message: tr('좋아요', 'Likes'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border, size: 16, color: iconColor),
                const SizedBox(width: 4),
                Text(formatNumber(level.likes), style: theme.textTheme.labelLarge),
              ],
            ),
          ),
      ],
    );
  }
}

class _Links extends StatelessWidget {
  const _Links({required this.level});

  final Level level;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final video = level.videoLink;
    final workshop = level.workshopLink;

    // 칸마다 자리를 정해 둔다. 창작마당 링크가 없어도 영상 단추는 같은 자리에 있다.
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox.square(
          dimension: 44,
          child: video == null
              ? null
              : HoverTip(
                  message: tr('영상 보기', 'Watch video'),
                  child: IconButton(
                    onPressed: () => app.openLink(video),
                    icon: const Icon(Icons.smart_display_outlined),
                  ),
                ),
        ),
        SizedBox.square(
          dimension: 44,
          child: workshop == null
              ? null
              : HoverTip(
                  message: tr('스팀 창작마당', 'Steam Workshop'),
                  child: IconButton(
                    onPressed: () => app.openLink(workshop),
                    icon: const Icon(Icons.sports_esports_outlined),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 받기 단추 밑의 작은 줄: 사이트에서 받은 횟수와 zip 크기.
/// 크기는 목록 응답에 없어서 카드가 보일 때 따로 묻는다. 묻는 동안에는 횟수만 보인다.
class _DownloadInfo extends StatelessWidget {
  const _DownloadInfo({required this.level});

  final Level level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: muted);
    final sizes = AppScope.of(context).levelSizes;
    final count = level.downloadCount;

    return FutureBuilder<int?>(
      // 이미 아는 크기면 기다리지 않는다. 모르는 CDN 레벨만 묻는다.
      future: LevelDownloader.isTufCdnLink(level.dlLink) ? sizes.resolve(level) : null,
      initialData: sizes.peek(level),
      builder: (context, snapshot) {
        final size = snapshot.data;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (count > 0)
              HoverTip(
                message: tr('받은 횟수', 'Downloads'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_outlined, size: 14, color: muted),
                    const SizedBox(width: 3),
                    Text(formatNumber(count), style: style),
                  ],
                ),
              ),
            if (count > 0 && size != null) Text('  ·  ', style: style),
            if (size != null)
              HoverTip(
                message: tr('레벨 파일 크기', 'Level file size'),
                child: Text(formatBytes(size), style: style),
              ),
          ],
        );
      },
    );
  }
}

class _InstallButton extends StatelessWidget {
  const _InstallButton({required this.level});

  final Level level;

  @override
  Widget build(BuildContext context) {
    final installs = AppScope.of(context).installs;

    return ListenableBuilder(
      listenable: installs,
      builder: (context, _) {
        final job = installs.jobFor(level.id);
        final state = installs.stateOf(level);

        // 받기 → 진행률 → 받음 으로 바뀔 때 흐려지며 넘어간다.
        return FadeSwitcher(
          scale: true,
          child: KeyedSubtree(
            key: ValueKey(job != null ? 'job' : state),
            child: job != null ? JobProgressIndicator(job: job) : _buttonFor(installs, state),
          ),
        );
      },
    );
  }

  Widget _buttonFor(InstallCenter installs, LevelInstallState state) {
    return switch (state) {
      LevelInstallState.notInstalled => HoverTip(
        message: tr('라이브러리에 받기', 'Download to library'),
        child: FilledButton.icon(
          onPressed: () => installs.install(level),
          icon: const Icon(Icons.download),
          label: Text(tr('받기', 'Download')),
        ),
      ),
      LevelInstallState.updateAvailable => HoverTip(
        message: tr('새 버전으로 업데이트', 'Update to the new version'),
        child: FilledButton.tonalIcon(
          onPressed: () => installs.install(level),
          icon: const Icon(Icons.update),
          label: Text(tr('업데이트', 'Update')),
        ),
      ),
      LevelInstallState.installed => HoverTip(
        message: tr('이미 받은 레벨입니다', 'Already downloaded'),
        child: OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.check), label: Text(tr('받음', 'Downloaded'))),
      ),
      LevelInstallState.notDownloadable => HoverTip(
        message: tr('TUF에서 직접 받을 수 있는 파일이 없습니다', 'No file to download directly from TUF'),
        child: TextButton(onPressed: null, child: Text(tr('링크 없음', 'No link'))),
      ),
    };
  }
}

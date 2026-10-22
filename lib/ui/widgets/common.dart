import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/image_cache_store.dart';
import '../../core/l10n.dart';
import 'hover_tip.dart';

/// 난이도/태그 아이콘. 받지 못하면 빈 자리만 남긴다.
class NetworkIcon extends StatefulWidget {
  const NetworkIcon(this.url, {super.key, required this.size, this.fallback, this.opacity = 1});

  final String? url;
  final double size;

  /// [url]을 열지 못하면 대신 그릴 그림 (예: 프로필 사진이 지워졌으면 디스코드 사진).
  final String? fallback;

  /// 그림의 투명도 (0~1). 레이어를 만들지 않고 그림을 그릴 때 바로 입힌다.
  final double opacity;

  /// [NetworkIcon]이 그리는 것과 같은 그림. 미리 불러 둘 때([precache]) 같은 캐시 항목을 쓰도록 한곳에서 정한다.
  ///
  /// 원본은 800~1300px이지만 화면에는 작게 나오므로, 보이는 크기로만 디코딩한다.
  /// 그래야 메모리 캐시에 오래 남아 목록을 오르내려도 다시 받지 않는다.
  /// 카드가 소수점 위치에 놓여도 흐릿해지지 않게 두 배로 받아 두고 그릴 때 줄인다.
  static ImageProvider provider(BuildContext context, String url, double size) =>
      DiskCachedImage(url, maxWidth: (size * MediaQuery.devicePixelRatioOf(context) * 2).ceil());

  /// 아이콘들을 미리 불러 둔다. 다 준비되면 끝난다 (실패한 것은 건너뛴다).
  /// 나타나는 애니메이션을 그림이 준비된 뒤에 시작해야 빈칸만 움직이다가 그림이 툭 생기지 않는다.
  static Future<void> precache(BuildContext context, Iterable<String?> urls, double size) => Future.wait([
    for (final url in urls.whereType<String>().toSet())
      precacheImage(provider(context, url, size), context, onError: (_, _) {}),
  ]);

  @override
  State<NetworkIcon> createState() => _NetworkIconState();
}

class _NetworkIconState extends State<NetworkIcon> with SingleTickerProviderStateMixin {
  /// 처음 받을 때만 살짝 나타난다. 이미 받아 둔 아이콘은 바로 그린다.
  /// 투명도는 그림을 그릴 때 바로 입힌다. AnimatedOpacity처럼 레이어를 만들면 아이콘이 많은 목록에서
  /// 그리기가 무거워지고, 한 장으로 구워 두는 줄([RasterSnapshot])에서 반쯤 나타난 채로 굳을 수 있다.
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  late final _curve = CurvedAnimation(parent: _fade, curve: Curves.easeOut);
  bool _shown = false;

  @override
  void dispose() {
    _curve.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _onFrame(bool synchronous) {
    if (_shown) return;
    _shown = true;
    if (synchronous) {
      _fade.value = 1;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fade.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.url;
    final size = widget.size;
    if (src == null) return SizedBox.square(dimension: size);

    final opacity = widget.opacity;
    return Image(
      image: NetworkIcon.provider(context, src, size),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      isAntiAlias: true,
      gaplessPlayback: true,
      opacity: opacity >= 1 ? _curve : _curve.drive(Tween(begin: 0, end: opacity)),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) _onFrame(wasSynchronouslyLoaded);
        return child;
      },
      errorBuilder: (context, error, stackTrace) => widget.fallback == null
          ? SizedBox.square(dimension: size)
          : NetworkIcon(widget.fallback, size: size, opacity: opacity),
    );
  }
}

/// 국가 코드를 국기 그림으로 보여준다 (예: "KR").
///
/// Windows는 국기 이모지를 글자 두 개로만 그려서, 그림을 받아 쓴다. 받은 그림은 아이콘들과 같이 캐시에 남는다.
class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.country, this.height = 14});

  final String? country;
  final double height;

  @override
  Widget build(BuildContext context) {
    final code = country?.trim().toLowerCase();
    if (code == null || code.length != 2) return const SizedBox.shrink();

    return HoverTip(
      message: country!.toUpperCase(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Image(
          image: DiskCachedImage(
            'https://flagcdn.com/w40/$code.png',
            maxWidth: (height * MediaQuery.devicePixelRatioOf(context) * 2).ceil(),
          ),
          height: height,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// 받는 중일 때 받기 버튼 자리에 보여주는 진행률과 취소 버튼.
class JobProgressIndicator extends StatelessWidget {
  const JobProgressIndicator({super.key, required this.job});

  final InstallJob job;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: job,
    builder: (context, _) => Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 진행률은 100ms마다 갱신되므로 사이를 부드럽게 채운다.
              if (job.fraction case final fraction?)
                TweenAnimationBuilder<double>(
                  tween: Tween(end: fraction),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, value, _) => LinearProgressIndicator(value: value),
                )
              else
                const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(job.shortText, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        IconButton(
          tooltip: tr('취소', 'Cancel'),
          visualDensity: VisualDensity.compact,
          onPressed: job.cancel,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

/// 목록 맨 아래: 다음 묶음을 받지 못했을 때. 저절로 다시 받지 않고 사용자가 누를 때만 다시 시도한다.
class LoadMoreError extends StatelessWidget {
  const LoadMoreError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('더 불러오지 못했어요', "Couldn't load more"),
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(tr('다시 시도', 'Retry')),
          ),
        ],
      ),
    );
  }
}

/// 비어 있거나 불러오지 못했을 때의 안내.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final Widget icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(
          data: IconThemeData(size: 40, color: theme.colorScheme.onSurfaceVariant),
          child: icon,
        ),
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    );
  }
}

/// 모든 화면의 내용 최대 폭 (양옆 여백 24를 포함). 내용은 1152까지 넓어진다.
const pageMaxWidth = 1200.0;

/// 1234567 → "1,234,567"
String formatNumber(int value) => value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');

/// 웹 formatDuration과 같은 형식: "02:15", "1:02:15"
String formatDuration(Duration duration) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
}

/// 120.0 → "120", 128.5 → "128.5"
String formatBpm(double bpm) =>
    bpm == bpm.roundToDouble() ? bpm.toInt().toString() : bpm.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// 67016.0 → "67,016.00" (웹 리더보드와 같이 소수점 두 자리까지)
String formatScore(double score) {
  final text = score.toStringAsFixed(2);
  final dot = text.indexOf('.');
  return formatNumber(int.parse(text.substring(0, dot))) + text.substring(dot);
}

/// 0.9883 → "98.83%"
String formatAccuracy(double accuracy) => '${(accuracy * 100).toStringAsFixed(2)}%';

/// 1.0 → "1", 1.25 → "1.25"
String formatSpeed(double speed) => speed == speed.roundToDouble() ? speed.toInt().toString() : speed.toString();

/// 2026-05-05 → "2026년 5월 5일" / "May 5, 2026". 모르면 빈 문자열.
String formatDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  return formatLongDate(local);
}

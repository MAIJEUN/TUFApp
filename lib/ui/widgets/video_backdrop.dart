import 'package:flutter/material.dart';

import '../../app/controllers.dart';
import '../../core/image_cache_store.dart';
import 'motion.dart';

/// 카드 배경에 까는 영상 썸네일. 살짝 흐리게 하고 25%만 비치게 해서 글자가 잘 읽히게 한다.
class VideoBackdrop extends StatelessWidget {
  const VideoBackdrop({super.key, required this.videoLink, required this.hovered});

  static const _opacity = 0.25;
  static const _hoveredOpacity = 0.35;

  /// 배경은 이 크기로 받아서 미리 흐리게 만들어 둔다.
  /// 그릴 때 흐리게 하면 카드마다 매 프레임 레이어를 합성해야 해서 무겁다.
  /// 카드 폭의 1/6쯤이라, 화면에서는 대략 이 값의 6배 정도로 번진다. 형태는 알아볼 수 있을 만큼만.
  /// 흐린 그림은 작게 둬도 늘렸을 때 티가 나지 않는다. 한 장이 작아야 메모리 캐시에 많이 남아서
  /// 스크롤해서 다시 돌아왔을 때 다시 읽고 흐리게 만드는 일이 없다 (320px이면 한 장에 약 300KB).
  static const _decodeWidth = 192;
  static const _blurSigma = 1.5;

  final String videoLink;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final thumbnails = AppScope.of(context).thumbnails;

    // 이미 찾아 둔 주소면 기다리는 장치 없이 바로 그린다 (스크롤 중 카드마다 Future를 만들지 않도록).
    if (thumbnails.isResolved(videoLink)) {
      final url = thumbnails.peek(videoLink);
      return url == null ? const SizedBox.shrink() : _image(url);
    }

    return FutureBuilder<String?>(
      future: thumbnails.resolve(videoLink),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return const SizedBox.shrink();

        return _image(url);
      },
    );
  }

  Widget _image(String url) => AnimatedOpacity(
    opacity: hovered ? _hoveredOpacity : _opacity,
    duration: Motion.medium,
    curve: Curves.easeOut,
    child: Image(
      image: DiskCachedImage(url, maxWidth: _decodeWidth, blurSigma: _blurSigma),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // 작은 그림을 부드럽게 늘려서 흐린 느낌을 낸다.
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => wasSynchronouslyLoaded
          ? child
          : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: Motion.slow, curve: Curves.easeOut, child: child),
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    ),
  );
}

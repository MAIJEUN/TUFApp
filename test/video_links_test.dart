import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/core/video_links.dart';
import 'package:tufapp/core/video_thumbnails.dart';
import 'package:tufapp/ui/widgets/embedded_video.dart';

/// Video link rules must match the website (utils/videoLink.js).
void main() {
  test('링크가 여러 개면 첫 번째가 대표 영상이다', () {
    const raw = 'https://www.youtube.com/watch?v=xpYUP2sOpQk  https://www.bilibili.com/video/BV1EaHy61EpY';
    expect(VideoLinks.split(raw), hasLength(2));
    expect(VideoLinks.primary(raw), 'https://www.youtube.com/watch?v=xpYUP2sOpQk');
    expect(VideoLinks.providerOf(raw), VideoProvider.youtube);
    expect(VideoThumbnails.youtubeVideoId(raw), 'xpYUP2sOpQk', reason: '썸네일도 대표 영상 것');
    expect(EmbeddedVideo.embedUrl(raw), 'https://www.youtube.com/embed/xpYUP2sOpQk?autoplay=0&rel=0');
  });

  test('YouTube 주소 모양들', () {
    for (final link in [
      'https://youtu.be/xpYUP2sOpQk',
      'https://www.youtube.com/shorts/xpYUP2sOpQk',
      'https://youtube.com/live/xpYUP2sOpQk',
      'https://www.youtube-nocookie.com/embed/xpYUP2sOpQk',
      'https://m.youtube.com/watch?feature=share&v=xpYUP2sOpQk',
    ]) {
      expect(VideoLinks.youtubeId(link), 'xpYUP2sOpQk', reason: link);
    }
    // The start time is passed on to the player.
    expect(VideoLinks.embedUrl('https://youtu.be/xpYUP2sOpQk?t=42'), endsWith('&start=42'));
  });

  test('Bilibili와 Douyin', () {
    expect(
      EmbeddedVideo.embedUrl('https://www.bilibili.com/video/BV1EaHy61EpY?p=1'),
      'https://player.bilibili.com/player.html?isOutside=true&bvid=BV1EaHy61EpY&p=1&autoplay=0',
    );
    expect(VideoLinks.bilibiliId('https://b23.tv/BV1EaHy61EpY'), 'BV1EaHy61EpY');

    const douyin = 'https://www.douyin.com/video/7412345678901234567';
    expect(VideoLinks.providerOf(douyin), VideoProvider.douyin);
    expect(
      EmbeddedVideo.embedUrl(douyin),
      'https://open.douyin.com/player/video?vid=7412345678901234567&autoplay=0&mode=pc',
      reason: 'mode=pc가 없으면 세로 화면으로 뜬다',
    );
    expect(VideoLinks.douyinId('https://www.douyin.com/jingxuan?modal_id=7412345678901234567'), '7412345678901234567');
    expect(VideoLinks.referrerPolicy(douyin), 'unsafe-url');
    expect(VideoLinks.referrerPolicy('https://youtu.be/xpYUP2sOpQk'), 'strict-origin-when-cross-origin');
  });

  test('모르는 사이트는 앱 안에서 재생하지 않는다', () {
    expect(EmbeddedVideo.canPlay('https://example.com/video.mp4'), isFalse);
    expect(EmbeddedVideo.canPlay(null), isFalse);
    expect(EmbeddedVideo.canPlay('   '), isFalse);
  });

  test('레벨의 팀은 teamObject에서도 읽고, 받은 횟수를 읽는다', () {
    // The detail response (/levels/10797) has team null and only teamObject.
    final level = Level.fromJson({
      'id': 10797,
      'song': '777',
      'artist': 'RoughSketch & Camellia',
      'team': null,
      'teamObject': {'id': 57, 'name': 'Team Zeta'},
      'downloadCount': 251,
    });
    expect(level.team, 'Team Zeta');
    expect(level.downloadCount, 251);
  });
}

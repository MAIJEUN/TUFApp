import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/level_manager.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/core/video_thumbnails.dart';

void main() {
  group('레벨 폴더 이름은 "#{id} {제목}"', () {
    String name(int id, String song) => LevelManager.folderNameFor(Level(id: id, song: song, artist: 'artist'));

    test('작곡가는 넣지 않는다', () {
      expect(name(11372, 'QuomodocunquizE 『CROWN』'), '#11372 QuomodocunquizE 『CROWN』');
    });

    test('Windows 폴더 이름에 쓸 수 없는 문자는 _로 바꾼다', () {
      expect(name(1, 'What? A/B: "C"'), '#1 What_ A_B_ _C_');
    });

    test('끝의 점과 공백은 뺀다', () {
      expect(name(2, 'Song...  '), '#2 Song');
    });
  });

  group('YouTube 영상 ID', () {
    const id = 'dwwXMfijo2c';

    test('여러 링크 형식을 읽는다', () {
      for (final link in [
        'https://www.youtube.com/watch?v=$id',
        'https://m.youtube.com/watch?v=$id&t=30s',
        'https://youtu.be/$id?si=abc',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/embed/$id',
        'youtu.be/$id',
      ]) {
        expect(VideoThumbnails.youtubeVideoId(link), id, reason: link);
      }
    });

    test('YouTube가 아니거나 ID가 없으면 null', () {
      for (final link in [
        'https://www.bilibili.com/video/BV1H6eJ6jER5',
        'https://www.youtube.com/channel/UC123',
        'https://www.youtube.com/watch',
        'not a link',
      ]) {
        expect(VideoThumbnails.youtubeVideoId(link), isNull, reason: link);
      }
    });
  });
}

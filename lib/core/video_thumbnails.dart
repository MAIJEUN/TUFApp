import 'tuf_api_client.dart';
import 'video_links.dart';

/// 레벨 영상 링크 → 썸네일 이미지 주소. 한 번 찾은 주소는 앱이 켜져 있는 동안 기억한다.
///
/// YouTube는 영상 ID로 주소를 바로 만들고(요청 없음), 그 밖의 사이트(Bilibili, Douyin)는 TUF API에 묻는다.
/// 링크가 여러 개 이어져 있으면 첫 번째(대표 영상)의 썸네일을 쓴다.
class VideoThumbnails {
  VideoThumbnails(this._api);

  final TufApiClient _api;
  final _pending = <String, Future<String?>>{};
  final _resolved = <String, String?>{};

  /// 이미 찾아 둔 주소. 아직 모르면 null (찾았는데 썸네일이 없는 경우도 null).
  String? peek(String videoLink) => _resolved[videoLink];

  /// 이미 다 찾아 본 주소인지. 화면에서 기다릴 필요가 있는지 판단할 때 쓴다.
  bool isResolved(String videoLink) => _resolved.containsKey(videoLink);

  Future<String?> resolve(String videoLink) {
    if (_resolved.containsKey(videoLink)) return Future.value(_resolved[videoLink]);
    return _pending.putIfAbsent(videoLink, () => _resolve(videoLink));
  }

  Future<String?> _resolve(String videoLink) async {
    try {
      final primary = VideoLinks.primary(videoLink);
      final youtubeId = VideoLinks.youtubeId(primary);
      final url = primary == null
          ? null
          : youtubeId != null
          ? 'https://i.ytimg.com/vi/$youtubeId/hqdefault.jpg'
          : await _api.getVideoThumbnailUrl(primary);
      _resolved[videoLink] = url;
      return url;
    } on TufApiException {
      // 기억하지 않고 넘어가서 다음에 카드가 다시 보일 때 한 번 더 시도한다.
      return null;
    } finally {
      _pending.remove(videoLink);
    }
  }

  /// YouTube 영상 ID. 대표 링크가 YouTube가 아니면 null.
  static String? youtubeVideoId(String link) {
    var text = link.trim();
    // 예전처럼 'youtu.be/…'처럼 주소 앞부분이 빠진 링크도 받아 준다.
    if (text.isNotEmpty && !text.contains('://')) text = 'https://$text';
    return VideoLinks.youtubeId(text);
  }
}

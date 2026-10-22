/// 영상 링크 다루기. 사이트(utils/videoLink.js)와 같은 규칙을 쓴다.
///
/// TUF의 videoLink 칸에는 링크 여러 개가 빈칸으로 이어져 올 수 있다. 첫 번째가 대표 영상이다.
/// 지원하는 곳: YouTube, Bilibili, Douyin.
enum VideoProvider { youtube, bilibili, douyin }

abstract final class VideoLinks {
  static final _youtubeHost = RegExp(r'(^|\.)youtube\.com$|(^|\.)youtube-nocookie\.com$|(^|\.)youtu\.be$');
  static final _bilibiliHost = RegExp(r'(^|\.)bilibili\.com$|(^|\.)b23\.tv$');
  static final _douyinHost = RegExp(r'(^|\.)douyin\.com$|(^|\.)iesdouyin\.com$');

  static final _youtubeIdPatterns = [
    RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
    RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
    RegExp(r'youtube\.com/live/([a-zA-Z0-9_-]{11})'),
    RegExp(r'youtube(?:-nocookie)?\.com/embed/([a-zA-Z0-9_-]{11})'),
    RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
  ];
  static final _bilibiliId = RegExp(r'/(BV[a-zA-Z0-9]+)');
  static final _douyinPath = RegExp(r'/(?:share/(?:video|note)|video)/(\d{15,22})');
  static final _douyinId = RegExp(r'^\d{15,22}$');

  /// 빈칸으로 이어진 링크들을 나눈다.
  static List<String> split(String? raw) =>
      raw == null ? const [] : raw.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();

  /// 대표 영상 (첫 번째 링크). 없으면 null.
  static String? primary(String? raw) => split(raw).firstOrNull;

  static VideoProvider? providerOf(String? raw) {
    final link = primary(raw);
    final uri = link == null ? null : Uri.tryParse(link);
    if (uri == null || !uri.hasScheme) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (_youtubeHost.hasMatch(host)) return VideoProvider.youtube;
    if (_bilibiliHost.hasMatch(host)) return VideoProvider.bilibili;
    if (_douyinHost.hasMatch(host)) return VideoProvider.douyin;
    return null;
  }

  /// YouTube 영상 id (11자). 대표 링크가 YouTube가 아니면 null.
  static String? youtubeId(String? raw) {
    final link = primary(raw);
    if (link == null || providerOf(link) != VideoProvider.youtube) return null;
    for (final pattern in _youtubeIdPatterns) {
      if (pattern.firstMatch(link)?.group(1) case final id?) return id;
    }
    return null;
  }

  /// Bilibili BV id. 대표 링크가 Bilibili가 아니면 null.
  static String? bilibiliId(String? raw) {
    final link = primary(raw);
    if (link == null || providerOf(link) != VideoProvider.bilibili) return null;
    return _bilibiliId.firstMatch(link)?.group(1);
  }

  /// Douyin 영상 id (15~22자리 숫자). 영상·공유·재생기 주소와 modal_id/vid 값에서 꺼낸다.
  static String? douyinId(String? raw) {
    final link = primary(raw);
    if (link == null || providerOf(link) != VideoProvider.douyin) return null;
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    if (_douyinPath.firstMatch(uri.path)?.group(1) case final id?) return id;
    for (final key in const ['modal_id', 'vid']) {
      final value = uri.queryParameters[key];
      if (value != null && _douyinId.hasMatch(value)) return value;
    }
    return null;
  }

  /// 앱 안에서 띄울 재생기 주소. 지원하지 않는 링크면 null.
  static String? embedUrl(String? raw, {bool autoplay = false}) {
    final play = autoplay ? 1 : 0;
    if (youtubeId(raw) case final id?) {
      // 사이트처럼 링크의 시작 시각(t=)을 이어 받는다.
      final start = RegExp(r'[?&]t=(\d+)s?').firstMatch(primary(raw)!)?.group(1);
      return 'https://www.youtube.com/embed/$id?autoplay=$play&rel=0${start == null ? '' : '&start=$start'}';
    }
    if (bilibiliId(raw) case final id?) {
      return 'https://player.bilibili.com/player.html?isOutside=true&bvid=$id&p=1&autoplay=$play';
    }
    // mode=pc가 없으면 공식 재생기가 좁은 칸에서 세로(모바일) 화면으로 뜬다.
    if (douyinId(raw) case final id?) return 'https://open.douyin.com/player/video?vid=$id&autoplay=$play&mode=pc';
    return null;
  }

  /// Douyin 공식 재생기는 보낸 곳(referrer)이 있어야 열린다. 나머지는 사이트와 같이 엄격하게 둔다.
  static String referrerPolicy(String? raw) =>
      providerOf(raw) == VideoProvider.douyin ? 'unsafe-url' : 'strict-origin-when-cross-origin';
}

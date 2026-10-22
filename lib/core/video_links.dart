/// Video link helpers, following the website's rules (utils/videoLink.js).
///
/// TUF's videoLink field may hold several links separated by spaces; the first one is the main video.
/// Supported: YouTube, Bilibili, Douyin.
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

  /// Splits space-separated links.
  static List<String> split(String? raw) =>
      raw == null ? const [] : raw.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();

  /// The main video (first link), or null.
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

  /// YouTube video id (11 characters), or null if the main link isn't YouTube.
  static String? youtubeId(String? raw) {
    final link = primary(raw);
    if (link == null || providerOf(link) != VideoProvider.youtube) return null;
    for (final pattern in _youtubeIdPatterns) {
      if (pattern.firstMatch(link)?.group(1) case final id?) return id;
    }
    return null;
  }

  /// Bilibili BV id, or null if the main link isn't Bilibili.
  static String? bilibiliId(String? raw) {
    final link = primary(raw);
    if (link == null || providerOf(link) != VideoProvider.bilibili) return null;
    return _bilibiliId.firstMatch(link)?.group(1);
  }

  /// Douyin video id (15–22 digits), taken from video, share or player URLs and modal_id/vid parameters.
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

  /// Player URL to embed in the app, or null for unsupported links.
  static String? embedUrl(String? raw, {bool autoplay = false}) {
    final play = autoplay ? 1 : 0;
    if (youtubeId(raw) case final id?) {
      // Keep the link's start time (t=), like the website.
      final start = RegExp(r'[?&]t=(\d+)s?').firstMatch(primary(raw)!)?.group(1);
      return 'https://www.youtube.com/embed/$id?autoplay=$play&rel=0${start == null ? '' : '&start=$start'}';
    }
    if (bilibiliId(raw) case final id?) {
      return 'https://player.bilibili.com/player.html?isOutside=true&bvid=$id&p=1&autoplay=$play';
    }
    // Without mode=pc the official player shows the vertical mobile layout in a narrow box.
    if (douyinId(raw) case final id?) return 'https://open.douyin.com/player/video?vid=$id&autoplay=$play&mode=pc';
    return null;
  }

  /// The official Douyin player only opens with a referrer. Everything else stays strict, like the website.
  static String referrerPolicy(String? raw) =>
      providerOf(raw) == VideoProvider.douyin ? 'unsafe-url' : 'strict-origin-when-cross-origin';
}

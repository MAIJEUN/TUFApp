import 'tuf_api_client.dart';
import 'video_links.dart';

/// Level video link → thumbnail URL, remembered while the app runs.
///
/// YouTube URLs are built from the video id (no request); other sites
/// (Bilibili, Douyin) are looked up through the TUF API.
/// With several links, the thumbnail of the first (main) video is used.
class VideoThumbnails {
  VideoThumbnails(this._api);

  final TufApiClient _api;
  final _pending = <String, Future<String?>>{};
  final _resolved = <String, String?>{};

  /// The resolved URL, or null if not resolved yet (also null when there is no thumbnail).
  String? peek(String videoLink) => _resolved[videoLink];

  /// Whether the link was already looked up, so the page knows whether to wait.
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
      // Not cached; tried again the next time the card appears.
      return null;
    } finally {
      _pending.remove(videoLink);
    }
  }

  /// YouTube video id, or null if the main link isn't YouTube.
  static String? youtubeVideoId(String link) {
    var text = link.trim();
    // Also accept links without a scheme, like 'youtu.be/…'.
    if (text.isNotEmpty && !text.contains('://')) text = 'https://$text';
    return VideoLinks.youtubeId(text);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';

import '../../core/video_links.dart';

/// Plays videos inside the app (YouTube, Bilibili and Douyin players in Edge WebView2 on Windows).
///
/// Calls [onUnavailable] if the player can't be shown; the caller then opens the browser instead.
class EmbeddedVideo extends StatefulWidget {
  const EmbeddedVideo({super.key, required this.videoLink, required this.onUnavailable, this.autoplay = false});

  final String videoLink;
  final VoidCallback onUnavailable;

  /// Starts playing immediately. By default, like the website, the player just loads and the user presses play.
  final bool autoplay;

  /// Whether the video can play in the app (YouTube, Bilibili, Douyin).
  static bool canPlay(String? videoLink) => embedUrl(videoLink) != null;

  /// Player URL for the first (main) link, or null for sites that can't play in the app.
  static String? embedUrl(String? videoLink, {bool autoplay = false}) =>
      VideoLinks.embedUrl(videoLink, autoplay: autoplay);

  @override
  State<EmbeddedVideo> createState() => _EmbeddedVideoState();
}

class _EmbeddedVideoState extends State<EmbeddedVideo> {
  final _controller = WebviewController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final url = EmbeddedVideo.embedUrl(widget.videoLink, autoplay: widget.autoplay);
    try {
      // Some Windows installs lack WebView2; fall back to the browser then.
      if (url == null || await WebviewController.getWebViewVersion() == null) {
        if (mounted) widget.onUnavailable();
        return;
      }

      // Opening the player URL directly makes YouTube fail with "Error 153" because it can't verify the origin.
      // Like the website, it has to be opened in an iframe on a page from our own origin.
      final page = await _writePlayerPage(url, VideoLinks.referrerPolicy(widget.videoLink));

      await _controller.initialize();
      // Keep the player from opening new windows (ads or "Watch on ...").
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.addVirtualHostNameMapping(_host, p.dirname(page), WebviewHostResourceAccessKind.allow);
      await _controller.loadUrl('https://$_host/${p.basename(page)}');
      if (mounted) setState(() => _ready = true);
    } on Exception {
      if (mounted) widget.onUnavailable();
    }
  }

  /// Fake host used only inside the app; the page on it hosts the player.
  static const _host = 'player.tufapp.local';

  /// Writes the page hosting the player to a temp folder and returns its path.
  /// The level and pass pages can be open on top of each other, so each video gets its own file.
  Future<String> _writePlayerPage(String embedUrl, String referrerPolicy) async {
    final folder = await Directory(p.join(Directory.systemTemp.path, 'tufapp-player')).create(recursive: true);
    final page = File(p.join(folder.path, 'player-${embedUrl.hashCode.toUnsigned(32)}.html'));
    await page.writeAsString('''
<!DOCTYPE html>
<html>
  <head><meta charset="utf-8"><style>
    html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
    iframe { border: 0; width: 100%; height: 100%; display: block; }
  </style></head>
  <body>
    <iframe src="${const HtmlEscape(HtmlEscapeMode.attribute).convert(embedUrl)}" referrerpolicy="$referrerPolicy" scrolling="no"
      allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe>
  </body>
</html>
''');
    return page.path;
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_ready) Webview(_controller),
      if (!_ready) const Center(child: CircularProgressIndicator()),
    ],
  );
}

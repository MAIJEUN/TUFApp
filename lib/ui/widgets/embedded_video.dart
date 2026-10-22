import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';

import '../../core/video_links.dart';

/// 앱 안에서 영상을 재생한다 (Windows의 Edge WebView2로 YouTube·Bilibili·Douyin 재생기를 띄운다).
///
/// 재생기를 띄울 수 없으면 [onUnavailable]을 부른다. 그럴 때는 부르는 쪽에서 브라우저로 연다.
class EmbeddedVideo extends StatefulWidget {
  const EmbeddedVideo({super.key, required this.videoLink, required this.onUnavailable, this.autoplay = false});

  final String videoLink;
  final VoidCallback onUnavailable;

  /// 켜면 바로 재생한다. 평소에는 웹사이트처럼 재생기만 띄워 두고 재생은 사용자가 누른다.
  final bool autoplay;

  /// 앱 안에서 재생할 수 있는 영상인지 (YouTube, Bilibili, Douyin).
  static bool canPlay(String? videoLink) => embedUrl(videoLink) != null;

  /// 재생기 주소. 링크가 여러 개면 첫 번째(대표 영상). 앱 안에서 재생할 수 없는 사이트면 null.
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
      // WebView2가 깔려 있지 않은 Windows도 있다. 그럴 때는 브라우저로 넘긴다.
      if (url == null || await WebviewController.getWebViewVersion() == null) {
        if (mounted) widget.onUnavailable();
        return;
      }

      // 재생기 주소를 그대로 열면 YouTube가 출처를 확인하지 못해 "오류 153"을 낸다.
      // 웹사이트처럼 우리 쪽 주소의 페이지 안(iframe)에서 열어야 한다.
      final page = await _writePlayerPage(url, VideoLinks.referrerPolicy(widget.videoLink));

      await _controller.initialize();
      // 재생기가 새 창을 띄우지 못하게 막는다 (광고나 '새 탭에서 보기').
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.addVirtualHostNameMapping(_host, p.dirname(page), WebviewHostResourceAccessKind.allow);
      await _controller.loadUrl('https://$_host/${p.basename(page)}');
      if (mounted) setState(() => _ready = true);
    } on Exception {
      if (mounted) widget.onUnavailable();
    }
  }

  /// 앱 안에서만 쓰는 가짜 주소. 이 주소의 페이지가 재생기를 품는다.
  static const _host = 'player.tufapp.local';

  /// 재생기를 품는 페이지를 임시 폴더에 쓰고 그 파일 경로를 돌려준다.
  /// 레벨 화면과 클리어 화면이 겹쳐 열려 있을 수 있어서, 영상마다 다른 파일을 쓴다.
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

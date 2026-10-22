import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 난이도·태그 아이콘과 영상 썸네일을 디스크에 모아 둔다.
/// 앱을 껐다 켜도 다시 받지 않고, 목록을 오르내려도 네트워크를 다시 타지 않는다.
class ImageCacheStore {
  ImageCacheStore._({http.Client? client, Directory? directory})
    : _client = client ?? http.Client(),
      _directory = directory == null ? null : Future.value(directory);

  /// 앱 전체가 함께 쓰는 저장소. 테스트에서는 [ImageCacheStore.forTesting]으로 바꿔 끼운다.
  static ImageCacheStore instance = ImageCacheStore._();

  /// 테스트용: 저장 위치와 클라이언트를 직접 정한다.
  @visibleForTesting
  factory ImageCacheStore.forTesting({required Directory directory, http.Client? client}) =>
      ImageCacheStore._(client: client, directory: directory);

  /// 이만큼 넘으면 오래된 파일부터 지운다.
  static const _maxBytes = 128 * 1024 * 1024;
  static const _targetBytes = 96 * 1024 * 1024;

  final http.Client _client;
  final Map<String, Future<Uint8List>> _inFlight = {};
  Future<Directory>? _directory;
  bool _pruned = false;

  Future<Directory> _dir() => _directory ??= _openDirectory();

  static Future<Directory> _openDirectory() async {
    final appData = Platform.environment['APPDATA'];
    final base = Platform.isWindows && appData != null
        ? p.join(appData, 'TUFApp')
        : (await getApplicationSupportDirectory()).path;
    return Directory(p.join(base, 'image-cache')).create(recursive: true);
  }

  /// 주소를 짧은 파일 이름으로 바꾼다 (같은 주소면 항상 같은 파일).
  /// 주소를 그대로 옮기면 긴 주소(영상 썸네일 등)는 Windows 경로 길이 제한(260자)을 넘어 저장되지 않는다.
  /// FNV-1a 64비트 두 벌(앞에서부터, 뒤에서부터)에 길이를 붙여 겹칠 일이 사실상 없게 한다.
  @visibleForTesting
  static String fileNameFor(String url) {
    final bytes = utf8.encode(url);
    String fnv(Iterable<int> data) {
      var hash = 0xcbf29ce484222325;
      for (final byte in data) {
        hash = (hash ^ byte) * 0x100000001b3;
      }
      // 64비트 값을 부호 없이 16진수 16자리로 적는다.
      return (hash >>> 32).toRadixString(16).padLeft(8, '0') + (hash & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    }

    return '${fnv(bytes)}${fnv(bytes.reversed)}-${bytes.length}';
  }

  /// 캐시에 있으면 파일에서, 없으면 받아서 저장한 뒤 돌려준다. 같은 주소를 동시에 부르면 한 번만 받는다.
  Future<Uint8List> bytesFor(String url) => _inFlight[url] ??= _load(url).whenComplete(() {
    // remove가 돌려주는 값을 그대로 반환하면 자기 자신을 기다리게 되어 영영 끝나지 않는다.
    _inFlight.remove(url);
  });

  Future<Uint8List> _load(String url) async {
    final dir = await _dir();
    final file = File(p.join(dir.path, fileNameFor(url)));

    try {
      if (await file.exists()) {
        final cached = await file.readAsBytes();
        if (cached.isNotEmpty) {
          // 오래된 파일부터 지울 때 쓰도록 마지막 사용 시각을 남긴다.
          unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
          return cached;
        }
      }
    } on FileSystemException {
      // 캐시를 읽지 못하면 그냥 받는다.
    }

    // 멈춘 연결 때문에 그림이 영영 '불러오는 중'으로 남지 않게 한다 (실패하면 다음에 다시 받는다).
    final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 400) {
      throw NetworkImageLoadException(statusCode: response.statusCode, uri: Uri.parse(url));
    }
    final bytes = response.bodyBytes;

    // 쓰다 만 파일이 남지 않게 임시 파일에 썼다가 옮긴다.
    try {
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      // 저장 실패는 무시한다. 이번 실행에서는 메모리 캐시로 충분하다.
    }

    unawaited(_pruneOnce());
    return bytes;
  }

  /// 캐시가 너무 커지면 오래 안 쓴 파일부터 지운다. 실행당 한 번만 확인한다.
  Future<void> _pruneOnce() async {
    if (_pruned) return;
    _pruned = true;

    try {
      final dir = await _dir();
      final files = <({File file, int size, DateTime used})>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        total += stat.size;
        files.add((file: entity, size: stat.size, used: stat.modified));
      }
      if (total <= _maxBytes) return;

      files.sort((a, b) => a.used.compareTo(b.used));
      for (final entry in files) {
        if (total <= _targetBytes) break;
        try {
          await entry.file.delete();
          total -= entry.size;
        } on FileSystemException {
          // 지우지 못한 파일은 건너뛴다.
        }
      }
    } on FileSystemException {
      // 정리에 실패해도 그림 표시에는 지장이 없다.
    }
  }
}

/// 디스크 캐시에서 읽어오는 이미지. [maxWidth]를 주면 그 크기로 줄여서 디코딩한다.
///
/// 원본 아이콘은 800~1300px이라 그대로 디코딩하면 한 장에 2~6MB를 쓴다.
/// 화면에 보이는 크기로 줄이면 수십 KB라, 메모리 캐시에서 밀려나 다시 받는 일이 없어진다.
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url, {this.maxWidth, this.blurSigma = 0});

  final String url;
  final int? maxWidth;

  /// 0보다 크면 이 정도로 흐리게 만들어 둔다.
  /// 그릴 때마다 흐리게 하면 무거우므로, 받아 둔 그림을 한 번만 처리해서 캐시에 담는다.
  final double blurSigma;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(DiskCachedImage key, ImageDecoderCallback decode) {
    if (key.blurSigma > 0) {
      return OneFrameImageStreamCompleter(
        _loadBlurred(key, decode),
        informationCollector: () => [ErrorDescription('주소: ${key.url}')],
      );
    }
    if (key.maxWidth != null) {
      return _FramesCompleter(
        _loadFrames(key, decode),
        debugLabel: key.url,
        informationCollector: () => [ErrorDescription('주소: ${key.url}')],
      );
    }
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode),
      scale: 1,
      debugLabel: key.url,
      informationCollector: () => [ErrorDescription('주소: ${key.url}')],
    );
  }

  Future<ImageInfo> _loadBlurred(DiskCachedImage key, ImageDecoderCallback decode) async {
    final codec = await _loadCodec(key, decode);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final blurred = await _blur(frame.image, key.blurSigma);
    frame.image.dispose();
    return ImageInfo(image: blurred, debugLabel: key.url);
  }

  /// 원본을 그대로 디코딩한 뒤 반씩 여러 번 줄여서 [maxWidth]에 맞춘다.
  ///
  /// 디코더에 바로 작은 크기를 달라고 하면 1000px을 18px로 한 번에 건너뛰며 점을 골라 뽑아서
  /// 가장자리가 계단처럼 깨진다. 반씩 줄이면 매번 주변 네 점을 섞으므로 브라우저처럼 매끄럽다.
  /// GIF처럼 움직이는 그림은 모든 장면을 같은 방법으로 줄여 둔다 (작아서 메모리는 얼마 안 든다).
  Future<List<_Frame>> _loadFrames(DiskCachedImage key, ImageDecoderCallback decode) async {
    final bytes = await ImageCacheStore.instance.bytesFor(key.url);
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    final frames = <_Frame>[];
    try {
      final count = codec.frameCount.clamp(1, _maxFrames);
      for (var i = 0; i < count; i++) {
        final frame = await codec.getNextFrame();
        frames.add((image: await _downscale(frame.image, key.maxWidth!), duration: frame.duration));
      }
    } catch (_) {
      for (final frame in frames) {
        frame.image.dispose();
      }
      rethrow;
    } finally {
      codec.dispose();
    }
    return frames;
  }

  /// 움직이는 그림에서 줄여 둘 최대 장면 수.
  static const _maxFrames = 300;

  /// [source]를 반씩 줄여 폭 [target]에 맞춘다. [source]는 여기서 정리한다.
  Future<ui.Image> _downscale(ui.Image source, int target) async {
    var image = source;
    while (image.width > target) {
      // 두 배 이상 크면 반으로, 그보다 작게 남았으면 마지막으로 딱 맞춘다.
      final width = image.width >= target * 2 ? (image.width / 2).ceil() : target;
      final height = max(1, (image.height * width / image.width).round());
      final smaller = await _resize(image, width, height);
      image.dispose();
      image = smaller;
    }
    return image;
  }

  Future<ui.Image> _resize(ui.Image source, int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      Offset.zero & Size(source.width.toDouble(), source.height.toDouble()),
      Offset.zero & Size(width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// 한 번 흐리게 만들어 둔 그림. 그릴 때는 그대로 쓰기만 한다.
  Future<ui.Image> _blur(ui.Image source, double sigma) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(
      source,
      Offset.zero,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(source.width, source.height);
    } finally {
      picture.dispose();
    }
  }

  Future<ui.Codec> _loadCodec(DiskCachedImage key, ImageDecoderCallback decode) async {
    final bytes = await ImageCacheStore.instance.bytesFor(key.url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final width = key.maxWidth;
    if (width == null) return decode(buffer);
    return decode(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        if (intrinsicWidth <= width) return ui.TargetImageSize(width: intrinsicWidth, height: intrinsicHeight);
        final height = (intrinsicHeight * width / intrinsicWidth).round();
        return ui.TargetImageSize(width: width, height: height);
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage && other.url == url && other.maxWidth == maxWidth && other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(url, maxWidth, blurSigma);

  @override
  String toString() => 'DiskCachedImage("$url", maxWidth: $maxWidth, blurSigma: $blurSigma)';
}

typedef _Frame = ({ui.Image image, Duration duration});

/// 미리 줄여 둔 장면들을 차례로 내보낸다. 한 장이면 그대로 두고, 여러 장이면 GIF처럼 되풀이한다.
/// 보는 곳이 없으면 (화면 밖으로 스크롤되면) 넘기기를 멈춘다.
class _FramesCompleter extends ImageStreamCompleter {
  _FramesCompleter(
    Future<List<_Frame>> frames, {
    required String debugLabel,
    InformationCollector? informationCollector,
  }) {
    this.debugLabel = debugLabel;
    frames.then(
      _onLoaded,
      onError: (Object error, StackTrace stack) => reportError(
        context: ErrorDescription('아이콘을 불러오는 중'),
        exception: error,
        stack: stack,
        informationCollector: informationCollector,
        silent: true,
      ),
    );
  }

  /// 장면 길이가 0에 가까우면 브라우저처럼 0.1초로 본다.
  static const _defaultDelay = Duration(milliseconds: 100);

  List<_Frame>? _frames;
  int _index = 0;
  Timer? _timer;
  bool _gone = false;

  void _onLoaded(List<_Frame> frames) {
    if (_gone) {
      for (final frame in frames) {
        frame.image.dispose();
      }
      return;
    }
    _frames = frames;
    _show();
  }

  void _show() {
    final frames = _frames!;
    setImage(ImageInfo(image: frames[_index].image.clone(), debugLabel: debugLabel));
    _scheduleNext();
  }

  void _scheduleNext() {
    final frames = _frames;
    if (frames == null || frames.length < 2 || !hasListeners || _timer != null || _gone) return;

    final duration = frames[_index].duration;
    _timer = Timer(duration.inMilliseconds <= 10 ? _defaultDelay : duration, () {
      _timer = null;
      if (_gone || !hasListeners) return;
      _index = (_index + 1) % frames.length;
      _show();
    });
  }

  @override
  void addListener(ImageStreamListener listener) {
    super.addListener(listener);
    _scheduleNext();
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void onDisposed() {
    _gone = true;
    _timer?.cancel();
    _timer = null;
    for (final frame in _frames ?? const <_Frame>[]) {
      frame.image.dispose();
    }
    _frames = null;
    super.onDisposed();
  }
}

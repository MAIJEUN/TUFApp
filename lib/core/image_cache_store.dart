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

/// Disk cache for difficulty/tag icons and video thumbnails.
/// Survives restarts and avoids network requests when scrolling back and forth.
class ImageCacheStore {
  ImageCacheStore._({http.Client? client, Directory? directory})
    : _client = client ?? http.Client(),
      _directory = directory == null ? null : Future.value(directory);

  /// Shared instance. Tests swap it with [ImageCacheStore.forTesting].
  static ImageCacheStore instance = ImageCacheStore._();

  /// For tests: custom directory and client.
  @visibleForTesting
  factory ImageCacheStore.forTesting({required Directory directory, http.Client? client}) =>
      ImageCacheStore._(client: client, directory: directory);

  /// Oldest files are deleted beyond this size.
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

  /// Maps a URL to a short file name (the same URL always maps to the same file).
  /// Using the URL as-is breaks long ones (like video thumbnails) on Windows' 260-character path limit.
  /// Two FNV-1a 64-bit hashes (forward and backward) plus the length make collisions practically impossible.
  @visibleForTesting
  static String fileNameFor(String url) {
    final bytes = utf8.encode(url);
    String fnv(Iterable<int> data) {
      var hash = 0xcbf29ce484222325;
      for (final byte in data) {
        hash = (hash ^ byte) * 0x100000001b3;
      }
      // Writes the 64-bit value as 16 unsigned hex digits.
      return (hash >>> 32).toRadixString(16).padLeft(8, '0') + (hash & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    }

    return '${fnv(bytes)}${fnv(bytes.reversed)}-${bytes.length}';
  }

  /// Returns the cached file, or downloads and stores it first. Concurrent calls for the same URL share one download.
  Future<Uint8List> bytesFor(String url) => _inFlight[url] ??= _load(url).whenComplete(() {
    // Returning the future from remove() would make the request wait on itself forever.
    _inFlight.remove(url);
  });

  Future<Uint8List> _load(String url) async {
    final dir = await _dir();
    final file = File(p.join(dir.path, fileNameFor(url)));

    try {
      if (await file.exists()) {
        final cached = await file.readAsBytes();
        if (cached.isNotEmpty) {
          // Record the last use so pruning removes the least recently used files first.
          unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
          return cached;
        }
      }
    } on FileSystemException {
      // Fall back to downloading if the cache can't be read.
    }

    // A stalled connection must not leave an image loading forever (it is retried next time).
    final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 400) {
      throw NetworkImageLoadException(statusCode: response.statusCode, uri: Uri.parse(url));
    }
    final bytes = response.bodyBytes;

    // Write to a temporary file and rename it so no partial file is left behind.
    try {
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      // Ignore write failures; the memory cache is enough for this run.
    }

    unawaited(_pruneOnce());
    return bytes;
  }

  /// Deletes the least recently used files when the cache grows too large. Checked once per run.
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
          // Skip files that can't be deleted.
        }
      }
    } on FileSystemException {
      // Pruning failures don't affect showing images.
    }
  }
}

/// An image read from the disk cache. With [maxWidth], it is decoded at that size.
///
/// Source icons are 800–1300px, so decoding them as-is costs 2–6 MB each.
/// At on-screen size they take tens of KB and stay in the memory cache instead of being evicted and reloaded.
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url, {this.maxWidth, this.blurSigma = 0});

  final String url;
  final int? maxWidth;

  /// If above 0, the image is blurred by this sigma.
  /// Blurring on every paint is expensive, so the downloaded image is blurred once and cached.
  final double blurSigma;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(DiskCachedImage key, ImageDecoderCallback decode) {
    if (key.blurSigma > 0) {
      return OneFrameImageStreamCompleter(
        _loadBlurred(key, decode),
        informationCollector: () => [ErrorDescription('URL: ${key.url}')],
      );
    }
    if (key.maxWidth != null) {
      return _FramesCompleter(
        _loadFrames(key, decode),
        debugLabel: key.url,
        informationCollector: () => [ErrorDescription('URL: ${key.url}')],
      );
    }
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode),
      scale: 1,
      debugLabel: key.url,
      informationCollector: () => [ErrorDescription('URL: ${key.url}')],
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

  /// Decodes at full size, then halves repeatedly down to [maxWidth].
  ///
  /// Asking the decoder for a small size directly samples 1000px down to 18px in one step,
  /// which leaves jagged edges. Halving blends four pixels each step, which looks as smooth as a browser.
  /// Animated images (GIF) get every frame downscaled the same way (they are small, so memory stays low).
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

  /// Maximum number of frames kept for an animated image.
  static const _maxFrames = 300;

  /// Halves [source] down to width [target]. Disposes [source].
  Future<ui.Image> _downscale(ui.Image source, int target) async {
    var image = source;
    while (image.width > target) {
      // Halve while at least twice as large, then make the last step exact.
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

  /// Blurs once; painting just reuses the result.
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

/// Emits the downscaled frames. A single frame stays as is; multiple frames loop like a GIF.
/// Stops advancing when nobody is listening (scrolled off screen).
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
        context: ErrorDescription('while loading an icon'),
        exception: error,
        stack: stack,
        informationCollector: informationCollector,
        silent: true,
      ),
    );
  }

  /// Frame durations close to zero are treated as 0.1 s, like browsers do.
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

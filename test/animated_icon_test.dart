import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/core/image_cache_store.dart';

/// Downscaled icons must still animate when they are GIFs.
void main() {
  late Directory dir;
  late ImageCacheStore original;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tufapp_animated_icon_');
    original = ImageCacheStore.instance;
    ImageCacheStore.instance = ImageCacheStore.forTesting(
      directory: dir,
      client: MockClient((request) async => http.Response.bytes(_twoFrameGif(), 200)),
    );
  });

  tearDown(() async {
    ImageCacheStore.instance = original;
    await dir.delete(recursive: true);
  });

  testWidgets('GIF 아이콘은 줄여서도 장면이 넘어간다', (tester) async {
    final colors = <int>{};
    await tester.runAsync(() async {
      final stream = const DiskCachedImage(
        'https://example.com/icon.gif',
        maxWidth: 1,
      ).resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((info, _) async {
        expect(info.image.width, 1, reason: '폭에 맞춰 줄인다');
        final data = await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        colors.add(data!.getUint32(0));
        info.dispose();
      });
      stream.addListener(listener);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (colors.length < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      stream.removeListener(listener);
    });

    expect(colors, {0xFF0000FF, 0x0000FFFF}, reason: '빨강과 파랑 두 장면이 모두 보인다 (RGBA)');
  });
}

/// A 2×2 GIF alternating a red and a blue frame every 0.1 s.
Uint8List _twoFrameGif() {
  final bytes = BytesBuilder()
    ..add('GIF89a'.codeUnits)
    // 2×2 screen, 2-color palette.
    ..add([2, 0, 2, 0, 0x80, 0, 0])
    ..add([0xFF, 0, 0, 0, 0, 0xFF])
    // Loop forever.
    ..add([0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0]);

  for (final color in [0, 1]) {
    bytes
      ..add([0x21, 0xF9, 4, 0, 10, 0, 0, 0])
      ..add([0x2C, 0, 0, 0, 0, 2, 0, 2, 0, 0])
      ..add([2]);
    final data = _lzw(List.filled(4, color));
    bytes
      ..add([data.length])
      ..add(data)
      ..add([0]);
  }
  bytes.add([0x3B]);
  return bytes.toBytes();
}

/// Uncompressed LZW: a clear code before every pixel keeps the code width at 3 bits.
List<int> _lzw(List<int> pixels) {
  const clear = 4, end = 5, width = 3;
  final codes = [
    for (final pixel in pixels) ...[clear, pixel],
    end,
  ];
  final out = <int>[];
  var buffer = 0, bits = 0;
  for (final code in codes) {
    buffer |= code << bits;
    bits += width;
    while (bits >= 8) {
      out.add(buffer & 0xFF);
      buffer >>= 8;
      bits -= 8;
    }
  }
  if (bits > 0) out.add(buffer & 0xFF);
  return out;
}

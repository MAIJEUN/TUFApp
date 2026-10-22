import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/core/image_cache_store.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('tufapp_image_cache_'));
  tearDown(() async => dir.delete(recursive: true));

  test('한 번 받은 그림은 다시 받지 않는다', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response.bytes(Uint8List.fromList([1, 2, 3, 4]), 200);
    });

    final store = ImageCacheStore.forTesting(directory: dir, client: client);
    const url = 'https://api.tuforums.com/cdn/images/TAG_ICON/abc/original';

    expect(await store.bytesFor(url), [1, 2, 3, 4]);
    expect(requests, 1);

    // Reads from the file, both within the same run and as if the app were restarted.
    expect(await store.bytesFor(url), [1, 2, 3, 4]);
    final restarted = ImageCacheStore.forTesting(directory: dir, client: client);
    expect(await restarted.bytesFor(url), [1, 2, 3, 4]);
    expect(requests, 1, reason: '캐시가 있으면 서버에 다시 묻지 않는다');
    expect(dir.listSync().whereType<File>(), hasLength(1));
  });

  test('동시에 여러 번 부르면 한 번만 받는다', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response.bytes(Uint8List.fromList([9]), 200);
    });

    final store = ImageCacheStore.forTesting(directory: dir, client: client);
    const url = 'https://api.tuforums.com/cdn/images/difficulty_icon/xyz/original';

    await Future.wait([store.bytesFor(url), store.bytesFor(url), store.bytesFor(url)]);
    expect(requests, 1);
  });

  test('받지 못하면 오류를 낸다', () async {
    final client = MockClient((request) async => http.Response('nope', 404));
    final store = ImageCacheStore.forTesting(directory: dir, client: client);

    expect(() => store.bytesFor('https://api.tuforums.com/cdn/images/none'), throwsA(isA<NetworkImageLoadException>()));
  });

  test('같은 주소와 크기면 같은 캐시 항목으로 본다', () {
    const a = DiskCachedImage('https://example.com/a.png', maxWidth: 64);
    const b = DiskCachedImage('https://example.com/a.png', maxWidth: 64);
    const c = DiskCachedImage('https://example.com/a.png', maxWidth: 128);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}

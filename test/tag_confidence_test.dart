import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/core/image_cache_store.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/ui/widgets/common.dart';
import 'package:tufapp/ui/widgets/level_card.dart';
import 'package:tufapp/ui/widgets/raster_snapshot.dart';

void main() {
  test('커뮤니티 태그와 신뢰도를 읽는다', () {
    final community = LevelTag.fromJson({'id': 50, 'name': 'Rolling', 'isCommunity': true, 'score': 0.97});
    expect(community.isCommunity, isTrue);
    expect(community.score, 0.97);

    final staff = LevelTag.fromJson({'id': 1, 'name': 'Filters', 'isCommunity': false, 'score': null});
    expect(staff.isCommunity, isFalse);
    expect(staff.score, isNull);

    // Vote info survives replacing the info from the catalog, as on the packs page.
    final resolved = community.withInfo(name: 'Rolling', icon: 'x');
    expect(resolved.isCommunity, isTrue);
    expect(resolved.score, 0.97);
  });

  /// Rings a 20×20 white square and samples colors where the ring is drawn.
  Future<ui.Image> render(WidgetTester tester, double score) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: TagConfidenceOutline(
                score: score,
                size: 20,
                child: Container(width: 20, height: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() => boundary.toImage()))!;
  }

  Future<Color> pixel(WidgetTester tester, ui.Image image, int x, int y) async {
    final data = (await tester.runAsync(() => image.toByteData()))!;
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  bool isGreen(Color c) => c.a > 0.5 && c.g > 0.8 && c.r < 0.3 && c.b < 0.3;

  testWidgets('신뢰도 25%면 웹처럼 오른쪽(시계 45°~135°)만 채운다', (tester) async {
    final image = await render(tester, 0.25);
    // The widget spans (4,4)–(26,26), the square (5,5)–(25,25), and the ring the 1px outside it.
    expect(isGreen(await pixel(tester, image, 25, 15)), isTrue, reason: '오른쪽 가운데');
    expect(isGreen(await pixel(tester, image, 4, 15)), isFalse, reason: '왼쪽 가운데');
    expect(isGreen(await pixel(tester, image, 15, 4)), isFalse, reason: '위 가운데');
    expect(await pixel(tester, image, 15, 15), Colors.white, reason: '아이콘은 그대로');
  });

  testWidgets('신뢰도 100%면 아이콘 모양을 따라 한 바퀴 다 두른다', (tester) async {
    final image = await render(tester, 1);
    for (final (x, y) in [(25, 15), (4, 15), (15, 4), (15, 25)]) {
      expect(isGreen(await pixel(tester, image, x, y)), isTrue, reason: '($x, $y)');
    }
    // The ring only reaches 1px outside the icon; farther out is empty.
    expect((await pixel(tester, image, 2, 15)).a, lessThan(0.1));
  });

  testWidgets('테까지 위젯 크기 안에 들어간다 (줄 밖으로 잘리지 않는다)', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: TagConfidenceOutline(score: 1, size: 18, child: SizedBox.square(dimension: 18))),
      ),
    );
    expect(tester.getSize(find.byType(TagConfidenceOutline)), const Size(20, 20));
  });

  testWidgets('아이콘 모양 테를 한 장으로 구워도 아이콘은 그대로이고 둘레만 초록이다', (tester) async {
    // 20×20 white square icon (PNG).
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = Colors.white);
      final image = await recorder.endRecording().toImage(20, 20);
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    }))!;
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tufapp_tag_icon_')))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    final previous = ImageCacheStore.instance;
    ImageCacheStore.instance = ImageCacheStore.forTesting(
      directory: dir,
      client: MockClient((_) async => http.Response.bytes(png, 200)),
    );
    addTearDown(() => ImageCacheStore.instance = previous);

    const url = 'https://example.com/icon.png';
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: RasterSnapshot(
                child: TagConfidenceOutline(score: 1, size: 20, iconUrl: url, child: const NetworkIcon(url, size: 20)),
              ),
            ),
          ),
        ),
      ),
    );
    // Wait until the image is loaded and decoded.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Newly loaded icons fade in; wait for it to finish.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final center = await pixel(tester, image, 15, 15);
    expect(center.r, greaterThan(0.9), reason: '아이콘 안쪽은 흰색 그대로 (초록으로 덮이지 않는다)');
    expect(center.b, greaterThan(0.9));
    expect(isGreen(await pixel(tester, image, 25, 15)), isTrue, reason: '오른쪽 둘레는 초록');
    expect(isGreen(await pixel(tester, image, 4, 15)), isTrue, reason: '왼쪽 둘레는 초록');
  });
}

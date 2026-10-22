import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:tufapp/app/paged_list.dart';
import 'package:tufapp/core/image_cache_store.dart';
import 'package:tufapp/core/level_downloader.dart';
import 'package:tufapp/core/level_library.dart';
import 'package:tufapp/core/level_manager.dart';
import 'package:tufapp/core/tuf_api_client.dart';

/// 코드 검토에서 고친 것들이 다시 깨지지 않는지 본다.
void main() {
  group('다음 묶음을 받다가 실패하면', () {
    test('저절로 다시 받지 않고, 다시 시도를 눌러야 받는다', () async {
      final list = _FlakyList();
      await list.reload();
      expect(list.items, [0, 1]);

      list.failNext = true;
      await list.loadMore();
      expect(list.loadMoreError, isNotNull);
      final calls = list.calls;

      // 화면이 다시 그려지며 몇 번을 불러도 요청하지 않는다.
      for (var i = 0; i < 5; i++) {
        await list.loadMore();
      }
      expect(list.calls, calls, reason: '실패한 뒤에는 쏟아지듯 다시 요청하지 않는다');

      await list.retryLoadMore();
      expect(list.loadMoreError, isNull);
      expect(list.items, [0, 1, 2, 3]);
    });

    test('새로 검색하면 실패 표시가 지워진다', () async {
      final list = _FlakyList();
      await list.reload();
      list.failNext = true;
      await list.loadMore();
      expect(list.loadMoreError, isNotNull);
      await list.reload();
      expect(list.loadMoreError, isNull);
    });
  });

  group('받은 레벨 목록 파일이 깨져 있으면', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('tufapp_review_'));
    tearDown(() async => root.delete(recursive: true));

    File index() => File(p.join(root.path, LevelLibrary.indexFileName));

    test('읽을 수 없는 파일은 남겨 두고 빈 목록으로 시작한다 (멈추지 않는다)', () async {
      await index().writeAsString('{not json');
      final library = await LevelLibrary.open(root.path);
      expect(library.getAll(), isEmpty);
      expect(library.recovery, isNotNull);
      final backups = root.listSync().where(
        (e) => p.basename(e.path).startsWith('${LevelLibrary.indexFileName}.broken'),
      );
      expect(backups, hasLength(1), reason: '원래 파일은 지우지 않는다');
    });

    test('폴더 이름이 비었거나 라이브러리 밖을 가리키는 항목은 뺀다', () async {
      Map<String, Object?> entry(int id, Object? folder) => {
        'levelId': id,
        'song': 's$id',
        'artist': 'a',
        'fileId': 'f',
        'folderName': folder,
        'installedAt': '2026-01-01T00:00:00Z',
      };
      await index().writeAsString(
        jsonEncode([
          entry(1, '#1 good'),
          entry(2, ''),
          entry(3, '../outside'),
          entry(4, null),
          entry(5, 42),
          {'levelId': 'not a number'},
        ]),
      );
      final library = await LevelLibrary.open(root.path);
      expect(library.getAll().map((l) => l.levelId), [1]);
      expect(library.recovery, contains('5개'));
    });

    test('레벨을 지울 때 라이브러리 폴더 자체는 절대 지우지 않는다', () async {
      final keep = File(p.join(root.path, 'other level', 'keep.adofai'))..createSync(recursive: true);
      await index().writeAsString(
        jsonEncode([
          {'levelId': 7, 'song': 's', 'artist': 'a', 'fileId': 'f', 'folderName': '#7 s', 'installedAt': ''},
        ]),
      );
      final library = await LevelLibrary.open(root.path);
      Directory(p.join(root.path, '#7 s')).createSync();
      final manager = LevelManager(TufApiClient(client: MockClient((_) async => http.Response('{}', 404))), library);

      expect(await manager.uninstall(7), isTrue);
      expect(Directory(p.join(root.path, '#7 s')).existsSync(), isFalse);
      expect(keep.existsSync(), isTrue);
      expect(root.existsSync(), isTrue);
    });
  });

  group('받기', () {
    test('데이터가 오지 않고 멈춘 받기도 취소하면 바로 끝난다', () async {
      final dir = await Directory.systemTemp.createTemp('tufapp_review_dl_');
      addTearDown(() => dir.delete(recursive: true));
      final stalled = StreamController<List<int>>();
      addTearDown(stalled.close);
      final client = MockClient.streaming(
        (request, body) async => http.StreamedResponse(stalled.stream, 200, contentLength: 1000),
      );
      final downloader = LevelDownloader(TufApiClient(client: client));
      final cancel = CancelToken();

      final download = downloader.download(
        'https://api.tuforums.com/cdn/x',
        p.join(dir.path, 'x.zip'),
        cancelToken: cancel,
      );
      stalled.add([1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();

      await expectLater(download.timeout(const Duration(seconds: 2)), throwsA(isA<OperationCancelledException>()));
      expect(File(p.join(dir.path, 'x.zip.part')).existsSync(), isFalse, reason: '받다 만 파일은 지운다');
    });
  });

  test('그림 캐시 파일 이름은 주소가 길어도 짧고, 주소마다 다르다', () {
    final long = 'https://example.com/${'a' * 1000}';
    final name = ImageCacheStore.fileNameFor(long);
    expect(name.length, lessThan(48));
    expect(ImageCacheStore.fileNameFor('${long}b'), isNot(name));
    expect(ImageCacheStore.fileNameFor(long), name, reason: '같은 주소는 같은 파일');
  });
}

/// 한 번에 두 개씩 주고, [failNext]면 한 번 실패한다.
class _FlakyList extends PagedList<int> {
  _FlakyList() : super(TufApiClient(client: MockClient((_) async => http.Response('{}', 404))));

  bool failNext = false;
  int calls = 0;

  @override
  Future<({List<int> items, int total, bool hasMore})> fetch(int offset) async {
    calls++;
    if (failNext) {
      failNext = false;
      throw const TufApiException('서버 오류');
    }
    return (items: [offset, offset + 1], total: 10, hasMore: offset + 2 < 10);
  }

  @override
  Object keyOf(int item) => item;
}

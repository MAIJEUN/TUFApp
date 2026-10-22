import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tufapp/core/level_sizes.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/core/models/search_models.dart';
import 'package:tufapp/core/tuf_api_client.dart';

void main() {
  test('cdnData에서 zip 크기를 읽는다 (originalZip, 없으면 originalArchive)', () {
    expect(
      CdnLevelMetadata.fromJson({
        'originalZip': {'size': 130188836},
        'originalArchive': {'size': 1},
      }).archiveBytes,
      130188836,
    );
    expect(
      CdnLevelMetadata.fromJson({
        'originalArchive': {'size': 42},
      }).archiveBytes,
      42,
    );
    expect(CdnLevelMetadata.fromJson({}).archiveBytes, isNull);
  });

  test('같은 파일은 한 번만 묻고, 동시에 4개까지만 묻는다', () async {
    var running = 0;
    var peak = 0;
    final asked = <String>[];
    final gate = Completer<void>();
    final client = MockClient((request) async {
      asked.add(request.url.path);
      running++;
      peak = running > peak ? running : peak;
      await gate.future;
      running--;
      final id = int.parse(request.url.pathSegments[3]);
      return http.Response(
        jsonEncode({
          'metadata': {
            'originalZip': {'size': id * 1000},
          },
        }),
        200,
      );
    });
    final sizes = LevelSizes(TufApiClient(client: client));
    Level level(int id) => Level(id: id, song: 's', artist: 'a', creator: 'c', fileId: 'f$id');

    final results = [for (var id = 1; id <= 6; id++) sizes.resolve(level(id)), sizes.resolve(level(1))];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(peak, 4, reason: '한꺼번에 몰리지 않는다');
    gate.complete();

    expect(await Future.wait(results), [1000, 2000, 3000, 4000, 5000, 6000, 1000]);
    expect(asked, hasLength(6), reason: '같은 레벨은 한 번만 묻는다');
    expect(sizes.peek(level(3)), 3000);
    await sizes.resolve(level(3));
    expect(asked, hasLength(6), reason: '알아 둔 크기는 다시 묻지 않는다');
  });
}

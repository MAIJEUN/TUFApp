import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/app/controllers.dart';
import 'package:tufapp/core/models/pack.dart';
import 'package:tufapp/core/tuf_api_client.dart';

/// Reading pack responses, and the folder layout created in the library for pack downloads.
void main() {
  // A trimmed real response (GET /v2/database/levels/packs/{id}?tree=true).
  Map<String, dynamic> level(int id, String song, {String dlLink = 'https://cdn.tuforums.com/zips/x'}) => {
    'id': id,
    'song': song,
    'artist': 'A',
    'diffId': 16,
    'dlLink': dlLink,
    'tags': [
      {'id': 3},
    ],
    // Like the real response, the list holds typeIds.
    'curations': [
      {
        'id': 1,
        'typeIds': [17, 20],
      },
    ],
  };

  final json = {
    'id': 'HXvV76zK',
    'name': 'AWC: Original / Levels',
    'levelCount': 4,
    'favoritesCount': 59,
    'isPinned': true,
    'packOwner': {'nickname': 'star4th', 'avatarUrl': null},
    'items': [
      {
        'id': 2,
        'type': 'folder',
        'name': 'AWC 2024',
        'sortOrder': 1,
        'children': [
          {'id': 20, 'type': 'level', 'sortOrder': 0, 'referencedLevel': level(3, 'C')},
        ],
      },
      {
        'id': 1,
        'type': 'folder',
        'name': 'AWC 2023',
        'sortOrder': 0,
        'children': [
          {'id': 11, 'type': 'level', 'sortOrder': 1, 'referencedLevel': level(2, 'B')},
          {'id': 10, 'type': 'level', 'sortOrder': 0, 'referencedLevel': level(1, 'A')},
          {
            'id': 12,
            'type': 'folder',
            'name': 'Extra?',
            'sortOrder': 2,
            'children': [
              {'id': 13, 'type': 'level', 'sortOrder': 0, 'referencedLevel': level(4, 'D')},
            ],
          },
        ],
      },
      {
        'id': 30,
        'type': 'level',
        'sortOrder': 2,
        'referencedLevel': level(5, 'E', dlLink: 'https://drive.google.com/x'),
      },
    ],
  };

  test('폴더 구조를 순서대로 읽고, 팩 응답의 큐레이션도 읽는다', () {
    final detail = LevelPackDetail.fromJson(json);

    expect(detail.pack.name, 'AWC: Original / Levels');
    expect(detail.pack.owner?.name, 'star4th');
    expect(detail.pack.isPinned, isTrue);

    final first = detail.items.first as PackFolder;
    expect(first.name, 'AWC 2023', reason: 'sortOrder 순서');
    expect([for (final entry in first.allLevels) entry.level.song], ['A', 'B', 'D']);
    expect(detail.allLevels.map((entry) => entry.level.id), [1, 2, 4, 3, 5]);
    expect(detail.allLevels.first.level.curationTypeIds, [17, 20]);
  });

  test('팩째 받으면 팩 이름 폴더 아래에 팩과 같은 폴더 구조로 넣는다', () {
    final detail = LevelPackDetail.fromJson(json);
    final api = TufApiClient();
    addTearDown(api.close);
    final installs = InstallCenter(onStatus: (_) {});
    final packs = PacksController(
      api: api,
      levels: LevelsController(api: api, onStatus: (_) {}),
      installs: installs,
      onStatus: (_) {},
    )..detail = detail;

    final all = packs.downloadItems(detail.pack, detail.items);
    // ':' and '/' (not allowed in names) and a trailing '?' all become '_'.
    expect(
      [for (final item in all) (item.level.id, item.folder)],
      [
        (1, 'AWC_ Original _ Levels/AWC 2023'),
        (2, 'AWC_ Original _ Levels/AWC 2023'),
        (4, 'AWC_ Original _ Levels/AWC 2023/Extra_'),
        (3, 'AWC_ Original _ Levels/AWC 2024'),
      ],
      reason: 'TUF CDN에 없는 레벨(5)은 받을 수 없어서 뺀다',
    );

    final extra = (detail.items.first as PackFolder).children.whereType<PackFolder>().single;
    expect(packs.folderPathOf(extra), ['AWC 2023'], reason: '폴더가 놓인 위치 (팩 이름은 받을 때 붙는다)');
    final folderOnly = packs.downloadItems(detail.pack, [extra], path: packs.folderPathOf(extra));
    expect([for (final item in folderOnly) item.folder], ['AWC_ Original _ Levels/AWC 2023/Extra_']);
  });

  test('팩을 받는 동안 받는 폴더를 펼치고, 다 받은 폴더는 접는다. 폴더 버튼도 자기 몫을 안다', () async {
    final detail = LevelPackDetail.fromJson(json);
    final api = TufApiClient();
    addTearDown(api.close);
    // Without a library the download fails right away (nothing is downloaded); only the flow is checked.
    final packs = PacksController(
      api: api,
      levels: LevelsController(api: api, onStatus: (_) {}),
      installs: InstallCenter(onStatus: (_) {}),
      onStatus: (_) {},
    )..detail = detail;

    final opened = <Set<int>>[];
    packs.addListener(() {
      final snapshot = {...packs.expanded};
      if (opened.isEmpty || !setEquals(opened.last, snapshot)) opened.add(snapshot);
    });

    final items = packs.downloadItems(detail.pack, detail.items);
    final running = packs.startDownload('pack', 'AWC', items);
    final job = packs.download!;
    // Folder 1 (AWC 2023) holds levels 1 and 2, plus level 4 in subfolder 12.
    expect(job.levelsFor(1), [1, 2, 4]);
    expect(job.levelsFor(12), [4]);
    expect(job.levelsFor(2), [3]);
    expect(job.levelsFor('pack'), [1, 2, 4, 3]);
    expect(job.isActiveFor(1), isTrue, reason: '팩을 받을 때 폴더 버튼도 진행률로 바뀐다');
    await running;

    expect(opened, [
      <int>{}, // start
      {1}, // expand AWC 2023
      {1, 12}, // also expand the subfolder to download level 4
      <int>{}, // subfolder and AWC 2023 done, both collapse
      {2}, // AWC 2024
      <int>{},
    ]);
  });

  test('받기가 끝나면 버튼으로 돌아오고, 멈추면 남은 레벨은 받지 않는다', () async {
    final detail = LevelPackDetail.fromJson(json);
    final api = TufApiClient();
    addTearDown(api.close);
    final messages = <String>[];
    // Without a library the download fails right away (nothing is downloaded).
    final installs = InstallCenter(onStatus: (_) {});
    final packs = PacksController(
      api: api,
      levels: LevelsController(api: api, onStatus: (_) {}),
      installs: installs,
      onStatus: messages.add,
    );

    final items = packs.downloadItems(detail.pack, detail.items);
    final running = packs.startDownload('pack', 'AWC', items);
    expect(packs.isDownloading, isTrue);
    expect(packs.download?.scope, 'pack', reason: '누른 버튼이 진행률로 바뀐다');
    packs.cancelDownload();
    await running;

    expect(packs.isDownloading, isFalse, reason: '끝나면 다시 버튼으로');
    expect(messages.single, contains('멈췄습니다'));
    expect(messages.single, isNot(contains('실패')), reason: '멈춰서 끊긴 레벨은 실패로 세지 않는다');
  });
}

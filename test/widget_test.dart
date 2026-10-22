import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/level_downloader.dart';
import 'package:tufapp/core/models/difficulty.dart';
import 'package:tufapp/core/models/facet.dart';
import 'package:tufapp/core/models/level.dart';
import 'package:tufapp/core/models/search_models.dart';

void main() {
  group('Level.creatorDisplay (웹 formatCreatorDisplay 규칙)', () {
    Level withCredits(List<(String role, String name)> credits, {String? team, String? creator}) => Level(
      id: 1,
      song: 'song',
      artist: 'artist',
      team: team,
      creator: creator,
      credits: [
        for (final (index, credit) in credits.indexed)
          LevelCredit(role: credit.$1, creatorName: credit.$2, sortOrder: index),
      ],
    );

    test('차터 한 명 + VFX 한 명', () {
      expect(withCredits([('charter', 'A'), ('vfxer', 'B')]).creatorDisplay, 'A | B');
    });

    test('차터 두 명', () {
      expect(withCredits([('charter', 'A'), ('charter', 'B')]).creatorDisplay, 'A & B');
    });

    test('세 명 이상이면 "& n more"로 줄인다', () {
      expect(withCredits([('charter', 'A'), ('charter', 'B'), ('vfxer', 'C')]).creatorDisplay, 'A & 1 more | C');
    });

    test('팀이 있으면 팀 이름이 우선', () {
      expect(withCredits([('charter', 'A')], team: 'Team X').creatorDisplay, 'Team X');
    });

    test('크레딧이 없으면 검색 결과의 creator 문자열', () {
      expect(withCredits([], creator: 'X | Y').creatorDisplay, 'X | Y');
    });
  });

  group('LevelSearchQuery', () {
    final catalog = DifficultyCatalog(const [
      Difficulty(id: 5, name: 'Unranked', type: 'SPECIAL', sortOrder: 0),
      Difficulty(id: 1, name: 'P1', type: 'PGU', sortOrder: 1),
      Difficulty(id: 2, name: 'U20', type: 'PGU', sortOrder: 72),
      Difficulty(id: 3, name: 'GQ0 (G1~G4)', type: 'SPECIAL', sortOrder: 78),
      Difficulty(id: 4, name: 'UQ4 (U17~U20)', type: 'SPECIAL', sortOrder: 87),
    ]);

    test('정렬 값에는 방향 접미사를 붙인다 (없으면 서버가 무시)', () {
      expect(const LevelSort(LevelSortKey.totalClears, SortDirection.asc).toApiValue(), 'TOTAL_CLEARS_ASC');
      expect(const LevelSort(LevelSortKey.recent).toApiValue(), 'RECENT_DESC');
    });

    test('Q를 켜면 Q 전체 이름과 특수 난이도를 합쳐서 보낸다', () {
      final filter = catalog.createFilter(pguLower: 0, pguUpper: 1, qLower: 0, qUpper: 1, includeQ: true);
      final params = LevelSearchQuery(
        difficultyFilter: filter,
        specialDifficulties: const ['Unranked'],
        clearedFilter: FilterState.hide,
      ).toQueryParameters();

      expect(params['pguRange'], 'P1,U20');
      expect(params['specialDifficulties'], 'GQ0 (G1~G4),UQ4 (U17~U20),Unranked');
      expect(params['clearedFilter'], 'hide');
      expect(params.containsKey('availableDlFilter'), isFalse);
    });

    test('Q를 끄면 Q 난이도를 보내지 않는다', () {
      final filter = catalog.createFilter(pguLower: 0, pguUpper: 1, qLower: 0, qUpper: 1, includeQ: false);
      final params = LevelSearchQuery(difficultyFilter: filter).toQueryParameters();

      expect(params.containsKey('specialDifficulties'), isFalse);
    });

    test('슬라이더 노브 순서가 뒤바뀌어도 범위를 바로잡는다', () {
      final filter = catalog.createFilter(pguLower: 1, pguUpper: 0, qLower: 1, qUpper: 0, includeQ: true);

      expect(filter.pguRangeValue, 'P1,U20');
      expect(filter.includedQNames, ['GQ0 (G1~G4)', 'UQ4 (U17~U20)']);
    });

    test('특수 난이도 목록에는 Q 난이도가 들어가지 않는다', () {
      expect(catalog.special.map((d) => d.name), ['Unranked']);
      expect(catalog.q.map((d) => d.name), ['GQ0 (G1~G4)', 'UQ4 (U17~U20)']);
    });
  });

  test('TUF CDN 링크만 앱에서 직접 받을 수 있다', () {
    expect(LevelDownloader.isTufCdnLink('https://api.tuforums.com/cdn/47050507-b774-4fef-94de-1631f35fad40'), isTrue);
    expect(LevelDownloader.isTufCdnLink('https://cdn.tuforums.com/zips/abc/level.zip'), isTrue);
    expect(LevelDownloader.isTufCdnLink('https://api.tuforums.com/v2/database/levels/1'), isFalse);
    expect(LevelDownloader.isTufCdnLink('https://drive.google.com/file/d/123'), isFalse);
    expect(LevelDownloader.isTufCdnLink(null), isFalse);
  });

  group('기반 점수 변동 (PP)', () {
    Level level({int? baseScore, int difficultyBaseScore = 0}) => Level(
      id: 1,
      song: 'song',
      artist: 'artist',
      baseScore: baseScore,
      difficulty: Difficulty(id: 1, name: 'U16', baseScore: difficultyBaseScore),
    );

    test('난이도 기본값과 다르면 그 값을 보여준다', () {
      expect(level(baseScore: 32000).baseScoreOverride, 32000);
      expect(level(baseScore: 500, difficultyBaseScore: 350).baseScoreOverride, 500);
    });

    test('난이도 기본값과 같거나 값이 없으면 표시하지 않는다', () {
      expect(level(baseScore: 350, difficultyBaseScore: 350).baseScoreOverride, isNull);
      expect(level(baseScore: 0).baseScoreOverride, isNull);
      expect(level().baseScoreOverride, isNull);
    });
  });

  group('큐레이션 유형 (난이도 아이콘 둘레에 표시)', () {
    test('검색 결과의 curation.typeIds를 읽는다', () {
      final level = Level.fromJson({
        'id': 16294,
        'song': 'Welcome to the New World',
        'artist': 'artist',
        'isCurated': true,
        'curation': {
          'id': 4509,
          'levelId': 16294,
          'customColor': null,
          'typeIds': [18, 20],
        },
      });
      expect(level.curationTypeIds, [18, 20]);
    });

    test('단일 레벨 응답의 curations[].types도 읽고, 겹치면 하나로 본다', () {
      final level = Level.fromJson({
        'id': 11372,
        'song': 'song',
        'artist': 'artist',
        'curation': {
          'typeIds': [18],
        },
        'curations': [
          {
            'id': 1758,
            'types': [
              {'id': 18, 'name': 'C2'},
              {'id': 22, 'name': 'V2'},
            ],
          },
        ],
      });
      expect(level.curationTypeIds, [18, 22]);
    });

    test('큐레이션이 없으면 비어 있다', () {
      final level = Level.fromJson({'id': 1, 'song': 'song', 'artist': 'artist'});
      expect(level.curationTypeIds, isEmpty);
    });

    test('C0과 V0만 아이콘에서 빼고 나머지는 보여준다 (웹과 같은 규칙)', () {
      const shown = [
        FacetItem(id: 1, name: 'C2'),
        FacetItem(id: 2, name: 'V1'),
        FacetItem(id: 3, name: 'H2'),
        FacetItem(id: 4, name: 'Epic'),
        // 웹은 O0을 숨기지 않는다.
        FacetItem(id: 5, name: 'O0'),
      ];
      const hidden = [FacetItem(id: 6, name: 'C0'), FacetItem(id: 7, name: 'V0')];

      for (final item in shown) {
        expect(isHiddenCurationArcType(item), isFalse, reason: item.name);
      }
      for (final item in hidden) {
        expect(isHiddenCurationArcType(item), isTrue, reason: item.name);
      }
    });

    test('아이콘은 그룹 순서대로 늘어놓고, 모르는 id는 건너뛴다', () {
      final catalog = FacetCatalog(const [
        FacetItem(id: 22, name: 'V2', group: 'VFX', groupSortOrder: 2, sortOrder: 1),
        FacetItem(id: 18, name: 'C2', group: 'Chart', groupSortOrder: 0, sortOrder: 1),
        FacetItem(id: 4, name: 'H2', group: 'Misc', groupSortOrder: 3),
      ]);

      expect(
        [
          for (final item in catalog.resolve([22, 999, 4, 18])) item.name,
        ],
        ['C2', 'V2', 'H2'],
      );
    });
  });
}

import '../json.dart';
import '../l10n.dart';
import 'difficulty.dart';

enum LevelSortKey {
  recent('RECENT'),
  diff('DIFF'),
  clears('CLEARS'),
  totalClears('TOTAL_CLEARS'),
  likes('LIKES'),
  baseScore('BASESCORE'),
  bpm('BPM'),
  tiles('TILES'),
  time('TIME'),
  random('RANDOM');

  const LevelSortKey(this.apiName);

  final String apiName;
}

enum SortDirection { desc, asc }

class LevelSort {
  const LevelSort(this.key, [this.direction = SortDirection.desc]);

  final LevelSortKey key;
  final SortDirection direction;

  /// 백엔드는 "KEY_ASC" / "KEY_DESC" 형식만 인식한다. 접미사가 없으면 기본 정렬(id desc)로 처리된다.
  String toApiValue() => '${key.apiName}_${direction == SortDirection.asc ? 'ASC' : 'DESC'}';
}

/// 웹 레벨 페이지의 3단 필터 값 (클리어한 레벨, 다운로드 가능).
enum FilterState {
  /// 모두 표시 (필터 없음)
  show,

  /// 해당하는 레벨 숨김
  hide,

  /// 해당하는 레벨만 표시
  only,
}

class PagedResult<T> {
  const PagedResult({required this.results, required this.total, required this.hasMore});

  factory PagedResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) => PagedResult(
    results: asObjectList(json['results']).map(parse).toList(),
    total: asInt(json['total']),
    hasMore: json['hasMore'] == true,
  );

  final List<T> results;
  final int total;
  final bool hasMore;
}

/// 서버의 난이도 목록. 필터를 만들 때 순서와 이름을 정한다.
class DifficultyCatalog {
  DifficultyCatalog(Iterable<Difficulty> difficulties)
    : all = List.unmodifiable([...difficulties]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))) {
    if (pgu.isEmpty) {
      throw StateError(tr('서버 난이도 목록에 PGU 난이도가 없습니다.', "The server's difficulty list has no PGU difficulties."));
    }
  }

  final List<Difficulty> all;

  /// P1 ~ U20
  late final List<Difficulty> pgu = all.where((d) => d.type == 'PGU').toList();

  /// Qq, GQ0 ~ UQ4. 웹처럼 이름에 Q가 들어간 SPECIAL 난이도만 쓴다 (LEGACY인 Q2+, Q3+는 서버가 무시).
  late final List<Difficulty> q = all.where((d) => d.type == 'SPECIAL' && d.name.contains('Q')).toList();

  /// Q가 아닌 특수 난이도: Unranked, P0, Censored, Impossible 등
  late final List<Difficulty> special = all.where((d) => d.type == 'SPECIAL' && !d.name.contains('Q')).toList();

  Difficulty? named(String? name) => name == null ? null : all.where((d) => d.name == name).firstOrNull;

  Difficulty? byId(int? id) => id == null ? null : all.where((d) => d.id == id).firstOrNull;

  /// 슬라이더 위치(인덱스)로 필터를 만든다. 순서가 뒤바뀌어 있으면 바로잡는다.
  DifficultyFilter createFilter({
    required int pguLower,
    required int pguUpper,
    required int qLower,
    required int qUpper,
    required bool includeQ,
  }) {
    int clampTo(List<Difficulty> list, int i) => i.clamp(0, list.length - 1);

    final pguLo = clampTo(pgu, pguLower < pguUpper ? pguLower : pguUpper);
    final pguHi = clampTo(pgu, pguLower < pguUpper ? pguUpper : pguLower);

    var qNames = const <String>[];
    if (q.isNotEmpty) {
      final qLo = clampTo(q, qLower < qUpper ? qLower : qUpper);
      final qHi = clampTo(q, qLower < qUpper ? qUpper : qLower);
      qNames = [for (var i = qLo; i <= qHi; i++) q[i].name];
    }

    return DifficultyFilter(
      pguFrom: pgu[pguLo],
      pguTo: pgu[pguHi],
      qNames: qNames,
      includeQ: includeQ && qNames.isNotEmpty,
    );
  }
}

/// 서버는 PGU 범위를 이름 두 개로, Q 난이도를 전체 이름 목록으로 받는다.
class DifficultyFilter {
  const DifficultyFilter({required this.pguFrom, required this.pguTo, required this.qNames, required this.includeQ});

  final Difficulty pguFrom;
  final Difficulty pguTo;

  /// Q 범위에 들어가는 난이도의 전체 이름 (예: "GQ0 (G1~G4)"). 짧은 이름을 보내면 서버가 무시한다.
  final List<String> qNames;
  final bool includeQ;

  String get pguRangeValue => '${pguFrom.name},${pguTo.name}';

  List<String> get includedQNames => includeQ ? qNames : const [];
}

/// GET /v2/database/levels 검색 조건.
class LevelSearchQuery {
  const LevelSearchQuery({
    this.query,
    this.sort = const LevelSort(LevelSortKey.recent),
    this.difficultyFilter,
    this.specialDifficulties = const [],
    this.clearedFilter = FilterState.show,
    this.availableDlFilter = FilterState.show,
    this.facetQuery,
    this.offset = 0,
    this.limit = 30,
    this.seed,
    this.byCreatorId,
  });

  final String? query;
  final LevelSort sort;

  /// null이면 난이도로 거르지 않는다. 필터를 쓰면 PGU 범위와 포함한 Q/특수 난이도만 나온다.
  final DifficultyFilter? difficultyFilter;

  /// 추가로 포함할 특수 난이도의 전체 이름 (Unranked, Censored 등).
  final List<String> specialDifficulties;
  final FilterState clearedFilter;
  final FilterState availableDlFilter;

  /// 태그·큐레이션 유형 필터 (facetQuery v1 JSON). [buildFacetQuery]로 만든다.
  final String? facetQuery;
  final int offset;
  final int limit;

  /// 무작위 정렬의 시드. 같은 시드로 요청해야 페이지를 넘겨도 순서가 유지된다.
  final int? seed;

  /// 이 제작자가 채보나 이펙트를 맡은 레벨만 (제작자 페이지).
  final int? byCreatorId;

  Map<String, String> toQueryParameters() {
    final trimmed = query?.trim() ?? '';
    final specials = {...?difficultyFilter?.includedQNames, ...specialDifficulties};

    return {
      'offset': '$offset',
      'limit': '$limit',
      'sort': sort.toApiValue(),
      if (trimmed.isNotEmpty) 'query': trimmed,
      if (difficultyFilter != null) 'pguRange': difficultyFilter!.pguRangeValue,
      if (specials.isNotEmpty) 'specialDifficulties': specials.join(','),
      'facetQuery': ?facetQuery,
      if (clearedFilter != FilterState.show) 'clearedFilter': clearedFilter.name,
      if (availableDlFilter != FilterState.show) 'availableDlFilter': availableDlFilter.name,
      if (seed != null) 'seed': '$seed',
      if (byCreatorId != null) 'byCreatorId': '$byCreatorId',
    };
  }
}

/// GET /v2/database/levels/{id}/cdnData 의 metadata 중 필요한 부분.
class CdnLevelMetadata {
  const CdnLevelMetadata({this.targetLevelRelativePath, this.archiveBytes});

  factory CdnLevelMetadata.fromJson(Map<String, dynamic> json) {
    int? sizeOf(Object? archive) => archive is Map<String, dynamic> ? asIntOrNull(archive['size']) : null;
    return CdnLevelMetadata(
      targetLevelRelativePath: asStringOrNull(json['targetLevelRelativePath']),
      archiveBytes: sizeOf(json['originalZip']) ?? sizeOf(json['originalArchive']),
    );
  }

  /// 메인 차트의 zip 내 상대 경로. 예: "Multi_arm(fixed)/main.adofai"
  final String? targetLevelRelativePath;

  /// 받을 zip 파일의 크기 (바이트). 모르면 null.
  final int? archiveBytes;
}

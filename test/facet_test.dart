import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/models/facet.dart';
import 'package:tufapp/core/models/search_models.dart';

void main() {
  group('facetQuery (태그 / 큐레이션 유형)', () {
    test('아무것도 고르지 않으면 보내지 않는다', () {
      expect(buildFacetQuery(), isNull);
      expect(buildFacetQuery(tags: const FacetSelection(), curationTypes: const FacetSelection()), isNull);
    });

    test('하나라도 / 모두 포함을 op로 보낸다', () {
      final any = jsonDecode(buildFacetQuery(tags: const FacetSelection(ids: {50, 49}))!);
      expect(any, {
        'v': 1,
        'tags': {
          'mode': 'simple',
          'op': 'or',
          'ids': [49, 50],
        },
      });

      final all = jsonDecode(buildFacetQuery(tags: const FacetSelection(ids: {49, 50}, matchAll: true))!);
      expect(all['tags']['op'], 'and');
    });

    test('둘 다 고르면 둘 다 만족하는 레벨만 찾는다', () {
      final both = jsonDecode(
        buildFacetQuery(
          tags: const FacetSelection(ids: {49}),
          curationTypes: const FacetSelection(ids: {19}),
        )!,
      );
      expect(both['curationTypes'], {
        'mode': 'simple',
        'op': 'or',
        'ids': [19],
      });
      expect(both['combine'], 'and');
    });

    test('검색 요청에 facetQuery가 실린다', () {
      final query = LevelSearchQuery(
        facetQuery: buildFacetQuery(curationTypes: const FacetSelection(ids: {19})),
      );
      expect(query.toQueryParameters()['facetQuery'], contains('"curationTypes"'));
      expect(const LevelSearchQuery().toQueryParameters().containsKey('facetQuery'), isFalse);
    });
  });

  group('FacetCatalog', () {
    final catalog = FacetCatalog(const [
      FacetItem(id: 2, name: 'Rolling', group: 'Play Style', groupSortOrder: 0, sortOrder: 1),
      FacetItem(id: 1, name: 'Pseudo', group: 'Play Style', groupSortOrder: 0, sortOrder: 0),
      FacetItem(id: 3, name: 'C3', group: 'Chart', groupSortOrder: 1),
      FacetItem(id: 4, name: '이름만'),
    ]);

    test('그룹 순서대로 묶고, 그룹 안에서는 정해진 순서대로 둔다', () {
      expect([for (final g in catalog.groups) g.title], ['Play Style', 'Chart', '기타']);
      expect([for (final item in catalog.groups.first.items) item.name], ['Pseudo', 'Rolling']);
    });

    test('id로 찾는다', () {
      expect(catalog.byId(3)?.name, 'C3');
      expect(catalog.byId(99), isNull);
    });
  });
}

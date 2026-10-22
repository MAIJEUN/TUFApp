import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'json.dart';
import 'l10n.dart';
import 'models/browse.dart';
import 'models/difficulty.dart';
import 'models/facet.dart';
import 'models/level.dart';
import 'models/pack.dart';
import 'models/pass.dart';
import 'models/profile.dart';
import 'models/search_models.dart';

class TufApiException implements Exception {
  const TufApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// TUF API(https://api.tuforums.com) 클라이언트.
class TufApiClient {
  TufApiClient({http.Client? client}) : _client = client ?? http.Client();

  static final Uri baseUri = Uri.parse('https://api.tuforums.com/');
  static const _headers = {'User-Agent': 'TUFApp/0.2'};

  /// 서버가 이만큼 답하지 않으면 실패로 본다 (연결이 멈춰서 화면이 영영 기다리지 않게).
  static const requestTimeout = Duration(seconds: 20);

  final http.Client _client;

  Future<PagedResult<Level>> searchLevels(LevelSearchQuery query) async {
    final json = await _getJson('v2/database/levels', query.toQueryParameters());
    if (json is! Map<String, dynamic>) throw TufApiException(tr('검색 응답 형식이 올바르지 않습니다.', 'Unexpected search response.'));
    return PagedResult.fromJson(json, Level.fromJson);
  }

  Future<Level> getLevel(int id) async {
    final json = await _getJson('v2/database/levels/$id');
    final level = json is Map<String, dynamic> ? json['level'] : null;
    if (level is! Map<String, dynamic>) {
      throw TufApiException(tr('레벨 $id의 응답에 level 필드가 없습니다.', 'The response for level $id has no level field.'));
    }
    return Level.fromJson(level);
  }

  Future<List<Difficulty>> getDifficulties() async {
    final json = await _getJson('v2/database/difficulties');
    if (json is! List) throw TufApiException(tr('난이도 목록 응답 형식이 올바르지 않습니다.', 'Unexpected difficulty list response.'));
    return json.whereType<Map<String, dynamic>>().map(Difficulty.fromJson).toList();
  }

  /// 레벨에 붙는 태그 목록 (그룹 정보 포함).
  Future<List<FacetItem>> getTags() => _getFacetItems('v2/database/difficulties/tags', tr('태그', 'tag'));

  /// 큐레이션 유형 목록 (C3, V2, Epic 등).
  Future<List<FacetItem>> getCurationTypes() =>
      _getFacetItems('v2/admin/curations/types', tr('큐레이션 유형', 'curation type'));

  Future<List<FacetItem>> _getFacetItems(String path, String label) async {
    final json = await _getJson(path);
    if (json is! List) throw TufApiException(tr('$label 목록 응답 형식이 올바르지 않습니다.', 'Unexpected $label list response.'));
    return json.whereType<Map<String, dynamic>>().map(FacetItem.fromJson).toList();
  }

  /// 레벨 하나의 클리어 기록 (리더보드).
  Future<List<LevelPass>> getLevelPasses(int levelId) async {
    final json = await _getJson('v2/database/passes/level/$levelId');
    if (json is! List) {
      throw TufApiException(tr('레벨 $levelId의 기록 응답 형식이 올바르지 않습니다.', 'Unexpected pass response for level $levelId.'));
    }
    return json.whereType<Map<String, dynamic>>().map(LevelPass.fromJson).toList();
  }

  /// 기록 하나의 자세한 정보 (랭킹 점수에 보탠 몫, 순위 포함).
  Future<PassDetail> getPass(int id) async {
    final json = await _getJson('v2/database/passes/$id');
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('기록 $id의 응답 형식이 올바르지 않습니다.', 'Unexpected response for pass $id.'));
    }
    return PassDetail.fromJson(json);
  }

  /// 기록을 낸 사람의 정보 (점수, 순위 등).
  Future<PlayerProfile> getPlayer(int id) async {
    final json = await _getJson('v2/database/players/$id');
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('플레이어 $id의 응답 형식이 올바르지 않습니다.', 'Unexpected response for player $id.'));
    }
    return PlayerProfile.fromJson(json);
  }

  /// 모든 클리어 기록 검색 (웹의 클리어 목록).
  Future<({List<PlayerPassEntry> passes, int total, int? seed})> searchPasses(ClearSearchQuery query) async {
    final json = await _getJson('v2/database/passes', query.toQueryParameters());
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('클리어 목록 응답 형식이 올바르지 않습니다.', 'Unexpected pass list response.'));
    }
    return (
      passes: asObjectList(json['results']).map(PlayerPassEntry.fromJson).toList(),
      total: asInt(json['count']),
      seed: asIntOrNull(json['seed']),
    );
  }

  /// 번호로 클리어 기록 찾기 (검색창에 "#번호"). 없으면 빈 목록.
  Future<List<PlayerPassEntry>> findPassesById(int id) async {
    final json = await _getJson('v2/database/passes/byId/$id');
    if (json is! Map<String, dynamic>) return const [];
    return asObjectList(json['results']).map(PlayerPassEntry.fromJson).toList();
  }

  /// 플레이어 리더보드. 웹처럼 정지된 플레이어는 뺀다.
  Future<({List<LeaderboardPlayer> players, int total})> getLeaderboard({
    String query = '',
    LeaderboardSort sort = LeaderboardSort.rankedScore,
    bool descending = true,
    int offset = 0,
    int limit = 30,
  }) async {
    final json = await _getJson('v3/players/leaderboard', {
      'query': query.trim(),
      'sortBy': sort.name,
      'order': descending ? 'desc' : 'asc',
      'offset': '$offset',
      'limit': '$limit',
      'flagField': 'isBanned',
      'flagMode': 'hide',
    });
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('리더보드 응답 형식이 올바르지 않습니다.', 'Unexpected leaderboard response.'));
    }
    return (
      players: asObjectList(json['results']).map(LeaderboardPlayer.fromJson).toList(),
      total: asInt(json['count']),
    );
  }

  /// 제작자 목록 (웹의 제작자 페이지). [facetQuery]는 큐레이션 유형 조건 ([buildFacetQuery]).
  Future<({List<CreatorListEntry> creators, int total})> getCreators({
    String query = '',
    CreatorSort sort = CreatorSort.chartsTotal,
    bool descending = true,
    CreatorVerification? verification,
    String? facetQuery,
    int offset = 0,
    int limit = 30,
  }) async {
    final json = await _getJson('v3/creators/leaderboard', {
      'query': query.trim(),
      'sortBy': sort.name,
      'order': descending ? 'desc' : 'asc',
      'offset': '$offset',
      'limit': '$limit',
      if (verification != null) 'filters': jsonEncode({'verificationStatus': verification.name}),
      'facetQuery': ?facetQuery,
    });
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('제작자 목록 응답 형식이 올바르지 않습니다.', 'Unexpected creator list response.'));
    }
    return (
      creators: asObjectList(json['results']).map(CreatorListEntry.fromJson).toList(),
      total: asInt(json['count']),
    );
  }

  /// 플레이어 페이지 (점수, 통계, 대회 입상, 모듈 배치).
  Future<PlayerProfileDetail> getPlayerProfile(int id) async {
    final json = await _getJson('v3/players/$id/profile');
    if (json is! Map<String, dynamic> || json['id'] == null) {
      throw TufApiException(tr('플레이어 $id을(를) 찾을 수 없습니다.', 'Player $id not found.'), 404);
    }
    return PlayerProfileDetail.fromJson(json);
  }

  /// 플레이어의 기록 목록. 정렬과 검색은 서버가 한다.
  Future<({List<PlayerPassEntry> passes, int total})> getPlayerPasses(
    int id, {
    int offset = 0,
    int limit = 50,
    PlayerPassSort sort = PlayerPassSort.score,
    bool descending = true,
    String query = '',
    bool bestPerLevel = false,
  }) async {
    final json = await _getJson('v3/players/$id/passes', {
      'limit': '$limit',
      'offset': '$offset',
      'sortBy': sort.name,
      'order': descending ? 'DESC' : 'ASC',
      if (query.trim().isNotEmpty) 'query': query.trim(),
      if (bestPerLevel) 'bestPerLevel': 'true',
    });
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('플레이어 $id의 기록 응답 형식이 올바르지 않습니다.', 'Unexpected pass response for player $id.'));
    }
    return (passes: asObjectList(json['passes']).map(PlayerPassEntry.fromJson).toList(), total: asInt(json['total']));
  }

  /// 순위 변화. [from]/[to]가 없으면 전체 기간.
  Future<List<RankHistoryPoint>> getRankHistory(int id, {DateTime? from, DateTime? to}) async {
    String day(DateTime date) => date.toUtc().toIso8601String().substring(0, 10);
    final json = await _getJson('v3/players/$id/rank-history', {
      if (from != null) 'from': day(from),
      if (to != null) 'to': day(to),
    });
    if (json is! Map<String, dynamic>) {
      throw TufApiException(
        tr('플레이어 $id의 순위 기록 응답 형식이 올바르지 않습니다.', 'Unexpected rank history response for player $id.'),
      );
    }
    return asObjectList(json['series']).map(RankHistoryPoint.fromJson).toList();
  }

  /// 제작자 페이지.
  Future<CreatorProfileDetail> getCreatorProfile(int id) async {
    final json = await _getJson('v3/creators/$id/profile');
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('제작자 $id을(를) 찾을 수 없습니다.', 'Creator $id not found.'), 404);
    }
    return CreatorProfileDetail.fromJson(json);
  }

  /// 공개된 레벨 팩 목록. 웹의 팩 페이지와 같은 요청이다.
  Future<({List<LevelPack> packs, int total})> searchPacks({
    String query = '',
    PackSort sort = PackSort.recent,
    bool descending = true,
    int offset = 0,
    int limit = 30,
  }) async {
    final json = await _getJson('v2/database/levels/packs', {
      'offset': '$offset',
      'limit': '$limit',
      'sort': sort.apiValue,
      'order': descending ? 'DESC' : 'ASC',
      if (query.trim().isNotEmpty) 'query': query.trim(),
    });
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('팩 목록 응답 형식이 올바르지 않습니다.', 'Unexpected pack list response.'));
    }
    return (packs: asObjectList(json['packs']).map(LevelPack.fromJson).toList(), total: asInt(json['total']));
  }

  /// 팩 하나를 폴더 구조까지 받는다.
  Future<LevelPackDetail> getPack(String id, {Level Function(Level level)? resolveLevel}) async {
    final json = await _getJson('v2/database/levels/packs/${Uri.encodeComponent(id)}', {'tree': 'true'});
    if (json is! Map<String, dynamic>) {
      throw TufApiException(tr('팩 $id의 응답 형식이 올바르지 않습니다.', 'Unexpected response for pack $id.'));
    }
    return LevelPackDetail.fromJson(json, resolveLevel: resolveLevel);
  }

  /// 레벨 zip의 내용 정보. CDN에 없는 레벨이면 null.
  Future<CdnLevelMetadata?> getLevelCdnMetadata(int id) async {
    final json = await _getJson('v2/database/levels/$id/cdnData');
    final metadata = json is Map<String, dynamic> ? json['metadata'] : null;
    return metadata is Map<String, dynamic> ? CdnLevelMetadata.fromJson(metadata) : null;
  }

  /// 영상 링크(YouTube, Bilibili 등)의 썸네일 이미지 주소. 서버가 캐시해 두며, Bilibili는 TUF 이미지 프록시 주소로 준다.
  Future<String?> getVideoThumbnailUrl(String videoLink) async {
    final json = await _getJson('v2/media/video-details/${Uri.encodeComponent(videoLink)}');
    return json is Map<String, dynamic> ? asStringOrNull(json['image']) : null;
  }

  /// 헤더까지만 받은 응답. 본문은 호출자가 스트림으로 읽는다.
  Future<http.StreamedResponse> openDownload(String url) async {
    final request = http.Request('GET', Uri.parse(url))..headers.addAll(_headers);

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(requestTimeout);
    } on TimeoutException {
      throw TufApiException(tr('서버가 응답하지 않습니다: $url', 'The server is not responding: $url'));
    } on http.ClientException catch (e) {
      throw TufApiException(tr('다운로드 요청 실패: $url (${e.message})', 'Download request failed: $url (${e.message})'));
    } on IOException catch (e) {
      throw TufApiException(tr('다운로드 요청 실패: $url ($e)', 'Download request failed: $url ($e)'));
    }

    if (response.statusCode >= 400) {
      await response.stream.drain<void>();
      throw TufApiException('${response.statusCode} ${response.reasonPhrase ?? ''}: $url', response.statusCode);
    }
    return response;
  }

  /// [query] 값은 글자이거나, 같은 이름으로 여러 번 보낼 글자 목록이다.
  Future<Object?> _getJson(String path, [Map<String, Object>? query]) async {
    var uri = baseUri.resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);

    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(requestTimeout);
    } on TimeoutException {
      throw TufApiException(tr('서버가 응답하지 않습니다: $path', 'The server is not responding: $path'));
    } on http.ClientException catch (e) {
      throw TufApiException(tr('요청 실패: $path (${e.message})', 'Request failed: $path (${e.message})'));
    } on IOException catch (e) {
      throw TufApiException(tr('요청 실패: $path ($e)', 'Request failed: $path ($e)'));
    }

    if (response.statusCode >= 400) {
      throw TufApiException('${response.statusCode}: $path ${response.body}'.trim(), response.statusCode);
    }

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw TufApiException(tr('응답을 읽을 수 없습니다: $path', 'Could not read the response: $path'));
    }
  }

  void close() => _client.close();
}

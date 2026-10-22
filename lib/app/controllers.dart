import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/frame_log.dart';
import '../core/l10n.dart';
import '../core/level_downloader.dart';
import '../core/level_library.dart';
import '../core/level_manager.dart';
import '../core/level_sizes.dart';
import '../core/library_organizer.dart';
import '../core/models/difficulty.dart';
import '../core/models/facet.dart';
import '../core/models/level.dart';
import '../core/models/search_models.dart';
import '../core/tuf_api_client.dart';
import '../core/video_links.dart';
import '../core/video_thumbnails.dart';
import 'browse_controllers.dart';
import 'packs_controller.dart';

export 'browse_controllers.dart';
export 'packs_controller.dart';

enum AppPage { levels, packs, clears, leaderboard, creators, library }

enum LevelInstallState { notInstalled, installed, updateAvailable, notDownloadable }

/// 위젯 트리 어디서나 [AppController]를 꺼내 쓰기 위한 InheritedWidget.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.controller, required super.child});

  final AppController controller;

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.controller;

  @override
  bool updateShouldNotify(AppScope oldWidget) => controller != oldWidget.controller;
}

/// 앱 전체 상태: 페이지, 상태 메시지, 초기화, 하위 컨트롤러.
class AppController extends ChangeNotifier {
  /// [api]는 테스트에서 가짜 서버를 끼울 때만 준다.
  AppController({TufApiClient? api}) : api = api ?? TufApiClient() {
    installs = InstallCenter(onStatus: setStatus);
    levels = LevelsController(api: this.api, onStatus: setStatus);
    library = LibraryController(api: this.api, installs: installs, onStatus: setStatus);
    packs = PacksController(api: this.api, levels: levels, installs: installs, onStatus: setStatus);
    clears = ClearsController(this.api, catalog: () => levels.catalog);
    leaderboard = LeaderboardController(this.api);
    creators = CreatorsController(this.api);
    installs.addListener(library.onInstallsChanged);
  }

  final TufApiClient api;
  late final VideoThumbnails thumbnails = VideoThumbnails(api);
  late final LevelSizes levelSizes = LevelSizes(api);
  late final InstallCenter installs;
  late final LevelsController levels;
  late final LibraryController library;
  late final PacksController packs;
  late final ClearsController clears;
  late final LeaderboardController leaderboard;
  late final CreatorsController creators;

  AppPage page = AppPage.levels;
  String status = tr('불러오는 중...', 'Loading...');
  String? startupError;

  void setPage(AppPage value) {
    if (page == value) return;
    page = value;
    // 팩·클리어·리더보드 목록은 처음 볼 때 불러온다.
    switch (value) {
      case AppPage.packs:
        packs.ensureLoaded();
      case AppPage.clears:
        clears.ensureLoaded();
      case AppPage.leaderboard:
        leaderboard.ensureLoaded();
      case AppPage.creators:
        creators.ensureLoaded();
      case AppPage.levels || AppPage.library:
        break;
    }
    notifyListeners();
  }

  void setStatus(String message) {
    status = message;
    notifyListeners();
  }

  /// 고른 화면 언어. null이면 시스템 언어를 따른다.
  AppLanguage? languageChoice;

  /// 화면 언어를 바꾸고 설정 파일에 적는다. null이면 시스템 언어를 따른다.
  /// 화면은 [TufApp]이 이 알림을 듣고 전체를 다시 그린다.
  Future<void> setLanguage(AppLanguage? choice) async {
    final wasReady = status == _readyText;
    languageChoice = choice;
    appLanguage = choice ?? AppLanguage.system;
    if (wasReady) status = _readyText;
    notifyListeners();

    final settings = library.settings;
    if (settings == null) return;
    settings.language = choice;
    try {
      await settings.save();
    } on FileSystemException catch (e) {
      setStatus(tr('설정을 저장하지 못했습니다: ${e.message}', 'Could not save settings: ${e.message}'));
    }
  }

  static String get _readyText => tr('준비됐습니다.', 'Ready.');

  /// [settings]는 앱을 켤 때 언어를 먼저 정하려고 미리 읽어 둔 설정이다 (없으면 여기서 읽는다).
  Future<void> initialize({AppSettings? settings}) async {
    startupError = null;
    setStatus(tr('불러오는 중...', 'Loading...'));

    try {
      settings ??= await AppSettings.load();
      settings.language = languageChoice;
      library.settings = settings;
      final tags = _tryList(api.getTags());
      final curations = _tryList(api.getCurationTypes());
      // 둘을 함께 기다린다. 따로 기다리면 먼저 실패한 쪽 때문에 나머지의 실패가 처리되지 않고 남는다.
      final ready = await Future.wait([library.open(settings.libraryPath), api.getDifficulties()]);
      final catalog = DifficultyCatalog(ready[1] as List<Difficulty>);

      setStatus(library.recovery ?? _readyText);
      await levels.initialize(catalog, tags: FacetCatalog(await tags), curationTypes: FacetCatalog(await curations));
    } on TufApiException catch (e) {
      _failStartup(e.message);
    } on FileSystemException catch (e) {
      _failStartup(e.message);
    } on StateError catch (e) {
      _failStartup(e.message);
    } on Object catch (e) {
      // 예상하지 못한 오류도 '불러오는 중'에 멈춰 있지 않고 다시 시도할 수 있게 한다.
      _failStartup('$e');
    }
  }

  /// 태그·큐레이션 목록은 없어도 나머지 기능은 쓸 수 있으므로 실패를 삼킨다.
  static Future<List<FacetItem>> _tryList(Future<List<FacetItem>> request) async {
    try {
      return await request;
    } on TufApiException {
      return const [];
    }
  }

  void _failStartup(String message) {
    startupError = message;
    setStatus(tr('시작하지 못했습니다: $message', 'Could not start: $message'));
  }

  Difficulty? difficultyNamed(String? name) => levels.catalog?.named(name);

  /// http/https 링크만 브라우저로 연다.
  /// 영상 칸처럼 링크 여러 개가 빈칸으로 이어져 있으면 첫 번째(대표)를 연다.
  Future<void> openLink(String? url) async {
    final first = VideoLinks.primary(url);
    final uri = first == null ? null : Uri.tryParse(first);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        setStatus(tr('링크를 열 수 없습니다: $url', 'Could not open the link: $url'));
      }
    } on PlatformException {
      setStatus(tr('링크를 열 수 없습니다: $url', 'Could not open the link: $url'));
    }
  }

  @override
  void dispose() {
    installs.removeListener(library.onInstallsChanged);
    levels.dispose();
    library.dispose();
    packs.dispose();
    clears.dispose();
    leaderboard.dispose();
    creators.dispose();
    installs.dispose();
    api.close();
    super.dispose();
  }
}

// ───────────────────────── 받기 ─────────────────────────

/// 레벨 하나를 받는 작업의 진행 상태.
class InstallJob extends ChangeNotifier {
  InstallJob(this.levelId);

  final int levelId;
  final CancelToken cancelToken = CancelToken();

  /// null이면 진행률을 알 수 없음 (준비/압축 해제 중).
  double? fraction;

  /// 좁은 버튼 안에 보여줄 짧은 상태. 예: "42%", "압축 해제"
  String shortText = tr('준비 중', 'Preparing');

  void report(InstallProgress progress) {
    switch (progress.stage) {
      case InstallStage.fetchingInfo:
        fraction = null;
        shortText = tr('준비 중', 'Preparing');
      case InstallStage.downloading:
        final download = progress.download;
        fraction = download?.fraction;
        shortText = fraction != null ? '${(fraction! * 100).round()}%' : formatBytes(download?.bytesReceived ?? 0);
      case InstallStage.extracting:
        fraction = null;
        shortText = tr('압축 해제', 'Extracting');
      case InstallStage.completed:
        fraction = 1;
        shortText = tr('완료', 'Done');
    }
    notifyListeners();
  }

  void cancel() {
    cancelToken.cancel();
    shortText = tr('취소 중', 'Cancelling');
    notifyListeners();
  }
}

/// 진행 중인 받기 작업. 같은 레벨을 동시에 두 번 받지 않고, 어느 화면에서든 같은 진행 상태를 보여준다.
class InstallCenter extends ChangeNotifier {
  InstallCenter({required this.onStatus});

  final void Function(String message) onStatus;
  LevelManager? manager;

  final Map<int, InstallJob> _jobs = {};

  InstallJob? jobFor(int levelId) => _jobs[levelId];

  int get activeCount => _jobs.length;

  /// 라이브러리가 바뀌었을 때(삭제, 폴더 변경) 받기 버튼 상태를 다시 그리게 한다.
  void refresh() => notifyListeners();

  LevelInstallState stateOf(Level level) {
    final installed = manager?.library.get(level.id);
    if (installed != null) {
      final remoteFileId = level.fileId;
      final isLatest = remoteFileId == null || remoteFileId.toLowerCase() == installed.fileId.toLowerCase();
      return isLatest ? LevelInstallState.installed : LevelInstallState.updateAvailable;
    }
    return LevelDownloader.isTufCdnLink(level.dlLink)
        ? LevelInstallState.notInstalled
        : LevelInstallState.notDownloadable;
  }

  /// 레벨을 받는다. [parentFolder]를 주면 라이브러리의 그 폴더 아래에 넣는다 ('/'로 구분).
  /// 받았으면 true.
  Future<bool> install(Level level, {String? parentFolder}) async {
    final current = manager;
    if (current == null || _jobs.containsKey(level.id)) return false;

    final job = InstallJob(level.id);
    _jobs[level.id] = job;
    notifyListeners();

    try {
      await current.install(level, onProgress: job.report, cancelToken: job.cancelToken, parentFolder: parentFolder);
      onStatus(tr('받기 완료: ${level.song}', 'Downloaded: ${level.song}'));
      return true;
    } on OperationCancelledException {
      onStatus(tr('받기를 취소했습니다: ${level.song}', 'Download cancelled: ${level.song}'));
    } on LevelNotDownloadableException catch (e) {
      final link = e.alternativeLink;
      onStatus(link == null ? e.toString() : tr('$e 대신 이 링크를 확인하세요: $link', '$e Try this link instead: $link'));
    } on TufApiException catch (e) {
      onStatus(tr('받지 못했습니다 (${level.song}): ${e.message}', 'Download failed (${level.song}): ${e.message}'));
    } on FileSystemException catch (e) {
      onStatus(tr('받지 못했습니다 (${level.song}): ${e.message}', 'Download failed (${level.song}): ${e.message}'));
    } on FormatException catch (e) {
      onStatus(tr('받지 못했습니다 (${level.song}): ${e.message}', 'Download failed (${level.song}): ${e.message}'));
    } finally {
      _jobs.remove(level.id);
      notifyListeners();
    }
    return false;
  }
}

// ───────────────────────── 레벨 찾기 ─────────────────────────

class SortOption {
  const SortOption(this.key, this._ko, this._en);

  final LevelSortKey key;
  final String _ko;
  final String _en;

  String get label => tr(_ko, _en);
}

const sortOptions = [
  SortOption(LevelSortKey.recent, '최신순 (ID)', 'Newest (ID)'),
  SortOption(LevelSortKey.diff, '난이도', 'Difficulty'),
  SortOption(LevelSortKey.clears, '클리어 수', 'Clears'),
  SortOption(LevelSortKey.totalClears, '전체 클리어', 'Total clears'),
  SortOption(LevelSortKey.likes, '좋아요 수', 'Likes'),
  SortOption(LevelSortKey.baseScore, '기반 점수', 'Base score'),
  SortOption(LevelSortKey.bpm, 'BPM', 'BPM'),
  SortOption(LevelSortKey.tiles, '타일 수', 'Tiles'),
  SortOption(LevelSortKey.time, '길이', 'Length'),
  SortOption(LevelSortKey.random, '무작위', 'Random'),
];

class SpecialDifficultyGroup {
  const SpecialDifficultyGroup({required this.hidden, required this.items});

  /// 히든 난이도 묶음이면 true, 엑스트라 묶음이면 false.
  final bool hidden;

  String get title => hidden ? tr('히든', 'Hidden') : tr('엑스트라', 'Extra');
  final List<Difficulty> items;
}

/// 검색어, 필터, 정렬, 무한 스크롤 목록.
class LevelsController extends ChangeNotifier {
  LevelsController({required this.api, required this.onStatus});

  static const pageSize = 30;
  static const _searchDebounce = Duration(milliseconds: 500);

  /// 웹 TagSelector에서 '히든' 그룹으로 묶는 난이도.
  static const _hiddenSpecialNames = {'Unranked', 'Impossible', 'Censored', 'P0'};

  final TufApiClient api;
  final void Function(String message) onStatus;

  DifficultyCatalog? catalog;

  // 검색
  String _searchText = '';
  String _committedQuery = '';
  Timer? _debounceTimer;

  String get searchText => _searchText;
  bool get isSearchPending => _searchText.trim() != _committedQuery;

  bool filterOpen = true;

  // 난이도
  int pguLower = 0;
  int pguUpper = 0;
  int qLower = 0;
  int qUpper = 0;
  bool includeQ = false;
  final Set<String> selectedSpecials = {};
  List<SpecialDifficultyGroup> specialGroups = const [];

  // 보기 필터 / 정렬 / 보기 방법
  FilterState clearedFilter = FilterState.show;
  FilterState availableDlFilter = FilterState.show;
  SortOption sort = sortOptions.first;
  bool ascending = false;
  bool compact = false;

  // 결과
  final List<Level> levels = [];
  bool isSearching = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  bool hasSearched = false;

  /// 다음 페이지를 받다가 실패한 이유. 있으면 저절로 다시 받지 않고 [retryLoadMore]를 기다린다.
  String? loadMoreError;
  int total = 0;

  /// 검색창에 적힌 글자만 따로 알린다 (목록은 다시 그리지 않는다).
  final ValueNotifier<String> searchTextNotifier = ValueNotifier('');

  /// 새 검색이 시작될 때마다 증가. 화면은 이 값이 바뀌면 맨 위로 스크롤한다.
  int searchGeneration = 0;
  int _nextOffset = 0;
  int? _seed;

  String? get qIconUrl => (catalog?.q.where((d) => d.name == 'Qq').firstOrNull ?? catalog?.q.firstOrNull)?.icon;

  int get activeFilterCount {
    final current = catalog;
    if (current == null) return 0;
    return [
      pguLower != 0 || pguUpper != current.pgu.length - 1,
      includeQ,
      selectedSpecials.isNotEmpty,
      selectedTagIds.isNotEmpty,
      selectedCurationIds.isNotEmpty,
      clearedFilter != FilterState.show,
      availableDlFilter != FilterState.show,
    ].where((changed) => changed).length;
  }

  /// 고른 태그와 큐레이션 유형. 각각 "하나라도"(기본) 또는 "모두"로 찾을 수 있다.
  final Set<int> selectedTagIds = {};
  bool tagsMatchAll = false;
  final Set<int> selectedCurationIds = {};
  bool curationsMatchAll = false;

  FacetCatalog? tagCatalog;
  FacetCatalog? curationCatalog;

  void toggleTag(int id) {
    selectedTagIds.contains(id) ? selectedTagIds.remove(id) : selectedTagIds.add(id);
    search();
  }

  void clearTags() {
    if (selectedTagIds.isEmpty) return;
    selectedTagIds.clear();
    search();
  }

  void setTagsMatchAll(bool value) {
    if (tagsMatchAll == value) return;
    tagsMatchAll = value;
    selectedTagIds.length > 1 ? search() : notifyListeners();
  }

  void toggleCuration(int id) {
    selectedCurationIds.contains(id) ? selectedCurationIds.remove(id) : selectedCurationIds.add(id);
    search();
  }

  void clearCurations() {
    if (selectedCurationIds.isEmpty) return;
    selectedCurationIds.clear();
    search();
  }

  void setCurationsMatchAll(bool value) {
    if (curationsMatchAll == value) return;
    curationsMatchAll = value;
    selectedCurationIds.length > 1 ? search() : notifyListeners();
  }

  Future<void> initialize(DifficultyCatalog value, {FacetCatalog? tags, FacetCatalog? curationTypes}) {
    catalog = value;
    tagCatalog = tags;
    curationCatalog = curationTypes;
    specialGroups = [
      SpecialDifficultyGroup(
        hidden: false,
        items: value.special.where((d) => !_hiddenSpecialNames.contains(d.name)).toList(),
      ),
      SpecialDifficultyGroup(
        hidden: true,
        items: value.special.where((d) => _hiddenSpecialNames.contains(d.name)).toList(),
      ),
    ].where((g) => g.items.isNotEmpty).toList();
    _applyDefaultRange();
    return search();
  }

  /// 글자를 칠 때마다 알리지 않는다. 목록 전체를 다시 그리면 타이핑이 밀린다.
  /// 지우기 버튼처럼 입력 상태만 보는 위젯은 [searchTextNotifier]를 듣는다.
  void setSearchText(String value) {
    if (value == _searchText) return;
    _searchText = value;
    searchTextNotifier.value = value;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_searchDebounce, search);
  }

  void submitSearch() => search();

  void clearSearch() {
    _searchText = '';
    searchTextNotifier.value = '';
    search();
  }

  void toggleFilterOpen() {
    filterOpen = !filterOpen;
    notifyListeners();
  }

  void setPguRange(int lower, int upper) {
    pguLower = lower;
    pguUpper = upper;
    _filtersChanged();
  }

  void setQRange(int lower, int upper) {
    qLower = lower;
    qUpper = upper;
    _filtersChanged();
  }

  void setIncludeQ(bool value) {
    includeQ = value;
    _filtersChanged();
  }

  void toggleSpecial(String name) {
    if (!selectedSpecials.remove(name)) selectedSpecials.add(name);
    _filtersChanged();
  }

  /// 하나라도 선택돼 있으면 모두 해제, 아니면 모두 선택.
  void toggleAllSpecials() {
    if (selectedSpecials.isNotEmpty) {
      selectedSpecials.clear();
    } else {
      selectedSpecials.addAll(specialGroups.expand((g) => g.items).map((d) => d.name));
    }
    _filtersChanged();
  }

  void setClearedFilter(FilterState value) {
    clearedFilter = value;
    _filtersChanged();
  }

  void setAvailableDlFilter(FilterState value) {
    availableDlFilter = value;
    _filtersChanged();
  }

  void setSort(SortOption value) {
    sort = value;
    _filtersChanged();
  }

  void toggleOrder() {
    ascending = !ascending;
    _filtersChanged();
  }

  void setCompact(bool value) {
    compact = value;
    notifyListeners();
  }

  /// 검색어, 정렬, 난이도, 특수 난이도, 보기 필터를 모두 기본값으로.
  void resetAll() {
    _searchText = '';
    searchTextNotifier.value = '';
    sort = sortOptions.first;
    ascending = false;
    _applyDefaultRange();
    includeQ = false;
    selectedSpecials.clear();
    selectedTagIds.clear();
    selectedCurationIds.clear();
    tagsMatchAll = false;
    curationsMatchAll = false;
    clearedFilter = FilterState.show;
    availableDlFilter = FilterState.show;
    search();
  }

  void _applyDefaultRange() {
    final current = catalog;
    if (current == null) return;
    pguLower = 0;
    pguUpper = current.pgu.length - 1;
    qLower = 0;
    qUpper = max(0, current.q.length - 1);
  }

  void _filtersChanged() {
    notifyListeners();
    search();
  }

  /// 첫 페이지부터 새로 검색한다. 이전 검색의 늦게 온 응답은 무시한다.
  Future<void> search() async {
    if (catalog == null) return;
    _debounceTimer?.cancel();

    _committedQuery = _searchText.trim();
    _seed = sort.key == LevelSortKey.random ? Random().nextInt(0x7FFFFFFE) + 1 : null;
    final generation = ++searchGeneration;
    isSearching = true;
    isLoadingMore = false;
    loadMoreError = null;
    notifyListeners();

    try {
      final page = await api.searchLevels(_buildQuery(0));
      if (generation != searchGeneration) return;

      levels
        ..clear()
        ..addAll(page.results);
      _nextOffset = page.results.length;
      hasMore = page.hasMore;
      total = page.total;
      hasSearched = true;
    } on TufApiException catch (e) {
      if (generation == searchGeneration) onStatus(tr('검색하지 못했습니다: ${e.message}', 'Search failed: ${e.message}'));
    } finally {
      if (generation == searchGeneration) {
        isSearching = false;
        notifyListeners();
      }
    }
  }

  /// 스크롤이 끝에 가까워지면 화면에서 호출한다. 다음 페이지를 이어 붙인다.
  Future<void> loadMore() async {
    if (catalog == null || !hasMore || isSearching || isLoadingMore || loadMoreError != null) return;

    final generation = searchGeneration;
    isLoadingMore = true;
    notifyListeners();

    try {
      final page = await api.searchLevels(_buildQuery(_nextOffset));
      if (generation != searchGeneration) return;

      levels.addAll(page.results);
      _nextOffset += page.results.length;
      hasMore = page.hasMore;
    } on TufApiException catch (e) {
      if (generation == searchGeneration) loadMoreError = e.message;
    } finally {
      if (generation == searchGeneration) {
        isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// 실패한 다음 페이지를 다시 받는다 (목록 맨 아래의 '다시 시도').
  Future<void> retryLoadMore() {
    loadMoreError = null;
    return loadMore();
  }

  LevelSearchQuery _buildQuery(int offset) => LevelSearchQuery(
    query: _committedQuery.isEmpty ? null : _committedQuery,
    sort: LevelSort(sort.key, ascending ? SortDirection.asc : SortDirection.desc),
    difficultyFilter: catalog!.createFilter(
      pguLower: pguLower,
      pguUpper: pguUpper,
      qLower: qLower,
      qUpper: qUpper,
      includeQ: includeQ,
    ),
    specialDifficulties: selectedSpecials.toList(),
    facetQuery: buildFacetQuery(
      tags: FacetSelection(ids: selectedTagIds, matchAll: tagsMatchAll),
      curationTypes: FacetSelection(ids: selectedCurationIds, matchAll: curationsMatchAll),
    ),
    clearedFilter: clearedFilter,
    availableDlFilter: availableDlFilter,
    offset: offset,
    limit: pageSize,
    seed: _seed,
  );

  @override
  void dispose() {
    _debounceTimer?.cancel();
    searchTextNotifier.dispose();
    super.dispose();
  }
}

/// 목록 정렬 방식.
enum LibrarySort { name, size, recent }

Map<LibrarySort, String> get librarySortLabels => {
  LibrarySort.name: tr('이름순', 'Name'),
  LibrarySort.size: tr('크기순', 'Size'),
  LibrarySort.recent: tr('최근 받은 순', 'Recently downloaded'),
};

// ───────────────────────── 받은 레벨 ─────────────────────────

class LibraryController extends ChangeNotifier {
  LibraryController({required this.api, required this.installs, required this.onStatus});

  final TufApiClient api;
  final InstallCenter installs;
  final void Function(String message) onStatus;

  AppSettings? settings;
  LevelLibrary? library;
  LibraryOrganizer? organizer;

  /// 라이브러리를 열 때 목록 파일이 깨져 있어서 고친 내용 (없으면 null).
  String? recovery;

  /// 지금 보고 있는 폴더 (라이브러리 루트 기준, 루트는 빈 문자열).
  String currentPath = '';
  FolderContents? contents;

  /// 고른 항목들의 경로. 탐색기처럼 Ctrl/Shift로 여러 개를 고를 수 있다.
  final Set<String> selection = {};

  /// 선택이 바뀐 것만 따로 알린다. 목록 전체를 다시 그리면 클릭이 굼떠진다.
  final ValueNotifier<int> selectionRevision = ValueNotifier(0);

  void _selectionChanged() => selectionRevision.value++;

  /// Shift로 범위를 고를 때 기준이 되는 항목.
  String? _selectionAnchor;

  LibrarySort sort = LibrarySort.name;

  /// 정렬을 적용한 목록. 폴더가 항상 먼저 온다.
  List<LibraryEntry> get entries {
    final current = contents;
    if (current == null) return const [];
    return [..._sorted(current.folders), ..._sorted(current.levels)];
  }

  List<LibraryEntry> get selectedEntries => [
    for (final entry in entries)
      if (selection.contains(entry.relativePath)) entry,
  ];

  List<LibraryEntry> _sorted(List<LibraryEntry> items) {
    final sorted = [...items];
    switch (sort) {
      case LibrarySort.name:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case LibrarySort.size:
        sorted.sort((a, b) => _sizeOf(b).compareTo(_sizeOf(a)));
      case LibrarySort.recent:
        sorted.sort((a, b) => _installedAt(b).compareTo(_installedAt(a)));
    }
    return sorted;
  }

  static int _sizeOf(LibraryEntry entry) => entry is LevelEntry ? entry.level.sizeBytes : 0;

  static DateTime _installedAt(LibraryEntry entry) =>
      entry is LevelEntry ? entry.level.installedAt : DateTime.fromMillisecondsSinceEpoch(0);

  void setSort(LibrarySort value) {
    if (sort == value) return;
    sort = value;
    notifyListeners();
  }

  /// 탐색기와 같은 선택 규칙: 그냥 누르면 하나만, Ctrl은 토글, Shift는 범위.
  void select(LibraryEntry entry, {bool toggle = false, bool range = false}) {
    final all = entries;
    if (range && _selectionAnchor != null) {
      final from = all.indexWhere((item) => item.relativePath == _selectionAnchor);
      final to = all.indexWhere((item) => item.relativePath == entry.relativePath);
      if (from >= 0 && to >= 0) {
        selection
          ..clear()
          ..addAll(all.sublist(min(from, to), max(from, to) + 1).map((item) => item.relativePath));
        _selectionChanged();
        return;
      }
    }

    if (toggle) {
      selection.contains(entry.relativePath) ? selection.remove(entry.relativePath) : selection.add(entry.relativePath);
    } else {
      selection
        ..clear()
        ..add(entry.relativePath);
    }
    _selectionAnchor = entry.relativePath;
    _selectionChanged();
  }

  void selectAll() {
    selection
      ..clear()
      ..addAll(entries.map((entry) => entry.relativePath));
    _selectionChanged();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection.clear();
    _selectionAnchor = null;
    _selectionChanged();
  }

  /// 드래그한 항목이 선택에 들어 있으면 선택 전체를, 아니면 그 항목만 옮긴다.
  List<LibraryEntry> dragGroupFor(LibraryEntry entry) =>
      selection.contains(entry.relativePath) && selection.length > 1 ? selectedEntries : [entry];

  /// 한 단계 위 폴더로.
  Future<void> goUp() {
    final index = currentPath.lastIndexOf('/');
    return openPath(index < 0 ? '' : currentPath.substring(0, index));
  }

  /// 현재 폴더까지의 경로 조각. [('루트', ''), ('Camellia', 'Camellia'), ...]
  List<(String name, String path)> get breadcrumb {
    final parts = currentPath.split('/').where((part) => part.isNotEmpty).toList();
    final crumbs = <(String, String)>[(tr('루트', 'Root'), '')];
    var path = '';
    for (final part in parts) {
      path = path.isEmpty ? part : '$path/$part';
      crumbs.add((part, path));
    }
    return crumbs;
  }

  /// 마지막 업데이트 확인 결과 (레벨 ID → 서버의 새 버전).
  final Map<int, Level> _pendingUpdates = {};
  bool isCheckingUpdates = false;

  List<InstalledLevel> get installed => library?.getAll() ?? const [];
  int get installedCount => installed.length;
  int get totalSize => installed.fold(0, (sum, level) => sum + level.sizeBytes);
  int get updateCount => _pendingUpdates.length;
  String get rootPath => library?.rootPath ?? '';

  Level? updateFor(int levelId) => _pendingUpdates[levelId];

  Future<void> open(String path) async {
    final opened = await LevelLibrary.open(path);
    recovery = opened.recovery;
    await opened.pruneMissing();
    library = opened;
    organizer = LibraryOrganizer(opened);
    installs.manager = LevelManager(api, opened);
    _pendingUpdates.clear();
    currentPath = '';

    // 전에 받았거나 직접 넣어 둔 폴더 중 게임이 못 불러오는 이름('+')을 바꿔 둔다.
    final renamed = await organizer!.fixUnloadableNames();
    if (renamed > 0) {
      onStatus(
        tr(
          "폴더 이름의 '+'를 '_'로 바꿨습니다 ($renamed개). 게임이 '+'가 든 경로를 불러오지 못해서예요.",
          "Replaced '+' with '_' in $renamed folder ${plural(renamed, 'name')}. The game can't load paths that contain '+'.",
        ),
      );
    }

    await refreshContents();
  }

  /// 지금 폴더의 내용을 다시 읽는다. 폴더가 사라졌으면 루트로 돌아간다.
  Future<void> refreshContents() async {
    final current = organizer;
    if (current == null) return;

    final watch = Stopwatch()..start();
    try {
      if (currentPath.isNotEmpty && !await Directory(current.fullPath(currentPath)).exists()) currentPath = '';
      contents = await current.list(currentPath);
      FrameLog.note('폴더 읽기', watch.elapsed, detail: currentPath.isEmpty ? '루트' : currentPath);
      final alive = {for (final entry in contents!.all) entry.relativePath};
      selection.removeWhere((path) => !alive.contains(path));
      _selectionChanged();
    } on LibraryOperationException catch (e) {
      onStatus(e.message);
    } on FileSystemException catch (e) {
      onStatus(tr('폴더를 읽지 못했습니다: ${e.message}', 'Could not read the folder: ${e.message}'));
    }
    notifyListeners();
  }

  Future<void> openPath(String relativePath) async {
    currentPath = relativePath;
    clearSelection();
    await refreshContents();
  }

  Future<void> createFolder(String name) => _organize((organizer) async {
    final created = await organizer.createFolder(currentPath, name);
    return tr('폴더를 만들었습니다: $created', 'Created folder: $created');
  });

  /// 지금 받기와 겹쳐서 건드리면 안 되는 항목인지.
  /// 받는 중인 레벨 자신, 또는 받기가 진행 중일 때의 폴더 (팩째 받기가 그 안에 레벨을 넣고 있을 수 있다).
  /// 이런 것을 지우거나 옮기면 받기가 끝난 뒤 레벨이 엉뚱한 자리에 다시 생긴다.
  bool _isBusy(LibraryEntry entry) => switch (entry) {
    LevelEntry(:final level) => installs.jobFor(level.levelId) != null,
    FolderEntry() => installs.activeCount > 0,
    ExternalLevelEntry() => false,
  };

  static String get _busyMessage => tr(
    '받는 중인 레벨이 있어서 지금은 할 수 없습니다. 받기가 끝난 뒤 다시 해 주세요.',
    "Can't do this while a level is downloading. Try again once the download finishes.",
  );

  /// 받기와 겹치지 않는 것만 남긴다. 건너뛴 개수를 알리는 글도 함께 돌려준다.
  ({List<LibraryEntry> items, String skipped}) _withoutBusy(List<LibraryEntry> items) {
    final free = items.where((entry) => !_isBusy(entry)).toList();
    final skipped = items.length - free.length;
    return (
      items: free,
      skipped: skipped == 0 ? '' : tr(' (받는 중이라 $skipped개는 건너뛰었습니다)', ' (skipped $skipped still downloading)'),
    );
  }

  Future<void> renameEntry(LibraryEntry entry, String newName) => _organize((organizer) async {
    if (_isBusy(entry)) return _busyMessage;
    await organizer.rename(entry, newName);
    return tr('이름을 바꿨습니다: $newName', 'Renamed to: $newName');
  });

  /// 여러 항목을 한 폴더로 옮긴다. 하나가 실패해도 나머지는 계속 옮긴다.
  Future<void> moveEntries(List<LibraryEntry> all, String targetFolder) => _organize((organizer) async {
    final (:items, :skipped) = _withoutBusy(all);
    var moved = 0;
    final failures = <String>[];
    for (final entry in items) {
      try {
        await organizer.move(entry, targetFolder);
        moved++;
      } on LibraryOperationException catch (e) {
        failures.add('${entry.name}: ${e.message}');
      }
    }

    final where = targetFolder.isEmpty ? tr('루트', 'Root') : targetFolder;
    if (failures.isEmpty) {
      return tr('$moved개를 $where(으)로 옮겼습니다.$skipped', 'Moved $moved ${plural(moved, 'item')} to $where.$skipped');
    }
    return tr(
      '$moved개를 옮기고 ${failures.length}개는 옮기지 못했습니다 (${failures.first})$skipped',
      'Moved $moved, but ${failures.length} could not be moved (${failures.first})$skipped',
    );
  });

  /// 여러 항목을 지운다. 받은 레벨은 목록에서도 뺀다.
  Future<void> deleteEntries(List<LibraryEntry> all) => _organize((organizer) async {
    final (:items, :skipped) = _withoutBusy(all);
    var count = 0;
    for (final entry in items) {
      if (entry is LevelEntry) {
        await installs.manager?.uninstall(entry.level.levelId);
        _pendingUpdates.remove(entry.level.levelId);
      } else {
        await organizer.delete(entry);
      }
      count++;
    }
    installs.refresh();
    return tr('$count개를 지웠습니다.$skipped', 'Deleted $count ${plural(count, 'item')}.$skipped');
  });

  Future<void> moveEntry(LibraryEntry entry, String targetFolder) => _organize((organizer) async {
    if (_isBusy(entry)) return _busyMessage;
    await organizer.move(entry, targetFolder);
    final where = targetFolder.isEmpty ? tr('루트', 'Root') : targetFolder;
    return tr('옮겼습니다: ${entry.name} → $where', 'Moved: ${entry.name} → $where');
  });

  /// 폴더나 (목록에 없는) 레벨 폴더를 통째로 지운다.
  Future<void> deleteEntry(LibraryEntry entry) => _organize((organizer) async {
    if (_isBusy(entry)) return _busyMessage;
    final removed = await organizer.delete(entry);
    installs.refresh();
    return removed == 0
        ? tr('지웠습니다: ${entry.name}', 'Deleted: ${entry.name}')
        : tr(
            '레벨 $removed개와 함께 지웠습니다: ${entry.name}',
            'Deleted with $removed ${plural(removed, 'level')}: ${entry.name}',
          );
  });

  /// 옮기기 대화상자에서 폴더를 하나씩 들여다본다 (라이브러리가 커도 느려지지 않게).
  Future<FolderContents> browse(String relativePath) async {
    final current = organizer;
    if (current == null) return const FolderContents(path: '', folders: [], levels: []);
    try {
      return await current.list(relativePath);
    } on FileSystemException {
      return FolderContents(path: relativePath, folders: const [], levels: const []);
    }
  }

  Future<void> _organize(Future<String> Function(LibraryOrganizer organizer) action) async {
    final current = organizer;
    if (current == null) return;

    try {
      onStatus(await action(current));
    } on LibraryOperationException catch (e) {
      onStatus(e.message);
    } on FileSystemException catch (e) {
      onStatus(tr('폴더를 다루지 못했습니다: ${e.message}', 'Folder operation failed: ${e.message}'));
    }
    await refreshContents();
  }

  /// 받기가 끝나면 호출된다. 이미 새 버전을 받은 레벨의 업데이트 표시를 지운다.
  void onInstallsChanged() {
    unawaited(refreshContents());
    final current = library;
    _pendingUpdates.removeWhere((id, remote) {
      final item = current?.get(id);
      return item == null || item.fileId.toLowerCase() == (remote.fileId ?? '').toLowerCase();
    });
    notifyListeners();
  }

  Future<void> checkUpdates() async {
    final manager = installs.manager;
    if (manager == null || isCheckingUpdates) return;

    isCheckingUpdates = true;
    onStatus(tr('업데이트를 확인하는 중...', 'Checking for updates...'));
    notifyListeners();

    try {
      final missing = await manager.library.pruneMissing();
      final updates = await manager.checkUpdates();
      _pendingUpdates
        ..clear()
        ..addEntries(updates.map((u) => MapEntry(u.installed.levelId, u.remote)));

      final missingText = missing.isEmpty
          ? ''
          : tr(
              ' 폴더가 사라진 레벨 ${missing.length}개는 목록에서 뺐습니다.',
              ' Removed ${missing.length} ${plural(missing.length, 'level')} whose folder is gone.',
            );
      final updateText = updates.isEmpty
          ? tr('모두 최신 버전입니다.', 'Everything is up to date.')
          : tr(
              '업데이트할 레벨이 ${updates.length}개 있습니다.',
              '${updates.length} ${plural(updates.length, 'level has', 'levels have')} an update.',
            );
      onStatus(updateText + missingText);
    } on FileSystemException catch (e) {
      onStatus(tr('업데이트를 확인하지 못했습니다: ${e.message}', 'Could not check for updates: ${e.message}'));
    } finally {
      isCheckingUpdates = false;
      notifyListeners();
    }
  }

  Future<void> updateAll() async {
    for (final remote in _pendingUpdates.values.toList()) {
      await installs.install(remote);
    }
  }

  Future<void> uninstall(InstalledLevel level) async {
    final manager = installs.manager;
    if (manager == null || installs.jobFor(level.levelId) != null) return;

    try {
      await manager.uninstall(level.levelId);
      _pendingUpdates.remove(level.levelId);
      await refreshContents();
      onStatus(tr('삭제했습니다: ${level.song}', 'Deleted: ${level.song}'));
    } on FileSystemException catch (e) {
      onStatus(tr('삭제하지 못했습니다: ${e.message}', 'Could not delete: ${e.message}'));
    } finally {
      notifyListeners();
      // 레벨 찾기 화면의 받기 버튼 상태도 갱신한다.
      installs.refresh();
    }
  }

  Future<void> changeFolder() async {
    if (installs.activeCount > 0) {
      onStatus(tr('받는 중인 레벨이 있어서 폴더를 바꿀 수 없습니다.', "Can't change the folder while a level is downloading."));
      return;
    }

    final path = await getDirectoryPath(confirmButtonText: tr('이 폴더 사용', 'Use this folder'));
    if (path == null) return;

    try {
      await open(path);
      final current = settings ?? AppSettings(libraryPath: path);
      current.libraryPath = library!.rootPath;
      settings = current;
      await current.save();
      onStatus(tr('라이브러리 폴더를 바꿨습니다: ${library!.rootPath}', 'Library folder changed: ${library!.rootPath}'));
      installs.refresh();
      if (recovery case final message?) onStatus(message);
    } on FileSystemException catch (e) {
      onStatus(tr('폴더를 열 수 없습니다: ${e.message}', 'Could not open the folder: ${e.message}'));
    }
  }

  Future<void> openFolder([InstalledLevel? level]) async {
    final current = library;
    if (current == null) return;
    await openFolderPath(level == null ? '' : level.folderName);
  }

  /// 라이브러리 루트 기준 경로를 탐색기로 연다. 빈 문자열이면 지금 보고 있는 폴더.
  Future<void> openFolderPath([String? relativePath]) async {
    final current = organizer;
    if (current == null) return;
    try {
      final path = current.fullPath(relativePath?.isNotEmpty == true ? relativePath! : currentPath);
      if (!await Directory(path).exists()) return;
      await launchUrl(Uri.directory(path));
    } on LibraryOperationException catch (e) {
      onStatus(e.message);
    }
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

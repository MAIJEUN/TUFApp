import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/tuf_api_client.dart';

/// 페이지와 함께 스크롤하며 끝에 가까워지면 다음 묶음을 불러오는 목록
/// (프로필의 기록·레벨, 클리어 목록, 리더보드).
abstract class PagedList<T> extends ChangeNotifier {
  PagedList(this.api);

  final TufApiClient api;
  final List<T> items = [];
  int total = 0;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  String? error;

  /// 다음 묶음을 받다가 실패한 이유. 있으면 저절로 다시 받지 않고, [retryLoadMore]를 기다린다.
  /// (그러지 않으면 화면이 다시 그려질 때마다 곧바로 또 요청해서 서버에 요청이 쏟아진다.)
  String? loadMoreError;

  /// 조건이 바뀌어 처음부터 다시 받을 때마다 늘어난다. 화면이 맨 위로 돌아갈 때 쓴다.
  int generation = 0;

  int _request = 0;
  bool _started = false;
  bool _disposed = false;
  Timer? _debounce;

  /// [offset]부터 한 묶음.
  @protected
  Future<({List<T> items, int total, bool hasMore})> fetch(int offset);

  /// 같은 항목을 두 번 넣지 않게 비교할 값.
  @protected
  Object keyOf(T item);

  /// 처음 볼 때 한 번만 불러온다.
  void ensureLoaded() {
    if (!_started) reload();
  }

  /// 처음부터 다시 받는다. 늦게 온 이전 응답은 버린다.
  Future<void> reload() async {
    _started = true;
    _debounce?.cancel();
    final request = ++_request;
    generation++;
    loading = true;
    error = null;
    loadMoreError = null;
    _notify();
    try {
      final page = await fetch(0);
      if (request != _request) return;
      items
        ..clear()
        ..addAll(page.items);
      total = page.total;
      hasMore = page.hasMore;
    } on TufApiException catch (e) {
      if (request == _request) error = e.message;
    } on Object catch (e) {
      // 응답 형식이 바뀌는 등 예상하지 못한 오류도 '불러오는 중'에 멈춰 있지 않게 알린다.
      if (request == _request) error = '$e';
    } finally {
      if (request == _request) {
        loading = false;
        _notify();
      }
    }
  }

  /// 검색어처럼 연달아 바뀌는 조건은 잠깐 기다렸다가 다시 받는다.
  @protected
  void reloadSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), reload);
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore || loadMoreError != null) return;
    final request = _request;
    loadingMore = true;
    _notify();
    try {
      final page = await fetch(items.length);
      if (request != _request) return;
      final known = {for (final item in items) keyOf(item)};
      final fresh = page.items.where((item) => !known.contains(keyOf(item))).toList();
      items.addAll(fresh);
      total = page.total;
      // 새 항목이 하나도 없으면 (서버가 같은 묶음을 또 주면) 더 묻지 않는다.
      hasMore = page.hasMore && fresh.isNotEmpty;
    } on TufApiException catch (e) {
      if (request == _request) loadMoreError = e.message;
    } on Object catch (e) {
      if (request == _request) loadMoreError = '$e';
    } finally {
      if (request == _request) {
        loadingMore = false;
        _notify();
      }
    }
  }

  /// 실패한 다음 묶음을 다시 받는다 (목록 맨 아래의 '다시 시도').
  Future<void> retryLoadMore() {
    loadMoreError = null;
    return loadMore();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/tuf_api_client.dart';

/// A list that scrolls with its page and loads the next batch near the end
/// (profile passes and levels, passes, leaderboard, creators).
abstract class PagedList<T> extends ChangeNotifier {
  PagedList(this.api);

  final TufApiClient api;
  final List<T> items = [];
  int total = 0;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  String? error;

  /// Why loading the next batch failed. While set, it is not requested again until [retryLoadMore]
  /// (otherwise every rebuild would retry immediately and flood the server).
  String? loadMoreError;

  /// Incremented on every reload from the start; the page scrolls back to the top when it changes.
  int generation = 0;

  int _request = 0;
  bool _started = false;
  bool _disposed = false;
  Timer? _debounce;

  /// One batch starting at [offset].
  @protected
  Future<({List<T> items, int total, bool hasMore})> fetch(int offset);

  /// Key used to skip duplicate items.
  @protected
  Object keyOf(T item);

  /// Loads once, the first time the list is shown.
  void ensureLoaded() {
    if (!_started) reload();
  }

  /// Reloads from the start, dropping late responses from earlier requests.
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
      // Report unexpected errors too (like a changed response format) instead of staying on "Loading".
      if (request == _request) error = '$e';
    } finally {
      if (request == _request) {
        loading = false;
        _notify();
      }
    }
  }

  /// Debounced reload for conditions that change in quick succession, like search text.
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
      // Stop asking when a batch has nothing new (the server returned the same batch again).
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

  /// Retries a failed next batch ("Retry" at the bottom of the list).
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

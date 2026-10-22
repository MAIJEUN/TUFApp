import 'dart:async';

import 'models/level.dart';
import 'tuf_api_client.dart';

/// Level zip sizes. List responses don't include them, so each level is asked once when its card appears.
/// Results are kept per file (level id + fileId) while the app runs, with only a few requests at a time.
class LevelSizes {
  LevelSizes(this._api);

  static const _maxConcurrent = 4;

  final TufApiClient _api;
  final _resolved = <String, int?>{};
  final _pending = <String, Future<int?>>{};
  final _queue = <Completer<void>>[];
  int _running = 0;

  static String _keyOf(Level level) => '${level.id}:${level.fileId ?? ''}';

  /// The size if already known, otherwise null.
  int? peek(Level level) => _resolved[_keyOf(level)];

  Future<int?> resolve(Level level) {
    final key = _keyOf(level);
    if (_resolved.containsKey(key)) return Future.value(_resolved[key]);
    return _pending.putIfAbsent(key, () => _fetch(level.id, key));
  }

  Future<int?> _fetch(int levelId, String key) async {
    while (_running >= _maxConcurrent) {
      final turn = Completer<void>();
      _queue.add(turn);
      await turn.future;
    }
    _running++;
    try {
      final size = (await _api.getLevelCdnMetadata(levelId))?.archiveBytes;
      _resolved[key] = size;
      return size;
    } on TufApiException {
      // Not cached; asked again when the card shows up next time.
      return null;
    } finally {
      _running--;
      _pending.remove(key);
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }
}

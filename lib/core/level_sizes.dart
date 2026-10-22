import 'dart:async';

import 'models/level.dart';
import 'tuf_api_client.dart';

/// 레벨 zip 크기. 목록 응답에는 없어서 카드가 보일 때 레벨마다 한 번씩 묻는다.
/// 같은 파일(레벨 id + fileId)은 앱이 켜져 있는 동안 기억하고, 한꺼번에 몰리지 않게 동시에 몇 개만 묻는다.
class LevelSizes {
  LevelSizes(this._api);

  static const _maxConcurrent = 4;

  final TufApiClient _api;
  final _resolved = <String, int?>{};
  final _pending = <String, Future<int?>>{};
  final _queue = <Completer<void>>[];
  int _running = 0;

  static String _keyOf(Level level) => '${level.id}:${level.fileId ?? ''}';

  /// 이미 알아 둔 크기. 모르면 null.
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
      // 기억하지 않는다. 카드가 다시 보이면 한 번 더 묻는다.
      return null;
    } finally {
      _running--;
      _pending.remove(key);
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }
}

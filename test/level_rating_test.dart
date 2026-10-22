import 'package:flutter_test/flutter_test.dart';
import 'package:tufapp/core/models/level.dart';

/// Q 레벨에 예상 PGU 난이도를 보여주려면 검색 결과의 rating.averageDifficultyId를 읽어야 한다.
void main() {
  test('평가에서 매겨진 예상 난이도를 읽는다', () {
    final level = Level.fromJson({
      'id': 15006,
      'song': 'Metamocluster',
      'artist': 'seatrus',
      'diffId': 65,
      'rating': {'id': 11939, 'levelId': 15006, 'averageDifficultyId': 42},
    });
    expect(level.ratedDifficultyId, 42);
  });

  test('평가가 없으면 비워 둔다', () {
    final level = Level.fromJson({'id': 1, 'song': 'a', 'artist': 'b', 'rating': null});
    expect(level.ratedDifficultyId, isNull);
  });
}

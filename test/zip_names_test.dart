import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tufapp/core/level_library.dart';
import 'package:tufapp/core/zip_names.dart';

/// 옛 압축 도구는 파일 이름을 UTF-8 표시 없이 그 컴퓨터의 코드 페이지로 적는다.
/// 그대로 풀면 이름이 깨져서 레벨이 노래를 못 찾는다.
void main() {
  // '자산 49oz.png' 의 CP949 바이트 (실제로 깨졌던 이름).
  final korean = <int>[...'9'.codeUnits, 0xC0, 0xDA, 0xBB, 0xEA, ...' 49oz.png'.codeUnits];
  // '曲.mp3' 의 Shift-JIS 바이트.
  final japanese = <int>[0x8B, 0xC8, ...'.mp3'.codeUnits];

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('tufapp-zip-test'));
  tearDown(() => temp.deleteSync(recursive: true));

  String extractTo(List<int> zip, {required String folder}) {
    final zipPath = p.join(temp.path, 'level.zip');
    File(zipPath).writeAsBytesSync(zip);
    final target = p.join(temp.path, folder);
    LevelArchive.extract(zipPath, target);
    return target;
  }

  List<String> namesIn(String folder) =>
      Directory(folder).listSync(recursive: true).map((e) => p.basename(e.path)).toList()..sort();

  test('한글 이름을 옛 방식으로 적은 zip', () {
    final out = extractTo(
      buildZip([
        ZipEntry(korean, [1, 2, 3]),
        ZipEntry('level.adofai'.codeUnits, utf8.encode('{"settings":{"songFilename":"자산 49oz.png"}}')),
      ]),
      folder: 'korean',
    );

    expect(namesIn(out), ['9자산 49oz.png', 'level.adofai']);
  });

  test('일본어 이름은 레벨 파일에 적힌 이름을 보고 고른다', () {
    // 이 바이트는 한국어 코드 페이지로도 읽히므로(엉뚱한 글자로), 레벨 파일과 견줘 봐야 제대로 고른다.
    final out = extractTo(
      buildZip([
        ZipEntry(japanese, [1, 2, 3]),
        ZipEntry('level.adofai'.codeUnits, utf8.encode('{"settings":{"songFilename":"曲.mp3"}}')),
      ]),
      folder: 'japanese',
    );

    expect(namesIn(out), ['level.adofai', '曲.mp3']);
  });

  test('UTF-8 표시가 있는 이름은 그대로 둔다', () {
    final out = extractTo(
      buildZip([
        ZipEntry(utf8.encode('별 하늘.png'), [1], utf8Flag: true),
      ]),
      folder: 'utf8',
    );

    expect(namesIn(out), ['별 하늘.png']);
  });

  test('ASCII 이름은 건드리지 않는다', () {
    final out = extractTo(
      buildZip([
        ZipEntry('song.mp3'.codeUnits, [1]),
        ZipEntry('level.adofai'.codeUnits, utf8.encode('{"songFilename":"song.mp3"}')),
      ]),
      folder: 'ascii',
    );

    expect(namesIn(out), ['level.adofai', 'song.mp3']);
  });

  test('한 zip 안에 서로 다른 언어의 이름이 섞여 있어도 고친다', () {
    // 한글(CP949)과 서유럽(CP1252) 이름이 한 zip에 같이 들어 있다.
    final out = extractTo(
      buildZip([
        ZipEntry(korean, [1]),
        ZipEntry([...'alic'.codeUnits, 0xE9, ...'.png'.codeUnits], [1]),
        ZipEntry(
          'level.adofai'.codeUnits,
          utf8.encode('{"settings":{"songFilename":"9자산 49oz.png","bgImage":"alicé.png"}}'),
        ),
      ]),
      folder: 'mixed',
    );

    expect(namesIn(out), ['9자산 49oz.png', 'alicé.png', 'level.adofai']);
  });

  test('바이트 그대로 온 이름만 골라낸다', () {
    expect(ZipNames.isRaw('song.mp3'), isFalse, reason: 'ASCII');
    expect(ZipNames.isRaw('별.png'), isFalse, reason: '제대로 읽힌 이름');
    expect(ZipNames.isRaw(String.fromCharCodes(korean)), isTrue);
  });

  test('코드 페이지에 없는 바이트면 읽지 않는다', () {
    expect(ZipNames.decode(949, Uint8List.fromList(korean)), '9자산 49oz.png');
    expect(ZipNames.decode(932, Uint8List.fromList(korean)), isNull, reason: '일본어 코드 페이지로는 읽을 수 없다');
    expect(ZipNames.decode(932, Uint8List.fromList(japanese)), '曲.mp3');
  });
}

class ZipEntry {
  ZipEntry(this.name, this.data, {this.utf8Flag = false});

  final List<int> name;
  final List<int> data;
  final bool utf8Flag;
}

/// 압축하지 않은(저장) zip을 손으로 만든다. 이름 바이트와 UTF-8 표시를 그대로 정할 수 있다.
List<int> buildZip(List<ZipEntry> entries) {
  final out = BytesBuilder();
  final directory = BytesBuilder();

  void uint16(BytesBuilder b, int value) => b.add([value & 0xFF, (value >> 8) & 0xFF]);
  void uint32(BytesBuilder b, int value) =>
      b.add([value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, (value >> 24) & 0xFF]);

  for (final entry in entries) {
    final offset = out.length;
    final crc = getCrc32(entry.data);
    final flags = entry.utf8Flag ? 0x800 : 0;

    uint32(out, 0x04034B50);
    uint16(out, 20); // 필요한 버전
    uint16(out, flags);
    uint16(out, 0); // 저장 (압축 안 함)
    uint16(out, 0); // 시각
    uint16(out, 0); // 날짜
    uint32(out, crc);
    uint32(out, entry.data.length);
    uint32(out, entry.data.length);
    uint16(out, entry.name.length);
    uint16(out, 0); // 추가 정보 없음
    out.add(entry.name);
    out.add(entry.data);

    uint32(directory, 0x02014B50);
    uint16(directory, 20); // 만든 버전
    uint16(directory, 20); // 필요한 버전
    uint16(directory, flags);
    uint16(directory, 0);
    uint16(directory, 0);
    uint16(directory, 0);
    uint32(directory, crc);
    uint32(directory, entry.data.length);
    uint32(directory, entry.data.length);
    uint16(directory, entry.name.length);
    uint16(directory, 0); // 추가 정보
    uint16(directory, 0); // 설명
    uint16(directory, 0); // 디스크 번호
    uint16(directory, 0); // 속성
    uint32(directory, 0); // 속성
    uint32(directory, offset);
    directory.add(entry.name);
  }

  final directoryBytes = directory.toBytes();
  final directoryOffset = out.length;
  out.add(directoryBytes);

  uint32(out, 0x06054B50);
  uint16(out, 0);
  uint16(out, 0);
  uint16(out, entries.length);
  uint16(out, entries.length);
  uint32(out, directoryBytes.length);
  uint32(out, directoryOffset);
  uint16(out, 0); // 전체 설명 없음

  return out.toBytes();
}

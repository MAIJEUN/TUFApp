// 이미 받아 둔 레벨의 깨진 파일 이름을 되돌린다 (한 번만 쓰는 도구).
// 앱이 zip을 풀 때 쓰는 것과 같은 방식(ZipNames)으로 코드 페이지를 골라 다시 읽는다.
//
//   dart run tool/fix_broken_names.dart <라이브러리 경로> [--apply]
//
// --apply 없이 실행하면 무엇이 바뀌는지만 보여준다.
// 레벨 파일(.adofai)이 있는 폴더를 레벨 하나로 보고, 그 레벨 파일에 적힌 이름과 견줘서 고른다.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tufapp/core/zip_names.dart';

void main(List<String> args) {
  final apply = args.contains('--apply');
  final root = args.firstWhere((a) => !a.startsWith('--'), orElse: () => '');
  if (root.isEmpty) {
    stderr.writeln('라이브러리 경로가 필요합니다.');
    exitCode = 2;
    return;
  }

  final log = <String>[];
  var levels = 0;
  var renamed = 0;

  for (final folder in _levelFolders(root)) {
    final entries = Directory(folder).listSync().where((e) => _isOwn(e, root)).toList();
    final broken = entries.where((e) => ZipNames.isRaw(p.basename(e.path))).toList();
    if (broken.isEmpty) continue;

    levels++;
    final fix = ZipNames.decoder(broken.map((e) => p.basename(e.path)), hint: _levelText(entries));

    for (final entry in broken) {
      final name = p.basename(entry.path);
      final fixed = fix(name);
      if (fixed == name) {
        log.add('그대로\t${entry.path}');
        continue;
      }

      final target = p.join(p.dirname(entry.path), fixed);
      if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
        log.add('건너뜀(이미 있음)\t${entry.path}\t$target');
        continue;
      }

      log.add('${apply ? "바꿈" : "바꿀 것"}\t${entry.path}\t$target');
      renamed++;
      if (apply) entry.renameSync(target);
    }
  }

  stdout.writeln(log.join('\n'));
  stdout.writeln('레벨 $levels개, 이름 $renamed개');
}

/// 레벨 파일(.adofai)이 들어 있는 폴더들. 그 아래에 또 레벨이 있으면 그것도 따로 센다.
Iterable<String> _levelFolders(String root) sync* {
  final seen = <String>{};
  for (final entry in Directory(root).listSync(recursive: true)) {
    if (entry is! File || !entry.path.toLowerCase().endsWith('.adofai')) continue;
    final folder = p.dirname(entry.path);
    if (seen.add(folder)) yield folder;
  }
}

/// 그 폴더에 바로 든 것들만 본다 (아래에 또 레벨이 있으면 그 레벨이 자기 이름을 고친다).
bool _isOwn(FileSystemEntity entry, String root) =>
    entry is File || Directory(entry.path).listSync().every((child) => !child.path.toLowerCase().endsWith('.adofai'));

/// 같은 폴더의 레벨 파일. 어떤 코드 페이지로 읽어야 하는지 고를 때 견준다.
String? _levelText(List<FileSystemEntity> entries) {
  final texts = <String>[];
  for (final entry in entries) {
    if (entry is! File || !entry.path.toLowerCase().endsWith('.adofai')) continue;
    if (entry.lengthSync() > ZipNames.hintLimit) continue;
    texts.add(const Utf8Decoder(allowMalformed: true).convert(entry.readAsBytesSync()));
  }
  return texts.isEmpty ? null : texts.join('\n');
}

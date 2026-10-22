// Restores garbled file names in levels downloaded earlier (a one-off tool).
// Picks the code page and decodes again the same way the app does when extracting (ZipNames).
//
//   dart run tool/fix_broken_names.dart <library path> [--apply]
//
// Without --apply it only shows what would change.
// Each folder with a level file (.adofai) is one level, and names are matched against that level file.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tufapp/core/zip_names.dart';

void main(List<String> args) {
  final apply = args.contains('--apply');
  final root = args.firstWhere((a) => !a.startsWith('--'), orElse: () => '');
  if (root.isEmpty) {
    stderr.writeln('A library path is required.');
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
        log.add('unchanged\t${entry.path}');
        continue;
      }

      final target = p.join(p.dirname(entry.path), fixed);
      if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
        log.add('skipped (exists)\t${entry.path}\t$target');
        continue;
      }

      log.add('${apply ? "renamed" : "would rename"}\t${entry.path}\t$target');
      renamed++;
      if (apply) entry.renameSync(target);
    }
  }

  stdout.writeln(log.join('\n'));
  stdout.writeln('$levels levels, $renamed names');
}

/// Folders containing a level file (.adofai). Nested levels below them count separately.
Iterable<String> _levelFolders(String root) sync* {
  final seen = <String>{};
  for (final entry in Directory(root).listSync(recursive: true)) {
    if (entry is! File || !entry.path.toLowerCase().endsWith('.adofai')) continue;
    final folder = p.dirname(entry.path);
    if (seen.add(folder)) yield folder;
  }
}

/// Only direct children (a nested level fixes its own names).
bool _isOwn(FileSystemEntity entry, String root) =>
    entry is File || Directory(entry.path).listSync().every((child) => !child.path.toLowerCase().endsWith('.adofai'));

/// The level file in the same folder, used to pick the code page.
String? _levelText(List<FileSystemEntity> entries) {
  final texts = <String>[];
  for (final entry in entries) {
    if (entry is! File || !entry.path.toLowerCase().endsWith('.adofai')) continue;
    if (entry.lengthSync() > ZipNames.hintLimit) continue;
    texts.add(const Utf8Decoder(allowMalformed: true).convert(entry.readAsBytesSync()));
  }
  return texts.isEmpty ? null : texts.join('\n');
}

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Decodes file names stored in a zip.
///
/// Zips have a flag marking names as UTF-8, but old archivers store names without it in the machine's code page
/// (949 for Korean, 932 for Japanese, ...). The archive package returns such names byte for byte (one char per byte),
/// so extracting them as is turns '자산 49oz.png' into 'À¯»ê 49oz.png' and the level can't find its music.
/// This picks a code page and decodes again (the same thing 7-Zip and NanaZip do).
abstract final class ZipNames {
  /// Tried after the machine's code page: Korean, Japanese, Simplified Chinese, Traditional Chinese, Western European.
  static const _fallbacks = [949, 932, 936, 950, 1252];

  /// Maximum size of the level file read to verify decoded names.
  static const hintLimit = 32 * 1024 * 1024;

  /// Whether the name holds raw bytes (every char fits in one byte and some are non-ASCII).
  static bool isRaw(String name) {
    var high = false;
    for (final unit in name.codeUnits) {
      if (unit > 0xFF) return false;
      if (unit >= 0x80) high = true;
    }
    return high;
  }

  static Uint8List bytesOf(String name) => Uint8List.fromList(name.codeUnits);

  /// Decides which code page to decode [names] with and returns a function that fixes a name.
  ///
  /// [hint] is the content of the level file (.adofai). It lists the music and image file names,
  /// so a decoded name that appears there was decoded correctly. Code pages confirmed this way are tried first;
  /// otherwise the machine's code page is used (the same result as extracting with NanaZip).
  /// Each name is decided separately, even if one zip mixes code pages.
  static String Function(String) decoder(Iterable<String> names, {String? hint}) {
    String unchanged(String name) => name;

    final raw = {
      for (final name in names)
        if (isRaw(name)) name,
    };
    if (raw.isEmpty || !Platform.isWindows) return unchanged;

    final pages = _codePages();

    // Decode each name with every code page (dropping pages that reject some byte).
    final options = <String, Map<int, String>>{};
    for (final name in raw) {
      final bytes = bytesOf(name);
      final read = <int, String>{};
      for (final page in pages) {
        final text = decode(page, bytes);
        if (text != null) read[page] = text;
      }
      if (read.isNotEmpty) options[name] = read;
    }
    if (options.isEmpty) return unchanged;

    // A code page gets a vote when its result matches a name in the level file.
    final votes = <int, int>{};
    final matched = <String, String>{};
    if (hint != null) {
      for (final entry in options.entries) {
        for (final read in entry.value.entries) {
          if (!hint.contains(_fileName(read.value))) continue;
          votes[read.key] = (votes[read.key] ?? 0) + 1;
          matched.putIfAbsent(entry.key, () => read.value);
        }
      }
    }

    // Most votes first; ties keep the original order (the machine's code page first).
    final order = [...pages]
      ..sort((a, b) {
        final byVotes = (votes[b] ?? 0).compareTo(votes[a] ?? 0);
        return byVotes != 0 ? byVotes : pages.indexOf(a).compareTo(pages.indexOf(b));
      });

    final fixed = <String, String>{};
    for (final entry in options.entries) {
      final byHint = matched[entry.key];
      if (byHint != null) {
        fixed[entry.key] = byHint;
        continue;
      }
      for (final page in order) {
        final text = entry.value[page];
        if (text != null) {
          fixed[entry.key] = text;
          break;
        }
      }
    }

    return (name) => fixed[name] ?? name;
  }

  /// The machine's code page first, then the common ones.
  static List<int> _codePages() {
    final system = _systemCodePage();
    return [?system, ..._fallbacks.where((page) => page != system)];
  }

  static String _fileName(String path) {
    final slash = path.replaceAll('\\', '/').lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// Decodes [bytes] with [codePage], or null if some byte is invalid in it.
  static String? decode(int codePage, Uint8List bytes) {
    if (bytes.isEmpty) return '';
    final convert = _multiByteToWideChar;
    if (convert == null) return null;

    final source = malloc<Uint8>(bytes.length);
    try {
      source.asTypedList(bytes.length).setAll(0, bytes);
      final length = convert(codePage, _errInvalidChars, source, bytes.length, nullptr, 0);
      if (length <= 0) return null;

      final target = malloc<Uint16>(length);
      try {
        final written = convert(codePage, _errInvalidChars, source, bytes.length, target, length);
        if (written <= 0) return null;
        return String.fromCharCodes(target.asTypedList(written));
      } finally {
        malloc.free(target);
      }
    } finally {
      malloc.free(source);
    }
  }

  /// Makes invalid bytes fail the conversion (MB_ERR_INVALID_CHARS).
  static const _errInvalidChars = 8;

  static bool _loaded = false;
  static int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>, int)? _convert;
  static int Function()? _acp;

  static void _load() {
    if (_loaded) return;
    _loaded = true;
    if (!Platform.isWindows) return;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _convert = kernel32
          .lookup<NativeFunction<Int32 Function(Uint32, Uint32, Pointer<Uint8>, Int32, Pointer<Uint16>, Int32)>>(
            'MultiByteToWideChar',
          )
          .asFunction();
      _acp = kernel32.lookup<NativeFunction<Uint32 Function()>>('GetACP').asFunction();
    } on ArgumentError {
      // Leave names as is when not on Windows or the function can't be found.
    }
  }

  static int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>, int)? get _multiByteToWideChar {
    _load();
    return _convert;
  }

  static int? _systemCodePage() {
    _load();
    final acp = _acp;
    if (acp == null) return null;
    final page = acp();
    // 65001 (UTF-8) was already tried by the archive package.
    return page == 65001 ? null : page;
  }
}

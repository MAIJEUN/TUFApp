import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// zip 안에 적힌 파일 이름을 제대로 읽어 온다.
///
/// zip에는 "이름을 UTF-8로 적었다"는 표시가 있는데, 옛 압축 도구들은 그 표시 없이
/// 그 컴퓨터의 코드 페이지(한국어 949, 일본어 932 …)로 이름을 적는다.
/// archive 패키지는 그런 이름을 바이트 그대로(한 글자당 한 바이트) 돌려주기 때문에,
/// 그대로 풀면 '자산 49oz.png'가 'À¯»ê 49oz.png'처럼 깨져서 레벨이 노래를 못 찾는다.
/// 여기서 코드 페이지를 골라 다시 읽는다 (7-Zip·NanaZip이 하는 일과 같다).
abstract final class ZipNames {
  /// 이 컴퓨터의 코드 페이지 다음으로 시도할 것들. 한국어·일본어·중국어·번체·서유럽 순.
  static const _fallbacks = [949, 932, 936, 950, 1252];

  /// 바뀐 이름이 맞는지 볼 때 읽어 들일 레벨 파일의 최대 크기.
  static const hintLimit = 32 * 1024 * 1024;

  /// 바이트가 그대로 담겨 온 이름인가 (모든 글자가 한 바이트 안에 들고, ASCII가 아닌 글자가 있다).
  static bool isRaw(String name) {
    var high = false;
    for (final unit in name.codeUnits) {
      if (unit > 0xFF) return false;
      if (unit >= 0x80) high = true;
    }
    return high;
  }

  static Uint8List bytesOf(String name) => Uint8List.fromList(name.codeUnits);

  /// [names]를 어떤 코드 페이지로 읽을지 정해서, 이름을 고치는 함수를 돌려준다.
  ///
  /// [hint]는 레벨 파일(.adofai)의 내용이다. 거기에는 노래·그림 파일 이름이 적혀 있으므로,
  /// 고친 이름이 거기에 나오면 제대로 읽은 것이다. 그렇게 확인된 코드 페이지를 먼저 쓰고,
  /// 확인할 수 없으면 이 컴퓨터의 코드 페이지를 쓴다 (NanaZip으로 풀었을 때와 같은 결과).
  /// 한 zip 안에 서로 다른 코드 페이지로 적힌 이름이 섞여 있어도 이름마다 따로 고른다.
  static String Function(String) decoder(Iterable<String> names, {String? hint}) {
    String unchanged(String name) => name;

    final raw = {
      for (final name in names)
        if (isRaw(name)) name,
    };
    if (raw.isEmpty || !Platform.isWindows) return unchanged;

    final pages = _codePages();

    // 이름마다 코드 페이지별로 읽어 본다 (그 코드 페이지에 없는 바이트가 있으면 빠진다).
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

    // 레벨 파일에 적힌 이름과 들어맞으면 그 코드 페이지에 표를 준다.
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

    // 표를 많이 받은 코드 페이지부터, 같으면 원래 순서대로 (이 컴퓨터의 것이 먼저).
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

  /// 이 컴퓨터의 코드 페이지를 먼저, 그다음 흔한 것들을 시도한다.
  static List<int> _codePages() {
    final system = _systemCodePage();
    return [?system, ..._fallbacks.where((page) => page != system)];
  }

  static String _fileName(String path) {
    final slash = path.replaceAll('\\', '/').lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// [bytes]를 [codePage]로 읽는다. 그 코드 페이지에 없는 바이트가 섞여 있으면 null.
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

  /// 읽을 수 없는 바이트가 있으면 실패로 처리하게 하는 표시 (MB_ERR_INVALID_CHARS).
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
      // 윈도가 아니거나 함수를 찾지 못하면 이름을 그대로 둔다.
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
    // 65001(UTF-8)은 이미 archive가 해 본 방식이라 후보에서 뺀다.
    return page == 65001 ? null : page;
  }
}

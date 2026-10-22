import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'tuf_api_client.dart';

class DownloadProgress {
  const DownloadProgress(this.bytesReceived, this.totalBytes);

  final int bytesReceived;
  final int? totalBytes;

  double? get fraction => (totalBytes ?? 0) > 0 ? bytesReceived / totalBytes! : null;
}

class OperationCancelledException implements Exception {
  const OperationCancelledException();

  @override
  String toString() => tr('취소됨', 'Cancelled');
}

class CancelToken {
  bool _cancelled = false;
  final Completer<void> _whenCancelled = Completer<void>();

  bool get isCancelled => _cancelled;

  /// 취소되는 순간 끝난다. 데이터가 오지 않고 멈춘 받기도 바로 멈출 수 있게 쓴다.
  Future<void> get whenCancelled => _whenCancelled.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _whenCancelled.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelledException();
  }
}

class LevelDownloader {
  LevelDownloader(this._api);

  static const _reportInterval = Duration(milliseconds: 100);

  /// 이만큼 아무 데이터도 오지 않으면 연결이 멈춘 것으로 보고 실패시킨다.
  static const idleTimeout = Duration(seconds: 30);

  final TufApiClient _api;

  /// TUF CDN에 올라간 zip 링크인지 확인. 구글 드라이브 등 외부 링크는 직접 받을 수 없다.
  static bool isTufCdnLink(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    return host == 'cdn.tuforums.com' || (host == 'api.tuforums.com' && uri.path.toLowerCase().startsWith('/cdn/'));
  }

  /// [url]을 [destinationPath]에 받는다. ".part" 파일에 먼저 쓰고, 끝까지 받은 경우에만 최종 경로로 옮긴다.
  Future<void> download(
    String url,
    String destinationPath, {
    void Function(DownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final response = await _api.openDownload(url);
    final total = response.contentLength;
    final partFile = File('$destinationPath.part');
    final sink = partFile.openWrite();

    var received = 0;
    var lastReport = DateTime.now();
    var sinkClosed = false;
    var completed = false;

    try {
      onProgress?.call(DownloadProgress(0, total));

      // 데이터가 오는 동안 받고, 취소되거나 한동안 아무것도 오지 않으면 바로 구독을 끊는다
      // (구독을 끊으면 연결도 닫힌다). 조각이 올 때만 취소를 확인하면 멈춘 연결은 영영 끝나지 않는다.
      final finished = Completer<void>();
      final subscription = response.stream
          .timeout(idleTimeout)
          .listen(
            (chunk) {
              sink.add(chunk);
              received += chunk.length;
              final now = DateTime.now();
              if (now.difference(lastReport) >= _reportInterval) {
                lastReport = now;
                onProgress?.call(DownloadProgress(received, total));
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!finished.isCompleted) finished.completeError(error, stack);
            },
            onDone: () {
              if (!finished.isCompleted) finished.complete();
            },
            cancelOnError: true,
          );
      unawaited(
        cancelToken?.whenCancelled.then((_) {
          if (!finished.isCompleted) finished.completeError(const OperationCancelledException());
        }),
      );
      try {
        await finished.future;
      } on TimeoutException {
        throw TufApiException(
          tr(
            '다운로드가 ${idleTimeout.inSeconds}초 동안 멈춰서 중단했습니다.',
            'The download stalled for ${idleTimeout.inSeconds} seconds and was stopped.',
          ),
        );
      } on http.ClientException catch (e) {
        throw TufApiException(tr('다운로드가 중간에 끊겼습니다: ${e.message}', 'The download was interrupted: ${e.message}'));
      } finally {
        await subscription.cancel();
      }

      await sink.close();
      sinkClosed = true;

      if (total != null && received != total) {
        throw TufApiException(
          tr('다운로드가 중간에 끊겼습니다. ($received/$total bytes)', 'The download was interrupted. ($received/$total bytes)'),
        );
      }

      onProgress?.call(DownloadProgress(received, total));
      await partFile.rename(destinationPath);
      completed = true;
    } finally {
      if (!sinkClosed) await sink.close();
      if (!completed) {
        try {
          await partFile.delete();
        } on FileSystemException {
          // 이미 없으면 무시
        }
      }
    }
  }
}

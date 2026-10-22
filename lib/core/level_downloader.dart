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

  /// Completes as soon as the token is cancelled, so even a stalled download can stop right away.
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

  /// A download that receives no data for this long is treated as stalled and fails.
  static const idleTimeout = Duration(seconds: 30);

  final TufApiClient _api;

  /// Whether the link is a zip on the TUF CDN. External links (Google Drive etc.) can't be downloaded directly.
  static bool isTufCdnLink(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    return host == 'cdn.tuforums.com' || (host == 'api.tuforums.com' && uri.path.toLowerCase().startsWith('/cdn/'));
  }

  /// Downloads [url] to [destinationPath]. Writes to a ".part" file first and moves it into place only when complete.
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

      // Read while data arrives; cancel the subscription (which closes
      // the connection) on cancel or after a quiet period.
      // Checking for cancellation only when a chunk arrives would never end a stalled connection.
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
          // Already gone.
        }
      }
    }
  }
}

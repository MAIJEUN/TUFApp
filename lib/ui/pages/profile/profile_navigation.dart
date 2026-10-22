import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/controllers.dart';
import '../../../core/l10n.dart';
import '../../../core/tuf_api_client.dart';
import '../level_viewer_page.dart';
import '../pass_viewer_page.dart';
import 'creator_profile_page.dart';
import 'player_profile_page.dart';

/// 프로필 화면에서 다른 화면으로 가는 길. id만 있는 대상은 먼저 받아 온 뒤 연다.
abstract final class ProfileNavigation {
  static Future<void> openPlayer(BuildContext context, int playerId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => PlayerProfilePage(playerId: playerId)));

  static Future<void> openCreator(BuildContext context, int creatorId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => CreatorProfilePage(creatorId: creatorId)));

  /// 레벨 자세히 보기.
  static Future<void> openLevel(BuildContext context, int levelId) =>
      _open(context, tr('레벨을 열지 못했습니다', "Couldn't open the level"), () async {
        final level = await AppScope.of(context).api.getLevel(levelId);
        return (context) => LevelViewerPage.open(context, level);
      });

  /// 기록 자세히 보기. 기록과 그 레벨을 받아 온다.
  static Future<void> openPass(BuildContext context, int passId) =>
      _open(context, tr('클리어를 열지 못했습니다', "Couldn't open the pass"), () async {
        final api = AppScope.of(context).api;
        final detail = await api.getPass(passId);
        final levelId = detail.pass.levelId;
        if (levelId == null) throw TufApiException(tr('기록의 레벨을 알 수 없습니다.', 'The level of this pass is unknown.'));
        final level = await api.getLevel(levelId);
        // 받아 둔 기록 정보를 넘겨서 클리어 화면이 같은 것을 다시 받지 않게 한다.
        return (context) => PassViewerPage.open(context, level: level, pass: detail.pass, detail: detail);
      });

  /// 받아 오는 중이면 또 누른 것은 무시한다 (같은 화면이 두 번 열리지 않게).
  static bool _opening = false;

  /// [load]로 필요한 것을 받은 뒤, 돌려준 함수로 화면을 연다.
  /// 0.2초 넘게 걸리면 맨 위에 진행 막대를 보여주고, 실패하면 지금 보이는 화면에 알린다
  /// (아래 상태 줄은 다른 화면에 가려져 있을 수 있다).
  static Future<void> _open(
    BuildContext context,
    String failText,
    Future<void Function(BuildContext context)> Function() load,
  ) async {
    if (_opening) return;
    _opening = true;
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    OverlayEntry? progress;
    final showProgress = Timer(const Duration(milliseconds: 200), () {
      if (overlay == null) return;
      progress = OverlayEntry(builder: (context) => const _OpeningProgress());
      overlay.insert(progress!);
    });

    try {
      final show = await load();
      showProgress.cancel();
      progress?.remove();
      progress = null;
      // 연 화면이 닫힐 때까지 기다리지 않는다. 기다리면 그 화면 안에서 또 여는 것이 막힌다.
      if (context.mounted) show(context);
    } on TufApiException catch (e) {
      final text = '$failText: ${e.message}';
      app.setStatus(text);
      messenger?.showSnackBar(SnackBar(content: Text(text)));
    } finally {
      showProgress.cancel();
      progress?.remove();
      _opening = false;
    }
  }

  /// 팩 화면으로 가서 그 팩을 연다.
  static Future<void> openPack(BuildContext context, String packRef) async {
    final app = AppScope.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    app.setPage(AppPage.packs);
    if (!await app.packs.openById(packRef)) app.setStatus(tr('팩을 열지 못했습니다.', "Couldn't open the pack."));
  }

  /// 그 사람이 만든 팩을 팩 화면에서 찾는다 (사이트의 '사용자 팩 보기').
  static void openPacksOf(BuildContext context, String handle) {
    final app = AppScope.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    app.packs.close();
    app.setPage(AppPage.packs);
    app.packs.setQuery('owner:$handle');
  }
}

/// 다른 화면을 받아 오는 동안 맨 위에 보이는 얇은 진행 막대.
class _OpeningProgress extends StatelessWidget {
  const _OpeningProgress();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.topCenter,
    child: IgnorePointer(child: LinearProgressIndicator(minHeight: 3)),
  );
}

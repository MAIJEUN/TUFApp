import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/controllers.dart';
import '../../../core/l10n.dart';
import '../../../core/tuf_api_client.dart';
import '../level_viewer_page.dart';
import '../pass_viewer_page.dart';
import 'creator_profile_page.dart';
import 'player_profile_page.dart';

/// Navigation from profile pages. Targets known only by id are fetched before opening.
abstract final class ProfileNavigation {
  static Future<void> openPlayer(BuildContext context, int playerId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => PlayerProfilePage(playerId: playerId)));

  static Future<void> openCreator(BuildContext context, int creatorId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => CreatorProfilePage(creatorId: creatorId)));

  static Future<void> openLevel(BuildContext context, int levelId) =>
      _open(context, l10n.couldntOpenTheLevel, () async {
        final level = await AppScope.of(context).api.getLevel(levelId);
        return (context) => LevelViewerPage.open(context, level);
      });

  /// Opens pass details, fetching the pass and its level.
  static Future<void> openPass(BuildContext context, int passId) => _open(context, l10n.couldntOpenThePass, () async {
    final api = AppScope.of(context).api;
    final detail = await api.getPass(passId);
    final levelId = detail.pass.levelId;
    if (levelId == null) throw TufApiException(l10n.theLevelOfThis);
    final level = await api.getLevel(levelId);
    // Pass the fetched details along so the pass page doesn't fetch them again.
    return (context) => PassViewerPage.open(context, level: level, pass: detail.pass, detail: detail);
  });

  /// Taps while something is loading are ignored, so the same page never opens twice.
  static bool _opening = false;

  /// Fetches what's needed with [load], then opens the page with the returned function.
  /// Shows a progress bar at the top after 0.2 s, and reports failures on the visible page
  /// (the status line below may be covered by another page).
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
      // Don't wait for the opened page to close; waiting would block opening another page from inside it.
      if (context.mounted) show(context);
    } on Object catch (e) {
      final text = '$failText: ${e is TufApiException ? e.message : e}';
      app.setStatus(text);
      messenger?.showSnackBar(SnackBar(content: Text(text)));
    } finally {
      showProgress.cancel();
      progress?.remove();
      _opening = false;
    }
  }

  /// Switches to the packs page and opens the pack.
  static Future<void> openPack(BuildContext context, String packRef) async {
    final app = AppScope.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    app.setPage(AppPage.packs);
    if (!await app.packs.openById(packRef)) app.setStatus(l10n.couldntOpenThePack);
  }

  /// Searches the packs page for packs made by this user (the website's "View user's packs").
  static void openPacksOf(BuildContext context, String handle) {
    final app = AppScope.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    app.packs.close();
    app.setPage(AppPage.packs);
    app.packs.setQuery('owner:$handle');
  }
}

/// Thin progress bar at the top while another page loads.
class _OpeningProgress extends StatelessWidget {
  const _OpeningProgress();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.topCenter,
    child: IgnorePointer(child: LinearProgressIndicator(minHeight: 3)),
  );
}

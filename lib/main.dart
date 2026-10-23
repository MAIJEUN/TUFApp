import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/controllers.dart';
import 'core/frame_log.dart';
import 'core/l10n.dart';
import 'core/level_manager.dart';
import 'ui/app_shell.dart';
import 'ui/app_shortcuts.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Logs slow frames when run with TUFAPP_PERF=1 (does nothing otherwise).
  FrameLog.start();
  // Registers the license of the bundled Roboto font.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Roboto'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  // Read settings first so the first frame is already in the chosen language. If
  // this fails, initialize reads them again and shows the error.
  AppSettings? settings;
  try {
    settings = await AppSettings.load();
  } on FileSystemException {
    settings = null;
  }
  appLanguage = settings?.language ?? AppLanguage.system;

  final controller = AppController()
    ..languageChoice = settings?.language
    ..zoom = settings?.zoom ?? 1;
  runApp(TufApp(controller: controller));
  controller.initialize(settings: settings);
}

/// Rebuilds the whole tree when the language changes (page, scroll positions and open routes are kept).
class TufApp extends StatefulWidget {
  const TufApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<TufApp> createState() => _TufAppState();
}

class _TufAppState extends State<TufApp> {
  late AppLanguage _shown = appLanguage;
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _observer = AppNavigatorObserver(widget.controller.history);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAppChanged);
  }

  @override
  void didUpdateWidget(TufApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onAppChanged);
      widget.controller.addListener(_onAppChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAppChanged);
    super.dispose();
  }

  void _onAppChanged() {
    if (_shown == appLanguage) return;
    _shown = appLanguage;
    // Text is read from l10n during build, so rebuilding every element switches the language.
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => AppScope(
    controller: widget.controller,
    child: MaterialApp(
      title: 'TUFApp',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: _navigatorKey,
      navigatorObservers: [_observer],
      builder: (context, child) =>
          AppShortcuts(app: widget.controller, navigatorKey: _navigatorKey, observer: _observer, child: child!),
      home: const AppShell(),
    ),
  );
}

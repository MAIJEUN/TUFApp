import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/controllers.dart';
import 'core/frame_log.dart';
import 'core/l10n.dart';
import 'core/level_manager.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TUFAPP_PERF=1로 실행하면 느린 프레임을 기록한다 (평소에는 아무 일도 하지 않는다).
  FrameLog.start();
  // 함께 넣은 Roboto 글꼴의 라이선스를 앱 라이선스 목록에 올린다.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Roboto'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  // 첫 화면부터 고른 언어로 보이게 설정을 먼저 읽는다. 못 읽으면 initialize가 다시 읽고 오류를 보여 준다.
  AppSettings? settings;
  try {
    settings = await AppSettings.load();
  } on FileSystemException {
    settings = null;
  }
  appLanguage = settings?.language ?? AppLanguage.system;

  final controller = AppController()..languageChoice = settings?.language;
  runApp(TufApp(controller: controller));
  controller.initialize(settings: settings);
}

/// 언어를 바꾸면 화면 전체를 다시 그린다 (페이지·스크롤 위치·열린 화면은 그대로 둔다).
class TufApp extends StatefulWidget {
  const TufApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<TufApp> createState() => _TufAppState();
}

class _TufAppState extends State<TufApp> {
  late AppLanguage _shown = appLanguage;

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
    // 글은 build에서 tr()로 고르므로, 모든 위젯을 다시 빌드하면 새 언어로 바뀐다.
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
      home: const AppShell(),
    ),
  );
}

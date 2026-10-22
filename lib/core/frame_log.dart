import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// 느린 프레임을 기록하는 진단 도구.
///
/// 환경 변수 `TUFAPP_PERF=1`로 실행할 때만 켜진다. 평소에는 아무 일도 하지 않는다.
/// 켜면 정해진 시간을 넘긴 프레임과, 끝날 때 전체 요약을 표준 출력으로 남긴다.
abstract final class FrameLog {
  /// 60Hz 기준 한 프레임 예산.
  static const _budget = Duration(milliseconds: 16);

  static int _frames = 0;
  static int _slow = 0;
  static Duration _worstBuild = Duration.zero;
  static Duration _worstRaster = Duration.zero;
  static Duration _totalBuild = Duration.zero;
  static Duration _totalRaster = Duration.zero;

  static bool get enabled => Platform.environment['TUFAPP_PERF'] == '1';

  static void start() {
    if (!enabled) return;

    stdout.writeln('[perf] 프레임 기록을 시작합니다 (예산 ${_budget.inMilliseconds}ms)');
    // 가만히 있을 때도 프레임이 계속 그려지는지 보려고 주기적으로 요약한다.
    Timer.periodic(const Duration(seconds: 5), (_) => report('5초'));
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _frames++;
        _totalBuild += timing.buildDuration;
        _totalRaster += timing.rasterDuration;
        if (timing.buildDuration > _worstBuild) _worstBuild = timing.buildDuration;
        if (timing.rasterDuration > _worstRaster) _worstRaster = timing.rasterDuration;

        final total = timing.buildDuration + timing.rasterDuration;
        if (total <= _budget) continue;
        _slow++;
        _line('느린 프레임 build=${_ms(timing.buildDuration)} raster=${_ms(timing.rasterDuration)}');
      }
    });
  }

  /// 오래 걸린 작업을 한 줄 남긴다 (폴더 읽기 같은 것).
  static void note(String what, Duration elapsed, {String detail = ''}) {
    if (!enabled) return;
    _line('$what ${_ms(elapsed)}${detail.isEmpty ? '' : ' ($detail)'}');
  }

  /// 지금까지의 요약을 한 줄로 남긴다.
  static void report(String label) {
    if (!enabled) return;
    if (_frames == 0) {
      _line('$label: 프레임 없음');
      return;
    }
    _line(
      '$label: 프레임 $_frames개, 느린 프레임 $_slow개 '
      '(평균 build=${_ms(_totalBuild ~/ _frames)} raster=${_ms(_totalRaster ~/ _frames)}, '
      '최대 build=${_ms(_worstBuild)} raster=${_ms(_worstRaster)})',
    );
    _frames = 0;
    _slow = 0;
    _worstBuild = Duration.zero;
    _worstRaster = Duration.zero;
    _totalBuild = Duration.zero;
    _totalRaster = Duration.zero;
  }

  /// 시각을 붙여서 남긴다. 어느 화면에서 일어난 일인지 맞춰 보려고.
  static void _line(String text) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';
    stdout.writeln('[perf $time] $text');
  }

  static String _ms(Duration value) => '${(value.inMicroseconds / 1000).toStringAsFixed(1)}ms';
}

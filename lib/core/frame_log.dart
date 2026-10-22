import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Diagnostic logger for slow frames.
///
/// Only enabled with the environment variable `TUFAPP_PERF=1`; does nothing otherwise.
/// When enabled, writes frames over budget and periodic summaries to stdout.
abstract final class FrameLog {
  /// One frame at 60 Hz.
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

    stdout.writeln('[perf] logging frames (budget ${_budget.inMilliseconds}ms)');
    // Summarize periodically to see whether frames keep being drawn while idle.
    Timer.periodic(const Duration(seconds: 5), (_) => report('5s'));
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
        _line('slow frame build=${_ms(timing.buildDuration)} raster=${_ms(timing.rasterDuration)}');
      }
    });
  }

  /// Logs one line for a slow operation (like reading a folder).
  static void note(String what, Duration elapsed, {String detail = ''}) {
    if (!enabled) return;
    _line('$what ${_ms(elapsed)}${detail.isEmpty ? '' : ' ($detail)'}');
  }

  /// Logs a one-line summary so far.
  static void report(String label) {
    if (!enabled) return;
    if (_frames == 0) {
      _line('$label: no frames');
      return;
    }
    _line(
      '$label: $_frames frames, $_slow slow '
      '(avg build=${_ms(_totalBuild ~/ _frames)} raster=${_ms(_totalRaster ~/ _frames)}, '
      'max build=${_ms(_worstBuild)} raster=${_ms(_worstRaster)})',
    );
    _frames = 0;
    _slow = 0;
    _worstBuild = Duration.zero;
    _worstRaster = Duration.zero;
    _totalBuild = Duration.zero;
    _totalRaster = Duration.zero;
  }

  /// Prefixes a timestamp so lines can be matched with what happened on screen.
  static void _line(String text) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';
    stdout.writeln('[perf $time] $text');
  }

  static String _ms(Duration value) => '${(value.inMicroseconds / 1000).toStringAsFixed(1)}ms';
}

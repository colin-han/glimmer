import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fgs_runtime.dart';
import 'processing_fgs_backend.dart';

/// Processing FGS 的唯一管理者：启停 / 延时调度 / 状态 / 结束回调。
///
/// 状态收口到本类（isRunning 唯一真相源），RecordingPage / DiaryDetailPage
/// 都通过本类交互，避免散落的状态标志导致误判（缺陷 1 的根因）。
///
/// 竞态防护：start() 用 Timer（可 cancel）而非 await 做 delay。delay 期间
/// _isStarting=true（hasActivity=true），录音的 stop() 可 cancel Timer
/// （FGS 根本不会启动），从设计上避免 service already started 竞态。
///
/// Timer fire 后的"不可取消窗口"（backend.startProcessingFgs 在 platform 层
/// 进行中）由 _startCompleter 处理：stop() await 它（等启动完成）再 stopService。
class ProcessingFgsController {
  ProcessingFgsController._();

  @visibleForTesting
  static ProcessingFgsBackend backend = const FlutterForegroundTaskBackend();

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  /// 正在启动（Timer delay 期间 或 Timer fire 后 backend 进行中）。可被 stop 处理。
  static bool _isStarting = false;
  static Timer? _startTimer;
  static Completer<void>? _startCompleter;

  /// 有 processing 活动（在跑 / 正在启动 / 待延时启动）。
  static bool get hasActivity =>
      _isRunning || _isStarting || _scheduledTimer != null;

  static Timer? _scheduledTimer;
  static Completer<void>? _stopCompleter;

  /// 立即启动 processing FGS（唯一启动入口）。
  /// mode==recording 时拒绝，返回 false。
  ///
  /// 同步返回：_isStarting=true 立即生效（hasActivity=true），FGS 在 500ms 后
  /// 由 Timer 启动。stop() 可 cancel Timer（FGS 不启动），或等 backend 完成后
  /// stopService（Timer 已 fire 的窗口）。
  static bool start() {
    if (FgsRuntime.mode == FgsMode.recording) {
      debugPrint('[FGS-Ctrl] start: 拒绝（mode=recording）');
      return false;
    }
    if (_isRunning || _isStarting) {
      debugPrint(
        '[FGS-Ctrl] start: 幂等（_isRunning=$_isRunning _isStarting=$_isStarting）',
      );
      return true;
    }

    _isStarting = true;
    FgsRuntime.setProcessing();
    _startCompleter = Completer<void>();
    debugPrint('[FGS-Ctrl] start: _isStarting=true，500ms 后启动 FGS');
    _startTimer = Timer(const Duration(milliseconds: 500), () async {
      _startTimer = null;
      try {
        if (!_isStarting) return; // 被 stop cancel（Timer 还没 fire 时）
        final svcRunning = await backend.isServiceRunning();
        debugPrint('[FGS-Ctrl] start Timer: isServiceRunning=$svcRunning');
        if (svcRunning) {
          _isStarting = false;
          _isRunning = true;
          return;
        }
        final ok = await backend.startProcessingFgs();
        debugPrint('[FGS-Ctrl] start Timer: startProcessingFgs ok=$ok');
        _isStarting = false;
        if (ok) {
          _isRunning = true;
        } else {
          FgsRuntime.setNone();
        }
      } finally {
        // 无论成功/失败/cancel/异常，complete _startCompleter（让 stop 不永等）
        if (_startCompleter != null && !_startCompleter!.isCompleted) {
          _startCompleter!.complete();
        }
        _startCompleter = null;
      }
    });
    return true;
  }

  /// 停止 processing 的一切。
  ///
  /// 三阶段：
  /// 1. Timer 还没 fire → cancel Timer（FGS 不启动）
  /// 2. Timer 已 fire，backend 在进行中 → 等 _startCompleter（启动完成），再 stopService
  /// 3. FGS 在跑 → stopService + 等 onStopped
  static Future<void> stop() async {
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    debugPrint(
      '[FGS-Ctrl] stop: _isRunning=$_isRunning _isStarting=$_isStarting _startTimer=${_startTimer != null}',
    );

    // 阶段 1：Timer 还没 fire → cancel（FGS 根本不会启动）
    if (_startTimer != null) {
      debugPrint('[FGS-Ctrl] stop: 取消进行中的 start Timer（FGS 不启动），槽空闲');
      _startTimer!.cancel();
      _startTimer = null;
      _isStarting = false;
      if (_startCompleter != null && !_startCompleter!.isCompleted) {
        _startCompleter!.complete();
      }
      _startCompleter = null;
      FgsRuntime.setNone();
      return;
    }

    // 阶段 2：Timer 已 fire，backend.startProcessingFgs 在进行中 → 等完成再 stop
    if (_isStarting && _startCompleter != null) {
      debugPrint('[FGS-Ctrl] stop: Timer 已 fire，等 backend 启动完成后 stopService');
      await _startCompleter!.future;
      // 此时 _isRunning=true（启动成功）或 false（失败）
    }

    if (!_isRunning) {
      debugPrint('[FGS-Ctrl] stop: 未在跑，直接返回');
      return;
    }

    // 阶段 3：FGS 在跑 → stopService + 等 onStopped
    _stopCompleter = Completer<void>();
    backend.stopFgs();
    debugPrint('[FGS-Ctrl] stop: stopFgs 已调，等 onStopped（3s 超时）');
    bool timedOut = false;
    await _stopCompleter!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        timedOut = true;
        _isRunning = false;
        FgsRuntime.setNone();
      },
    );
    final svcRunningAfter = await backend.isServiceRunning();
    debugPrint(
      '[FGS-Ctrl] stop: 完成 timedOut=$timedOut isServiceRunning(后)=$svcRunningAfter',
    );
    _stopCompleter = null;
  }

  /// 延时启动（录音后 / app 启动恢复）。
  static Future<void> schedule({bool isStartup = false}) async {
    _scheduledTimer?.cancel();
    final delay = await backend.getProcessingDelay();
    final seconds = (delay <= 0) ? (isStartup ? 5 : 0) : delay;
    if (seconds == 0) {
      start();
      return;
    }
    _scheduledTimer = Timer(Duration(seconds: seconds), () {
      _scheduledTimer = null;
      start();
    });
  }

  /// FGS 自然结束回调（processingDone/completed/failed）或 stop 超时后调。
  static void onStopped() {
    debugPrint(
      '[FGS-Ctrl] onStopped: _isRunning=$_isRunning _isStarting=$_isStarting → false',
    );
    _isRunning = false;
    _isStarting = false;
    FgsRuntime.setNone();
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete();
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _isRunning = false;
    _isStarting = false;
    _startTimer?.cancel();
    _startTimer = null;
    if (_startCompleter != null && !_startCompleter!.isCompleted) {
      _startCompleter!.complete();
    }
    _startCompleter = null;
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    _stopCompleter = null;
  }
}

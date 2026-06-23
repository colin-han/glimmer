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
class ProcessingFgsController {
  ProcessingFgsController._();

  /// 平台依赖（可替换，测试注入 fake）。
  @visibleForTesting
  static ProcessingFgsBackend backend = const FlutterForegroundTaskBackend();

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  /// 正在启动（Timer delay 期间，startService 还没调）。可被 stop() 取消。
  static bool _isStarting = false;
  static Timer? _startTimer;

  /// 有 processing 活动（在跑 / 正在启动 / 待延时启动），供录音方判断要不要 stop。
  static bool get hasActivity =>
      _isRunning || _isStarting || _scheduledTimer != null;

  static Timer? _scheduledTimer;
  static Completer<void>? _stopCompleter;

  /// 立即启动 processing FGS（唯一启动入口）。
  /// mode==recording 时拒绝（别中断录音），返回 false。
  ///
  /// 同步返回：_isStarting=true 立即生效（hasActivity=true），FGS 在 500ms 后
  /// 由 Timer 启动。这 500ms 窗口内若录音 → stop() cancel Timer → FGS 不启动。
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
    debugPrint('[FGS-Ctrl] start: _isStarting=true，500ms 后启动 FGS');
    _startTimer = Timer(const Duration(milliseconds: 500), () async {
      _startTimer = null;
      if (!_isStarting) return; // 被 stop 取消
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
        FgsRuntime.setNone(); // 启动失败，回退
      }
    });
    return true;
  }

  /// 停止 processing 的一切：取消待执行延时 + 停正在跑的 FGS + 等它真停。
  /// 调用方 await 返回后，FGS 槽已释放，可立即启动录音 FGS。
  static Future<void> stop() async {
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    debugPrint(
      '[FGS-Ctrl] stop: _isRunning=$_isRunning _isStarting=$_isStarting',
    );

    // 正在启动（Timer delay 期间）→ cancel Timer，FGS 根本不会启动
    if (_startTimer != null) {
      debugPrint('[FGS-Ctrl] stop: 取消进行中的 start（FGS 不启动），槽空闲');
      _startTimer!.cancel();
      _startTimer = null;
      _isStarting = false;
      FgsRuntime.setNone();
      return; // FGS 没启动，录音可直接 startService(microphone)
    }

    if (!_isRunning) {
      debugPrint('[FGS-Ctrl] stop: 未在跑，直接返回');
      return;
    }

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

  /// 延时启动（录音后 / app 启动恢复）。读 backend.getProcessingDelay。
  /// isStartup=true 时 delay<=0 默认 5s；否则立即（delay<=0 直接 start）。
  static Future<void> schedule({bool isStartup = false}) async {
    _scheduledTimer?.cancel();
    final delay = await backend.getProcessingDelay();
    final seconds = (delay <= 0) ? (isStartup ? 5 : 0) : delay;
    if (seconds == 0) {
      start(); // 同步
      return;
    }
    _scheduledTimer = Timer(Duration(seconds: seconds), () {
      _scheduledTimer = null;
      start(); // start 内部检查 mode==recording + _isStarting Timer
    });
  }

  /// FGS 自然结束回调（processingDone/completed/failed）或 stop 超时后调。
  /// 由 store（ProcessingTaskStore._onTaskData）在收到结束消息时调用。
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

  /// 测试用：重置所有状态。
  @visibleForTesting
  static void resetForTesting() {
    _isRunning = false;
    _isStarting = false;
    _startTimer?.cancel();
    _startTimer = null;
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    _stopCompleter = null;
  }
}

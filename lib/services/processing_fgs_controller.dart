import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fgs_runtime.dart';
import 'processing_fgs_backend.dart';

/// Processing FGS 的唯一管理者：启停 / 延时调度 / 状态 / 结束回调。
///
/// 状态收口到本类（isRunning 唯一真相源），RecordingPage / DiaryDetailPage
/// 都通过本类交互，避免散落的状态标志导致误判（缺陷 1 的根因）。
class ProcessingFgsController {
  ProcessingFgsController._();

  /// 平台依赖（可替换，测试注入 fake）。
  @visibleForTesting
  static ProcessingFgsBackend backend = const FlutterForegroundTaskBackend();

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  /// 有 processing 活动（在跑 或 待延时启动），供录音方判断要不要 stop + 提示。
  static bool get hasActivity => _isRunning || _scheduledTimer != null;

  static Timer? _scheduledTimer;
  static Completer<void>? _stopCompleter;

  /// 立即启动 processing FGS（唯一启动入口）。
  /// mode==recording 时拒绝（别中断录音），返回 false。
  static Future<bool> start() async {
    if (FgsRuntime.mode == FgsMode.recording) return false;
    if (_isRunning) return true; // 幂等
    final ok = await backend.startProcessingFgs();
    if (!ok) return false;
    _isRunning = true;
    FgsRuntime.setProcessing();
    return true;
  }

  /// FGS 自然结束回调（processingDone/completed/failed）或 stop 超时后调。
  /// 由 RecordingPage / DiaryDetailPage 的 _onTaskData 在收到结束消息时调用。
  static void onStopped() {
    _isRunning = false;
    FgsRuntime.setNone();
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete(); // 通知 stop() 完成
    }
  }

  /// 测试用：重置所有状态。
  @visibleForTesting
  static void resetForTesting() {
    _isRunning = false;
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    _stopCompleter = null;
  }
}

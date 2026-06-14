import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'fgs_runtime.dart';
import 'recording_processor.dart' show processingCallback;

/// 启动 processing FGS 的公共入口。
///
/// 并发规则：若当前录音 FGS 在跑（`FgsRuntime.mode == recording`），返回 false
/// 且不启动——调用方应仅入队（resetEntryForReanalysis）+ 提示，录音结束后
/// `RecordingPage._scheduleProcessingFgs` 会拾取。
/// 否则 stopService + 启动 processing，成功返回 true。
class ProcessingFgsController {
  ProcessingFgsController._();

  /// 返回 true 表示已成功启动 processing FGS；
  /// false 表示未启动（录音中，或启动失败）。
  static Future<bool> start() async {
    if (FgsRuntime.mode == FgsMode.recording) {
      debugPrint('[ProcessingFgsController] 录音中，跳过启动 FGS');
      return false;
    }

    // 用 try/catch 兜底：startService 可能抛平台异常，统一返回 false，
    // 保证调用方（RecordingPage / DiaryDetailPage）无需再包 try/catch。
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(milliseconds: 500));

      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '正在处理',
        notificationText: '语音日记 - 处理中...',
        callback: processingCallback,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[ProcessingFgsController] 启动失败: ${result.error}');
        return false;
      }

      FgsRuntime.setProcessing();
      return true;
    } catch (e) {
      debugPrint('[ProcessingFgsController] 启动异常: $e');
      return false;
    }
  }
}

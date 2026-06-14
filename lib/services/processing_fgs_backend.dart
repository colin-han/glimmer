import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../pages/settings_page.dart' show SettingsPage;
import 'recording_processor.dart' show processingCallback;

/// 封装 ProcessingFgsController 的平台依赖（FlutterForegroundTask + SettingsPage），
/// 便于单测注入 fake。生产用 [FlutterForegroundTaskBackend]。
abstract interface class ProcessingFgsBackend {
  /// 启动 processing FGS（initCommunicationPort + stopService + delay + startService）。
  /// 返回 true 表示成功。
  Future<bool> startProcessingFgs();

  /// 停止 FGS（FlutterForegroundTask.stopService）。
  void stopFgs();

  /// 读取用户设置的 processing 延迟秒数（<=0 表示无延迟）。
  Future<int> getProcessingDelay();
}

class FlutterForegroundTaskBackend implements ProcessingFgsBackend {
  const FlutterForegroundTaskBackend();

  @override
  Future<bool> startProcessingFgs() async {
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
        debugPrint('[ProcessingFgsBackend] 启动失败: ${result.error}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[ProcessingFgsBackend] 启动异常: $e');
      return false;
    }
  }

  @override
  void stopFgs() => FlutterForegroundTask.stopService();

  @override
  Future<int> getProcessingDelay() => SettingsPage.getProcessingDelay();
}

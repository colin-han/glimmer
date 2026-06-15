import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'api_log_service.dart';
import 'asr_service.dart';
import 'daily_summary_processing_task.dart';
import 'daily_summary_service.dart';
import 'diary_processing_task.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'processing_task.dart';
import 'tos_upload_service.dart';

/// Processing FGS 入口函数
@pragma('vm:entry-point')
void processingCallback() {
  FlutterForegroundTask.setTaskHandler(ProcessingTaskHandler());
}

/// 确保 processing FGS 正在运行：未运行则启动（复用现有 channel / processingCallback）；
/// 已运行则不重复启动。供启动钩子、详情页重新生成、list 手动生成共用。
Future<void> ensureProcessingFgsRunning({
  String notificationText = '语音日记 - 处理中...',
}) async {
  if (await FlutterForegroundTask.isRunningService) return;
  FlutterForegroundTask.initCommunicationPort();
  final result = await FlutterForegroundTask.startService(
    serviceTypes: [ForegroundServiceTypes.dataSync],
    notificationTitle: '正在处理',
    notificationText: notificationText,
    callback: processingCallback,
  );
  if (result is ServiceRequestFailure) {
    debugPrint('[Processing] 启动 FGS 失败: ${result.error}');
  }
}

/// 处理阶段调度器，运行在 FGS isolate 中。
///
/// 查询录音（DiaryEntries status=processing）+ 每日总结（DailySummaries
/// status=processing）两类 pending 任务，分别包成 DiaryProcessingTask /
/// DailySummaryProcessingTask，录音在前、总结在后，依次 execute；错误隔离。
/// 具体处理逻辑在各 Task 内部。
class ProcessingTaskHandler extends TaskHandler {
  void _sendToMain(Map<String, dynamic> data) {
    FlutterForegroundTask.sendDataToMain(data);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ProcessingHandler] onStart');

    try {
      await dotenv.load(fileName: '.env.local');
    } catch (e) {
      debugPrint('[ProcessingHandler] dotenv.load 失败: $e');
    }

    final storage = DiaryStorageService();
    final ctx = ProcessingContext(
      storage: storage,
      llm: LlmService(),
      asr: AsrService(),
      tos: TosUploadService(),
      apiLog: ApiLogService(),
      dailySummary: DailySummaryService(),
      sendToMain: _sendToMain,
    );

    // 录音任务在前、每日总结在后（总结依赖当天录音已处理完成）
    final entries = await storage.getPendingEntries();
    final summaries = await storage.getPendingDailySummaries();
    final tasks = <ProcessingTask>[
      ...entries.map(DiaryProcessingTask.new),
      ...summaries.map((s) => DailySummaryProcessingTask(s.date)),
    ];

    if (tasks.isEmpty) {
      debugPrint('[ProcessingHandler] 无待处理任务，停止');
      _sendToMain({'type': 'processingDone'});
      await _stopService();
      return;
    }

    debugPrint('[ProcessingHandler] 待处理任务: ${tasks.length} 个');
    for (final task in tasks) {
      FlutterForegroundTask.updateService(
        notificationTitle: '正在处理',
        notificationText: task.notificationText,
      );
      try {
        await task.execute(ctx);
      } catch (e) {
        // 防御性兜底：Task 应自管失败，这里防止一个 Task 的未捕获异常中断其他
        debugPrint('[ProcessingHandler] task ${task.id} 未捕获异常: $e');
      }
    }

    debugPrint('[ProcessingHandler] 全部处理完成');
    _sendToMain({'type': 'processingDone'});
    await _stopService();
  }

  Future<void> _stopService() async {
    await Future.delayed(const Duration(seconds: 2));
    FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
    _sendToMain({
      'type': 'notificationPressed',
      'state': 'processing',
      'entryId': '',
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ProcessingHandler] onDestroy, isTimeout=$isTimeout');
    // 通知主 isolate 服务已停止，避免用户等待时 UI 卡住
    _sendToMain({'type': 'processingDone'});
  }
}

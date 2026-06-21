import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/processing_task.dart' as task_model;
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

/// 处理阶段调度器，运行在 FGS isolate 中。
///
/// 查询 processing_tasks 表的所有活跃任务（queued + running），按 task_type
/// 分发：diary → getEntryById 后构造 DiaryProcessingTask，daily_summary →
/// DailySummaryProcessingTask。diary 在前、summary 在后（summary 依赖当天
/// diary 已处理完成），依次 execute；错误隔离。具体处理逻辑在各 Task 内部。
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

    // 统一查 processing_tasks 表，按 task_type 分发
    final pendingTasks = await storage.getPendingProcessingTasks();
    if (pendingTasks.isEmpty) {
      debugPrint('[ProcessingHandler] 无待处理任务，停止');
      _sendToMain({'type': 'processingDone'});
      await _stopService();
      return;
    }

    // diary 在前、summary 在后（summary 依赖当天 diary 已处理完成）
    pendingTasks.sort((a, b) {
      final aDiary = a.taskType == task_model.TaskType.diary ? 0 : 1;
      final bDiary = b.taskType == task_model.TaskType.diary ? 0 : 1;
      return aDiary.compareTo(bDiary);
    });

    debugPrint('[ProcessingHandler] 待处理任务: ${pendingTasks.length} 个');
    for (final t in pendingTasks) {
      FlutterForegroundTask.updateService(
        notificationTitle: '正在处理',
        notificationText: _notificationFor(t),
      );
      try {
        if (t.taskType == task_model.TaskType.diary) {
          final entry = await storage.getEntryById(t.refId);
          await DiaryProcessingTask(entry, t).execute(ctx);
        } else {
          await DailySummaryProcessingTask(t).execute(ctx);
        }
      } catch (e) {
        // 防御性兜底：Task 应自管失败，这里防止一个 Task 的未捕获异常中断其他
        debugPrint('[ProcessingHandler] task ${t.id} 未捕获异常: $e');
      }
    }

    debugPrint('[ProcessingHandler] 全部处理完成');
    _sendToMain({'type': 'processingDone'});
    await _stopService();
  }

  String _notificationFor(task_model.ProcessingTask t) {
    return t.taskType == task_model.TaskType.diary
        ? '语音日记 - 处理中...'
        : '生成每日总结（${t.refId}）';
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

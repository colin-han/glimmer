import 'api_log_service.dart';
import 'asr_service.dart';
import 'daily_summary_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'tos_upload_service.dart';

/// 处理任务的统一抽象。录音处理与每日总结各封装为一个 Task，
/// 由 ProcessingTaskHandler 调度器统一拉起、顺序执行、错误隔离。
abstract class ProcessingTask {
  /// 任务标识：录音为 entryId，每日总结为日期 'yyyy-MM-dd'。
  String get id;

  /// 任务类型：'diary' | 'daily_summary'。
  String get taskType;

  /// FGS 通知文案。
  String get notificationText;

  /// 执行任务。失败时由 Task 自行标记 status=failed + 通知主 isolate，
  /// 不向上抛（保证调度器错误隔离）。
  Future<void> execute(ProcessingContext ctx);
}

/// Task 执行时共享的依赖容器，避免每个 Task 各自 new service。
class ProcessingContext {
  final DiaryStorageService storage;
  final LlmService llm;
  final AsrService asr;
  final TosUploadService tos;
  final ApiLogService apiLog;
  final DailySummaryService dailySummary;

  /// 向主 isolate 发送消息（封装 FlutterForegroundTask.sendDataToMain）。
  final void Function(Map<String, dynamic>) sendToMain;

  const ProcessingContext({
    required this.storage,
    required this.llm,
    required this.asr,
    required this.tos,
    required this.apiLog,
    required this.dailySummary,
    required this.sendToMain,
  });
}

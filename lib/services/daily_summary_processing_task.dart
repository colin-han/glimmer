import 'package:flutter/foundation.dart';

import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import '../models/processing_task.dart' as task_model;
import 'processing_task.dart';

/// 每日总结处理任务：把指定日期当天所有录音的 ASR 全文重组为一篇总结。
///
/// 持有 model ProcessingTask（refId=date），写 task.status（completed/failed）。
/// daily_summary 表的 status 列废弃（任务状态以 processing_tasks 表为准），
/// 写入时给一个固定值占位（不读）。
///
/// 流程：查当天 entries → 0 篇空完成 / 有 processing 篇判 failed / 否则
/// summarizeDay 聚合 → 写正文文件 + 更新元数据 + task.status。失败时标记
/// task.status=failed + 通知，不向上抛。
class DailySummaryProcessingTask implements ProcessingTask {
  final task_model.ProcessingTask task;

  DailySummaryProcessingTask(this.task);

  @override
  String get id => task.id;

  @override
  String get taskType => 'daily_summary';

  @override
  String get notificationText => '生成每日总结（${task.refId}）';

  String get date => task.refId;

  @override
  Future<void> execute(ProcessingContext ctx) async {
    debugPrint('[DailySummaryTask] 开始处理: $date');
    await ctx.storage.updateProcessingTaskStatus(
      task.id,
      task_model.TaskStatus.running,
    );
    ctx.sendToMain({
      'type': 'taskStarted',
      'taskId': task.id,
      'refId': date,
      'taskType': 'daily_summary',
    });

    final entries = await ctx.storage.getEntriesByDate(date);
    final sourceEntryIds = entries.map((e) => e.id).toList();

    // 0 篇：空总结标记完成
    if (entries.isEmpty) {
      await _saveCompleted(
        ctx,
        title: '今天没有录音',
        summary: '',
        outline: '',
        sourceEntryIds: const [],
        entryCount: 0,
        degraded: false,
      );
      ctx.sendToMain({
        'type': 'dailySummaryCompleted',
        'date': date,
        'taskId': task.id,
      });
      return;
    }

    // 前置：当天有 diary 尚未处理完成 → 判 failed（明确失败优于静默跳过）
    // 查 processing_tasks 表（不读废弃的 entry.status）：当天任一 diary 仍有
    // queued/running 任务即视为未完成。FGS isolate 不能访问 main isolate 的
    // processingTaskStore（static 不跨 isolate），改由 ctx.storage 直接查 DB。
    final diaryIds = entries.map((e) => e.id).toSet();
    final allPending = await ctx.storage.getPendingProcessingTasks();
    final hasProcessing = allPending.any((t) => diaryIds.contains(t.refId));
    if (hasProcessing) {
      await _markFailed(ctx, '当天有录音尚未处理完成');
      return;
    }

    // 调 LLM 聚合（通知文案由调度器循环统一管理，task 内不再调 updateService）
    try {
      ctx.sendToMain({
        'type': 'dailySummaryStage',
        'date': date,
        'stage': 'llm',
      });
      final result = await ctx.dailySummary.summarizeDay(entries);
      await _saveCompleted(
        ctx,
        title: result.title,
        summary: result.summary,
        outline: result.outline,
        sourceEntryIds: sourceEntryIds,
        entryCount: entries.length,
        degraded: result.degraded,
      );
      ctx.sendToMain({
        'type': 'dailySummaryCompleted',
        'date': date,
        'taskId': task.id,
      });
    } catch (e) {
      await _markFailed(ctx, e.toString());
    }
  }

  Future<void> _saveCompleted(
    ProcessingContext ctx, {
    required String title,
    required String summary,
    required String outline,
    required List<String> sourceEntryIds,
    required int entryCount,
    required bool degraded,
  }) async {
    await ctx.storage.writeDailySummaryJson(
      date,
      DailySummaryData(
        version: 1,
        date: date,
        title: title,
        summary: summary,
        outline: outline,
        sourceEntryIds: sourceEntryIds,
        degraded: degraded,
      ),
    );
    final existing = await ctx.storage.getDailySummary(date);
    // daily_summary 表 status 列废弃（任务状态走 processing_tasks），这里给占位值不读。
    await ctx.storage.saveDailySummary(
      DailySummary(
        date: date,
        title: title,
        status: EntryStatus.completed,
        sourceEntryIds: sourceEntryIds,
        entryCount: entryCount,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await ctx.storage.updateProcessingTaskStatus(
      task.id,
      task_model.TaskStatus.completed,
    );
  }

  Future<void> _markFailed(ProcessingContext ctx, String error) async {
    debugPrint('[DailySummaryTask] 失败 ($date): $error');
    await ctx.storage.updateProcessingTaskStatus(
      task.id,
      task_model.TaskStatus.failed,
      failedMessage: error,
    );
    ctx.sendToMain({
      'type': 'dailySummaryFailed',
      'date': date,
      'taskId': task.id,
      'error': error,
    });
  }
}

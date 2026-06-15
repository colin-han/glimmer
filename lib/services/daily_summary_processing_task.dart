import 'package:flutter/foundation.dart';

import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import 'processing_task.dart';

/// 每日总结处理任务：把指定日期当天所有录音的 ASR 全文重组为一篇总结。
///
/// 流程：查当天 entries → 0 篇空完成 / 有 processing 篇判 failed / 否则
/// summarizeDay 聚合 → 写正文文件 + 更新元数据。失败时标记 status=failed +
/// 通知，不向上抛。
class DailySummaryProcessingTask implements ProcessingTask {
  final String date;

  DailySummaryProcessingTask(this.date);

  @override
  String get id => date;

  @override
  String get taskType => 'daily_summary';

  @override
  String get notificationText => '生成每日总结（$date）';

  @override
  Future<void> execute(ProcessingContext ctx) async {
    debugPrint('[DailySummaryTask] 开始处理: $date');
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
      ctx.sendToMain({'type': 'dailySummaryCompleted', 'date': date});
      return;
    }

    // 前置：当天有 recording 尚未处理完成 → 判 failed（明确失败优于静默跳过）
    final hasProcessing = entries.any(
      (e) => e.status == EntryStatus.processing,
    );
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
      ctx.sendToMain({'type': 'dailySummaryCompleted', 'date': date});
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
  }

  Future<void> _markFailed(ProcessingContext ctx, String error) async {
    debugPrint('[DailySummaryTask] 失败 ($date): $error');
    final existing = await ctx.storage.getDailySummary(date);
    await ctx.storage.saveDailySummary(
      DailySummary(
        date: date,
        title: existing?.title ?? '生成失败',
        status: EntryStatus.failed,
        sourceEntryIds: existing?.sourceEntryIds ?? const [],
        entryCount: existing?.entryCount ?? 0,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    ctx.sendToMain({
      'type': 'dailySummaryFailed',
      'date': date,
      'error': error,
    });
  }
}

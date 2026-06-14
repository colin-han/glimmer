import '../exceptions.dart';
import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import 'api_log_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';

/// 每日总结生成服务：读各篇 transcript → 拼接 → 超长降级 → 调 LLM → 记 API 日志。
class DailySummaryService {
  final DiaryStorageService _storage;
  final LlmService _llm;
  final ApiLogService _apiLog;

  DailySummaryService({
    DiaryStorageService? storage,
    LlmService? llm,
    ApiLogService? apiLog,
  }) : _storage = storage ?? DiaryStorageService(),
       _llm = llm ?? LlmService(),
       _apiLog = apiLog ?? ApiLogService();

  /// 把一天各篇录音重组为一篇总结。
  ///
  /// [entries] 无序传入也会内部按 createdAt 升序。
  /// 前置条件：各篇 transcript.json 应已存在（由调用方 DailySummaryProcessingTask
  /// 检查当天无 processing 篇后再调用）；单篇读失败则容错跳过。
  Future<DailySummaryResult> summarizeDay(List<DiaryEntry> entries) async {
    final sorted = [...entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final diaryIdForLog = sorted.isEmpty ? 'daily' : sorted.first.id;

    final sw = Stopwatch()..start();
    try {
      // 1) 读各篇 transcript 全文
      final fullSegments = <DayFullTextSegment>[];
      for (final e in sorted) {
        try {
          final transcript = await _storage.readTranscriptJson(e.folderPath);
          final text = transcript.fullText;
          if (text.isNotEmpty) {
            fullSegments.add((createdAt: e.createdAt, text: text));
          }
        } catch (_) {
          // 单篇 transcript 读失败跳过，不整盘失败
        }
      }

      // 2) 拼接 + 超长降级判断
      String combined = buildDayFullText(fullSegments);
      var degraded = shouldDegrade(combined);

      // 3) 降级：退回各篇 summary 聚合
      if (degraded) {
        final summarySegments = <DaySummarySegment>[];
        for (final e in sorted) {
          try {
            final llmData = await _storage.readLlmResult(e.folderPath);
            summarySegments.add((
              createdAt: e.createdAt,
              title: llmData.title,
              summary: llmData.summary,
            ));
          } catch (_) {}
        }
        combined = buildDaySummariesText(summarySegments);
      }

      // 4) 调 LLM
      final result = await _llm.summarizeDayText(combined, degraded: degraded);

      sw.stop();
      await _apiLog.logApiCall(
        diaryId: diaryIdForLog,
        apiType: 'llm_daily_summary',
        step: 'daily_summary',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        promptTokens: result.usage?.promptTokens,
        completionTokens: result.usage?.completionTokens,
        totalTokens: result.usage?.totalTokens,
        cachedTokens: result.usage?.cachedTokens,
        reasoningTokens: result.usage?.reasoningTokens,
        responseSummary: degraded ? '降级：基于各篇摘要聚合' : null,
      );
      return result;
    } catch (e) {
      sw.stop();
      await _apiLog.logApiCall(
        diaryId: diaryIdForLog,
        apiType: 'llm_daily_summary',
        step: 'daily_summary',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      throw DailySummaryException('每日总结生成失败: $e');
    }
  }
}

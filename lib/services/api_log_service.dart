import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../constants/api_pricing.dart';
import 'database/app_database.dart';

/// API 日志服务：记录 API 调用和关键步骤到 SQLite。
class ApiLogService {
  final AppDatabase _db = AppDatabase();
  final _uuid = const Uuid();

  /// 记录一次 API 调用。
  ///
  /// [apiType] 见设计文档枚举：asr_flash / asr_realtime / asr_async /
  /// llm_summarize / llm_generate_reply / llm_match_tags / llm_recommend_diaries / tts
  /// [step] 处理阶段：recording / asr / llm / tts / tagging / processing
  Future<void> logApiCall({
    required String diaryId,
    required String apiType,
    required String step,
    required String status,
    int? durationMs,
    String? errorMessage,
    String? responseSummary,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    int? cachedTokens,
    int? reasoningTokens,
    int? audioDurationSeconds,
    int? ttsCharacterCount,
  }) async {
    final estimatedCost = _estimateCost(
      apiType: apiType,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      audioDurationSeconds: audioDurationSeconds,
      ttsCharacterCount: ttsCharacterCount,
    );

    // 截断 responseSummary 到 500 字
    String? truncatedSummary;
    if (responseSummary != null) {
      truncatedSummary = responseSummary.length > 500
          ? '${responseSummary.substring(0, 500)}...'
          : responseSummary;
    }

    await _db.insertApiLog(ApiLogsCompanion.insert(
      id: _uuid.v4(),
      diaryId: diaryId,
      apiType: apiType,
      step: step,
      status: status,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      durationMs: Value(durationMs),
      errorMessage: Value(errorMessage),
      responseSummary: Value(truncatedSummary),
      promptTokens: Value(promptTokens),
      completionTokens: Value(completionTokens),
      totalTokens: Value(totalTokens),
      cachedTokens: Value(cachedTokens),
      reasoningTokens: Value(reasoningTokens),
      audioDurationSeconds: Value(audioDurationSeconds),
      ttsCharacterCount: Value(ttsCharacterCount),
      estimatedCost: Value(estimatedCost),
    ));
  }

  /// 记录一个关键步骤（非 API 调用）。
  ///
  /// 内部将 apiType 设为 'step' 以区分。
  Future<void> logStep({
    required String diaryId,
    required String step,
    required String status,
    String? message,
  }) async {
    await _db.insertApiLog(ApiLogsCompanion.insert(
      id: _uuid.v4(),
      diaryId: diaryId,
      apiType: 'step',
      step: step,
      status: status,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      errorMessage: Value(message),
    ));
  }

  /// 查询某篇日记的所有日志（按时间正序）。
  Future<List<ApiLog>> getLogsForDiary(String diaryId) {
    return _db.getLogsForDiary(diaryId);
  }

  /// 查询最近的日志（按时间倒序，支持分页）。
  Future<List<ApiLog>> getRecentLogs({int limit = 50, int offset = 0}) {
    return _db.getRecentLogs(limit: limit, offset: offset);
  }

  /// 根据 apiType 和可用用量信息估算费用。
  double? _estimateCost({
    required String apiType,
    int? promptTokens,
    int? completionTokens,
    int? audioDurationSeconds,
    int? ttsCharacterCount,
  }) {
    if (apiType.startsWith('llm') &&
        promptTokens != null &&
        completionTokens != null) {
      return ApiPricing.estimateLlmCost(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
    }
    if (apiType.startsWith('asr') && audioDurationSeconds != null) {
      return ApiPricing.estimateAsrCost(audioDurationSeconds);
    }
    if (apiType == 'tts' && ttsCharacterCount != null) {
      return ApiPricing.estimateTtsCost(ttsCharacterCount);
    }
    return null;
  }
}

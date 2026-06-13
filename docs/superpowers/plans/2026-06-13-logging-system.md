# API 日志系统实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在数据库中增加 API 日志表和服务，记录日记处理过程中的 API 调用详情与费用估算。

**Architecture:** 新增 `ApiLogs` drift 表 + `ApiLogService` 服务层 + 费用估算常量。在调用层（ProcessingTaskHandler / RecordingTaskHandler）包装现有 API 调用并记录日志，不修改现有 AsrService / LlmService / TtsService 的接口（仅向后兼容地扩展 LlmResult 添加 usage 字段）。

**Tech Stack:** drift (SQLite ORM) + Dart + Flutter

**设计文档:** `docs/superpowers/specs/2026-06-13-logging-system-design.md`

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| 修改 | `lib/services/database/tables.dart` | 新增 `ApiLogs` 表定义 |
| 修改 | `lib/services/database/app_database.dart` | 注册新表、schema 7、migration、查询方法 |
| 生成 | `lib/services/database/app_database.g.dart` | build_runner 生成（勿手动编辑） |
| 创建 | `lib/constants/api_pricing.dart` | API 单价常量 + 费用估算函数 |
| 创建 | `lib/services/api_log_service.dart` | 日志服务：logApiCall / logStep / 查询 |
| 修改 | `lib/services/llm_service.dart` | LlmResult 添加 usage 字段（向后兼容） |
| 修改 | `lib/services/recording_processor.dart` | ProcessingTaskHandler 集成日志 |
| 修改 | `lib/services/recording_task_handler.dart` | RecordingTaskHandler 集成日志 |

---

### Task 1: 定义 ApiLogs 表 + 更新数据库 schema

**Files:**
- 修改: `lib/services/database/tables.dart`
- 修改: `lib/services/database/app_database.dart`

- [ ] **Step 1: 在 tables.dart 末尾添加 ApiLogs 表定义**

在 `DiaryTagRelations` 类之后追加：

```dart
class ApiLogs extends Table {
  TextColumn get id => text()();
  TextColumn get diaryId => text()();
  TextColumn get apiType => text()();
  TextColumn get step => text()();
  TextColumn get status => text()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get responseSummary => text().nullable()();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  IntColumn get totalTokens => integer().nullable()();
  IntColumn get cachedTokens => integer().nullable()();
  IntColumn get reasoningTokens => integer().nullable()();
  IntColumn get audioDurationSeconds => integer().nullable()();
  IntColumn get ttsCharacterCount => integer().nullable()();
  RealColumn get estimatedCost => real().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: 更新 app_database.dart — 注册表、升级 schema、添加查询方法**

变更点：

**a) `@DriftDatabase` 注解添加 `ApiLogs`：**

```dart
@DriftDatabase(tables: [DiaryEntries, Tags, DiaryTagRelations, ApiLogs])
```

**b) `schemaVersion` 改为 `7`：**

```dart
@override
int get schemaVersion => 7;
```

**c) migration `onUpgrade` 中追加 version 7：**

在现有 `if (from < 6)` 块之后追加：

```dart
if (from < 7) {
  try { await m.createTable(apiLogs); } catch (_) {}
}
```

**d) 添加 ApiLogs 查询方法**（在 `getProcessingEntryCount()` 方法之后）：

```dart
// --- ApiLogs ---

Future<void> insertApiLog(ApiLogsCompanion log) {
  return into(apiLogs).insert(log);
}

Future<List<ApiLog>> getLogsForDiary(String diaryId) {
  return (select(apiLogs)
        ..where((t) => t.diaryId.equals(diaryId))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .get();
}

Future<List<ApiLog>> getRecentLogs({int limit = 50, int offset = 0}) {
  return (select(apiLogs)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(limit, offset: offset))
      .get();
}
```

- [ ] **Step 3: 运行 build_runner 重新生成代码**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: 验证生成成功**

```bash
flutter analyze
```

Expected: 无错误，`app_database.g.dart` 已重新生成，包含 `ApiLog` 数据类和 `ApiLogsCompanion`。

- [ ] **Step 5: 提交**

```bash
git add lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/database/app_database.g.dart
git commit -m "feat: 新增 ApiLogs 数据库表（schema v7）"
```

---

### Task 2: 创建 API 费用估算常量

**Files:**
- 创建: `lib/constants/api_pricing.dart`

- [ ] **Step 1: 创建 lib/constants/ 目录**

```bash
mkdir -p lib/constants
```

- [ ] **Step 2: 创建 api_pricing.dart**

```dart
/// API 费用估算常量。
///
/// 单价来源：火山引擎控制台。实际价格以控制台为准，此处为估算值。
class ApiPricing {
  ApiPricing._();

  // LLM (Doubao) — 输入/输出价格不同（¥/百万 tokens）
  static const double llmInputPricePerMillion = 0.8;
  static const double llmOutputPricePerMillion = 2.0;

  // ASR — 按小时（¥/小时）
  static const double asrPricePerHour = 1.5;

  // TTS — 按万字符（¥/万字符）
  static const double ttsPricePerTenThousandChars = 1.5;

  /// 估算 LLM 费用（元）
  static double estimateLlmCost({
    required int promptTokens,
    required int completionTokens,
  }) {
    return (promptTokens * llmInputPricePerMillion / 1000000) +
        (completionTokens * llmOutputPricePerMillion / 1000000);
  }

  /// 估算 ASR 费用（元）
  static double estimateAsrCost(int durationSeconds) {
    return durationSeconds * asrPricePerHour / 3600;
  }

  /// 估算 TTS 费用（元）
  static double estimateTtsCost(int characterCount) {
    return characterCount * ttsPricePerTenThousandChars / 10000;
  }
}
```

- [ ] **Step 3: 提交**

```bash
git add lib/constants/api_pricing.dart
git commit -m "feat: 新增 API 费用估算常量"
```

---

### Task 3: 创建 ApiLogService

**Files:**
- 创建: `lib/services/api_log_service.dart`

- [ ] **Step 1: 创建 api_log_service.dart**

```dart
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
```

- [ ] **Step 2: 验证**

```bash
flutter analyze
```

- [ ] **Step 3: 提交**

```bash
git add lib/services/api_log_service.dart
git commit -m "feat: 新增 ApiLogService 日志服务"
```

---

### Task 4: LLM 服务向后兼容地返回 usage 数据

**Files:**
- 修改: `lib/services/llm_service.dart`

这一步仅向 `LlmResult` 添加可选 `usage` 字段，不影响任何现有调用方。

- [ ] **Step 1: 在 llm_service.dart 中添加 `LlmUsage` 类**

在 `LlmResult` 类定义之前插入：

```dart
/// LLM API 返回的 token 用量。
class LlmUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int? cachedTokens;
  final int? reasoningTokens;

  const LlmUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    this.cachedTokens,
    this.reasoningTokens,
  });
}
```

- [ ] **Step 2: 给 LlmResult 添加 usage 字段**

在 `LlmResult` 类中添加 `usage` 字段：

```dart
class LlmResult {
  final String title;
  final String content;
  final String summary;
  final String outline;
  final List<Utterance> utterances;
  final LlmUsage? usage;

  LlmResult({
    required this.title,
    required this.content,
    required this.summary,
    required this.outline,
    required this.utterances,
    this.usage,
  });
}
```

- [ ] **Step 3: 在 `summarize()` 方法中提取 usage 数据**

在 `summarize()` 方法中，找到这段代码：

```dart
    final content =
        response.data['choices'][0]['message']['content'] as String;
    return _parseResult(content);
```

替换为：

```dart
    final content =
        response.data['choices'][0]['message']['content'] as String;

    // 提取 usage 数据
    final usageJson = response.data['usage'] as Map<String, dynamic>?;
    LlmUsage? usage;
    if (usageJson != null) {
      usage = LlmUsage(
        promptTokens: usageJson['prompt_tokens'] as int? ?? 0,
        completionTokens: usageJson['completion_tokens'] as int? ?? 0,
        totalTokens: usageJson['total_tokens'] as int? ?? 0,
        cachedTokens:
            (usageJson['prompt_tokens_details'] as Map<String, dynamic>?)
                ?['cached_tokens'] as int?,
        reasoningTokens:
            (usageJson['completion_tokens_details'] as Map<String, dynamic>?)
                ?['reasoning_tokens'] as int?,
      );
    }

    final result = _parseResult(content);
    return LlmResult(
      title: result.title,
      content: result.content,
      summary: result.summary,
      outline: result.outline,
      utterances: result.utterances,
      usage: usage,
    );
```

注意：`_parseResult` 返回的 `LlmResult` 不会有 `usage`（因为它是从 JSON content 解析的，不包含 HTTP 响应的 usage），所以这里用 `LlmResult(...)` 重建并附上 `usage`。

- [ ] **Step 4: 验证**

```bash
flutter analyze
```

- [ ] **Step 5: 提交**

```bash
git add lib/services/llm_service.dart
git commit -m "feat: LLM 服务向后兼容地返回 token usage 数据"
```

---

### Task 5: ProcessingTaskHandler 集成日志记录

**Files:**
- 修改: `lib/services/recording_processor.dart`

- [ ] **Step 1: 添加 import 和 ApiLogService 实例**

在文件顶部的 import 区域添加：

```dart
import 'api_log_service.dart';
```

在 `ProcessingTaskHandler` 类的字段区域（`final _storageService` 之后）添加：

```dart
final _apiLogService = ApiLogService();
```

- [ ] **Step 2: 在 `_processEntry` 外层循环（onStart 中）添加步骤日志**

在 `onStart` 方法中，将现有的 for 循环：

```dart
for (final entry in entries) {
  try {
    await _processEntry(entry);
  } catch (e) {
    debugPrint('[ProcessingHandler] 处理异常 (${entry.id}): $e');
    await _markFailed(entry.id, '处理失败');
  }
}
```

替换为：

```dart
for (final entry in entries) {
  await _apiLogService.logStep(
    diaryId: entry.id,
    step: 'processing',
    status: 'started',
    message: '从 ${entry.processingStage.value} 阶段恢复',
  );
  try {
    await _processEntry(entry);
    await _apiLogService.logStep(
      diaryId: entry.id,
      step: 'processing',
      status: 'success',
    );
  } catch (e) {
    debugPrint('[ProcessingHandler] 处理异常 (${entry.id}): $e');
    await _apiLogService.logStep(
      diaryId: entry.id,
      step: 'processing',
      status: 'error',
      message: e.toString(),
    );
    await _markFailed(entry.id, '处理失败');
  }
}
```

- [ ] **Step 3: 替换 `_doAsr` 方法**

将整个 `_doAsr` 方法替换为带日志的版本：

```dart
  /// 阶段: ASR 识别（异步 submit + query）
  Future<void> _doAsr(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 语音识别...',
    );

    final sw = Stopwatch()..start();
    try {
      final tosKey = await _storageService.getTosKey(entry.id);
      if (tosKey == null) {
        throw Exception('tosKey 为空，无法进行 ASR');
      }

      final presignedUrl = await _tosService.getPresignedUrl(tosKey);

      AsrResult asrResult;
      if (entry.asrTaskId != null) {
        debugPrint('[ProcessingHandler] 恢复 ASR 查询: ${entry.asrTaskId}');
        try {
          asrResult = await _asrService.pollAsyncResult(entry.asrTaskId!);
        } catch (e) {
          debugPrint('[ProcessingHandler] ASR 查询失败，重新提交: $e');
          final newTaskId = await _asrService.submitAsync(presignedUrl);
          await _storageService.updateAsrTaskIdAndStage(
              entry.id, newTaskId, ProcessingStage.asr);
          asrResult = await _asrService.pollAsyncResult(newTaskId);
        }
      } else {
        final asrTaskId = await _asrService.submitAsync(presignedUrl);
        await _storageService.updateAsrTaskIdAndStage(
            entry.id, asrTaskId, ProcessingStage.asr);
        asrResult = await _asrService.pollAsyncResult(asrTaskId);
      }

      await _storageService.writeTranscriptJson(
        entry.folderPath,
        TranscriptData(version: 1, utterances: asrResult.utterances),
      );
      await _storageService.updateProcessingStage(
          entry.id, ProcessingStage.llm);

      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'asr_async',
        step: 'asr',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        audioDurationSeconds: entry.durationSeconds,
      );
      debugPrint('[ProcessingHandler] ASR 完成');
    } catch (e) {
      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'asr_async',
        step: 'asr',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
        audioDurationSeconds: entry.durationSeconds,
      );
      rethrow;
    }
  }
```

- [ ] **Step 4: 替换 `_doLlm` 方法**

将整个 `_doLlm` 方法替换为带日志的版本：

```dart
  /// 阶段: LLM 润色汇总
  Future<void> _doLlm(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - AI 总结...',
    );

    final sw = Stopwatch()..start();
    try {
      final transcript =
          await _storageService.readTranscriptJson(entry.folderPath);
      final llmResult = await _llmService.summarize(transcript.utterances);

      await _storageService.writeLlmResult(
        entry.folderPath,
        LlmResultData(
          version: 1,
          title: llmResult.title,
          content: llmResult.content,
          summary: llmResult.summary,
          outline: llmResult.outline,
          utterances: llmResult.utterances,
        ),
      );
      await _storageService.updateProcessingStage(
          entry.id, ProcessingStage.tagging);

      sw.stop();
      final usage = llmResult.usage;
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_summarize',
        step: 'llm',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        promptTokens: usage?.promptTokens,
        completionTokens: usage?.completionTokens,
        totalTokens: usage?.totalTokens,
        cachedTokens: usage?.cachedTokens,
        reasoningTokens: usage?.reasoningTokens,
      );
      debugPrint('[ProcessingHandler] LLM 完成');
    } catch (e) {
      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_summarize',
        step: 'llm',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }
```

- [ ] **Step 5: 替换 `_doTagging` 方法**

将整个 `_doTagging` 方法替换为带日志的版本：

```dart
  /// 阶段: 标签归类（失败不阻塞）
  Future<void> _doTagging(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 自动归类...',
    );

    final sw = Stopwatch()..start();
    try {
      final llmResult = await _storageService.readLlmResult(entry.folderPath);
      final allTags = await _storageService.getAllTags();
      final tagsWithPrompt =
          allTags.where((t) => t.matchPrompt.isNotEmpty).toList();
      if (tagsWithPrompt.isNotEmpty) {
        final tagInfos = tagsWithPrompt
            .map((t) =>
                TagInfo(id: t.id, name: t.name, matchPrompt: t.matchPrompt))
            .toList();
        final matchedTagIds =
            await _llmService.matchTags(llmResult.content, tagInfos);
        if (matchedTagIds.isNotEmpty) {
          await _storageService.autoTagDiary(entry.id, matchedTagIds);
        }
      }

      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
      );
      debugPrint('[ProcessingHandler] 标签归类完成');
    } catch (e) {
      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      // 标签归类失败不阻塞，不 rethrow
      debugPrint('[ProcessingHandler] 自动归类失败（不阻塞）: $e');
    }
  }
```

- [ ] **Step 6: 验证**

```bash
flutter analyze
```

- [ ] **Step 7: 提交**

```bash
git add lib/services/recording_processor.dart
git commit -m "feat: ProcessingTaskHandler 集成 API 日志记录"
```

---

### Task 6: RecordingTaskHandler 集成日志记录

**Files:**
- 修改: `lib/services/recording_task_handler.dart`

- [ ] **Step 1: 添加 import 和 ApiLogService 实例**

在文件顶部的 import 区域添加：

```dart
import 'api_log_service.dart';
```

在 `RecordingTaskHandler` 类的字段区域（`final _uuid` 之后）添加：

```dart
final _apiLogService = ApiLogService();
```

- [ ] **Step 2: 替换 `_connectRealtimeAsr` 方法**

将整个 `_connectRealtimeAsr` 方法替换为带日志的版本：

```dart
  void _connectRealtimeAsr() {
    _realtimeAsr = RealtimeAsrService();
    final sw = Stopwatch()..start();
    _realtimeAsr!.connect().then((_) {
      sw.stop();
      _apiLogService.logApiCall(
        diaryId: _folderId ?? '',
        apiType: 'asr_realtime',
        step: 'recording',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
      );
    }).catchError((e) {
      sw.stop();
      debugPrint('[TaskHandler] 实时 ASR 连接失败（不阻塞录音）: $e');
      _apiLogService.logApiCall(
        diaryId: _folderId ?? '',
        apiType: 'asr_realtime',
        step: 'recording',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
    });

    _partialResultSub = _realtimeAsr!.onPartialResult.listen((text) {
      _sendToMain({'type': 'partialText', 'text': text});
    });
  }
```

- [ ] **Step 3: 验证**

```bash
flutter analyze
```

- [ ] **Step 4: 提交**

```bash
git add lib/services/recording_task_handler.dart
git commit -m "feat: RecordingTaskHandler 集成实时 ASR 日志记录"
```

---

## 自检清单

### 1. Spec 覆盖

| Spec 要求 | 对应 Task |
|-----------|----------|
| `ApiLogs` 表 | Task 1 |
| schema 版本 6→7 | Task 1 |
| 费用估算常量 | Task 2 |
| `ApiLogService` | Task 3 |
| LLM usage 提取 | Task 4 |
| ProcessingTaskHandler 集成 | Task 5 |
| RecordingTaskHandler 集成 | Task 6 |

### 2. 类型一致性

- `ApiLogsCompanion.insert()` 的参数类型与 `tables.dart` 定义一致
- `LlmResult.usage` 类型为 `LlmUsage?`，在 Task 4 定义、Task 5 读取
- `ApiLogService.logApiCall()` 参数名与 `ApiLogs` 表字段名一一对应
- `ApiPricing` 的方法签名与 Task 3 中 `_estimateCost` 的调用参数一致

### 3. 无占位符

- 所有代码步骤包含完整实现
- 无 TBD / TODO / "implement later"

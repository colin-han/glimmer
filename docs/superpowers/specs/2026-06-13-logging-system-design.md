# API 日志系统设计

## 目标

在数据库中增加日志表，记录日记处理过程中的 API 调用和关键步骤，用于调试排错和费用监控。

## 范围

- 新增 `api_logs` 数据库表
- 新增 `ApiLogService` 服务层
- 在调用层（ProcessingTaskHandler 等）集成日志记录
- 支持费用估算（基于常量单价）

## 数据库表设计

### `ApiLogs` 表

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PK | UUID |
| `diaryId` | TEXT | 关联的日记 ID |
| `apiType` | TEXT | API 类型：`asr_flash` / `asr_realtime` / `asr_async` / `llm_summarize` / `llm_generate_reply` / `llm_match_tags` / `llm_recommend_diaries` / `tts` |
| `step` | TEXT | 处理阶段：`recording` / `asr` / `llm` / `tts` |
| `status` | TEXT | 结果状态：`success` / `error` / `timeout` |
| `durationMs` | INTEGER NULL | 调用耗时（毫秒） |
| `errorMessage` | TEXT NULL | 错误信息 |
| `responseSummary` | TEXT NULL | 响应摘要（截断到 500 字） |
| `promptTokens` | INTEGER NULL | LLM 输入 token 数 |
| `completionTokens` | INTEGER NULL | LLM 输出 token 数 |
| `totalTokens` | INTEGER NULL | LLM 总 token 数 |
| `cachedTokens` | INTEGER NULL | LLM 缓存 token 数 |
| `reasoningTokens` | INTEGER NULL | LLM 推理 token 数 |
| `audioDurationSeconds` | INTEGER NULL | ASR 音频时长（秒），用于估算费用 |
| `ttsCharacterCount` | INTEGER NULL | TTS 字符数，用于估算费用 |
| `estimatedCost` | REAL NULL | 估算费用（元） |
| `createdAt` | INTEGER | 记录时间戳 |

`diaryId` 不设外键约束（日志不依赖日记存在，日记删除不影响日志）。

## 服务层设计

### `ApiLogService`

位置：`lib/services/api_log_service.dart`

```dart
class ApiLogService {
  final AppDatabase _db;

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
    double? estimatedCost,
  });

  Future<void> logStep({
    required String diaryId,
    required String step,
    required String status,
    String? message,
  });

  Future<List<ApiLog>> getLogsForDiary(String diaryId);
  Future<List<ApiLog>> getRecentLogs({int limit = 50, int offset = 0});
}
```

- `logApiCall`：记录一次 API 调用，包含用量和估算费用
- `logStep`：记录关键步骤（如"开始处理"、"ASR 完成"等），`apiType` 设为 `step` 以区分
- `getLogsForDiary`：查询某篇日记的所有日志，按时间正序
- `getRecentLogs`：查询最近的日志，按时间倒序，支持分页

### 费用估算常量

位置：`lib/constants/api_pricing.dart`

```dart
class ApiPricing {
  // LLM (Doubao) — 输入/输出价格不同
  static const double llmInputPricePerMillion = 0.8;   // ¥/百万 input tokens
  static const double llmOutputPricePerMillion = 2.0;  // ¥/百万 output tokens

  // ASR — 按小时
  static const double asrPricePerHour = 1.5;  // ¥/小时

  // TTS — 按万字符
  static const double ttsPricePerTenThousandChars = 1.5;  // ¥/万字符

  static double estimateLlmCost({
    required int promptTokens,
    required int completionTokens,
  }) {
    return (promptTokens * llmInputPricePerMillion / 1000000) +
           (completionTokens * llmOutputPricePerMillion / 1000000);
  }

  static double estimateAsrCost(int durationSeconds) {
    return durationSeconds * asrPricePerHour / 3600;
  }

  static double estimateTtsCost(int characterCount) {
    return characterCount * ttsPricePerTenThousandChars / 10000;
  }
}
```

单价定义为常量，后续根据控制台实际账单校准即可。

## 集成方案

在**调用层**（ProcessingTaskHandler）而非服务内部记录日志，保持 AsrService、LlmService、TtsService 职责不变。

### ProcessingTaskHandler 中的集成

```
处理流程中的日志记录点：

① 录音完成 → logStep(step: 'recording', status: 'success')
② 开始 ASR → logStep(step: 'asr', status: 'started')
③ ASR 返回 → logApiCall(apiType: 'asr_async', status: 'success', audioDurationSeconds: ...)
④ 开始 LLM → logStep(step: 'llm', status: 'started')
⑤ LLM 返回 → logApiCall(apiType: 'llm_summarize', status: 'success', promptTokens: ..., completionTokens: ..., estimatedCost: ...)
⑥ 开始 TTS → logStep(step: 'tts', status: 'started')
⑦ TTS 返回 → logApiCall(apiType: 'tts', status: 'success', ttsCharacterCount: ..., estimatedCost: ...)
⑧ 处理完成 → logStep(step: 'processing', status: 'success')
⑨ 任何异常 → logApiCall/logStep(status: 'error', errorMessage: ...)
```

### RecordingTaskHandler 中的集成

```
① 实时 ASR 连接 → logApiCall(apiType: 'asr_realtime', status: 'success'/'error')
```

## 数据库迁移

- `schemaVersion` 从 6 → 7
- 在 `onUpgrade` 中：`if (from < 7) { await m.createTable(apiLogs); }`
- 新建表，不影响现有数据

## API 费用调查结论

| API 服务 | 返回用量信息 | 计费方式 | 预估单价 |
|---------|-------------|---------|---------|
| LLM (Doubao) | ✅ `usage` 含 `prompt_tokens` / `completion_tokens` | 按百万 token，输入/输出不同价 | 输入 ~¥0.8/M，输出 ~¥2/M |
| ASR (语音识别) | ❌ 无费用字段 | 按音频时长（小时） | ~¥1-2/小时 |
| TTS (语音合成) | ❌ 无费用字段 | 按字符数（万字符） | ~¥1-2/万字符 |

## 不做的事

- 不做日志查看 UI（后续可加）
- 不做日志自动清理（后续可加，如保留 90 天）
- 不修改现有 AsrService / LlmService / TtsService 的接口

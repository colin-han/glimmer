# 每日总结（Daily Summary）功能设计

> 日期：2026-06-14
> 状态：设计中

## 1. 背景与目标

现有 app 以「单次录音」为基本单位，每次录音生成一篇带 title / summary / outline 的日记。用户希望在「天」的维度上，把一天内所有录音的内容重组为一篇**真正的连贯日记**，作为独立的「日」实体保存和回看。

核心目标：每天首次打开 app 时，自动把**昨天**所有录音的**原始 ASR 全文**重组为一篇日记（标题 + 正文 + 播报 outline），支持手动生成 / 重新生成任意一天，并在按天分组的列表中查看。

## 2. 需求决策（brainstorming 已确认）

| 维度 | 决策 |
|---|---|
| 实体定位 | 独立的「日」实体，单独存储 / 展示，总结页关联当天各篇录音 |
| 总结输入 | 当天所有录音的**原始 ASR 全文**（utterances）按时间顺序重组，非 summary 二次聚合 |
| 生成时机 | **每天首次打开 app 自动生成「昨天」的总结**（无需后台定时；昨天录音已完整） |
| 输出形态 | 标题 + 正文（summary）+ 播报（outline），复用现有 `LlmResult` 结构，可 TTS |
| 展示入口 | 集成进 list 页**按天分组**，每个日期下有「本日总结」入口 |
| 存储 | 独立 `DailySummaries` 表（元数据）+ `daily_summary_<date>.json`（正文），遵循「元数据入库 + 正文入文件」策略 |
| 执行者 | 由 **processing FGS** 执行（保活 / 通知 / 锁屏可继续）；启动钩子只创建 pending 任务 + 启动 FGS |
| 任务抽象 | **中等抽象**：引入 `ProcessingTask` 接口，录音 / DailySummary 各封装为 Task，`ProcessingTaskHandler` 退化为调度器 |
| 重新生成 | list 每个日期分组 + 详情页都有「生成 / 重新生成」按钮 |
| 天气聚合 | 详情页 AppBar 显示当天聚合天气：天气取众数（weatherIcon 频次最高）+ 温度取 min~max 范围 + 地点众数 |

## 3. 架构概览

```
[app 启动钩子]                 [list 分组按钮 / 详情页按钮]
      │ (检测昨天需生成)              │ (生成 / 重新生成指定日期)
      ▼                              ▼
[创建 / 更新 DailySummaries(status=processing)] ── [启动 processing FGS]
                                                        │
                                                        ▼
                                      [ProcessingTaskHandler 调度器]
                                         查 pending: DiaryEntries(status=processing)
                                                    + DailySummaries(status=processing)
                                                        │
                                        ┌───────────────┴───────────────┐
                                        ▼                               ▼
                              [DiaryProcessingTask]          [DailySummaryProcessingTask]
                              (现有录音处理逻辑提取)          (新增：全天 ASR 重组)
```

## 4. 数据模型与存储

### 4.1 新表 `DailySummaries`（tables.dart）

```dart
class DailySummaries extends Table {
  TextColumn get date => text()();              // 'yyyy-MM-dd'，主键
  TextColumn get title => text()();
  TextColumn get status => text().withDefault(const Constant('processing'))();
  TextColumn get sourceEntryIds => text().withDefault(const Constant('[]'))(); // JSON 数组
  IntColumn get entryCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}
```

`status`：`processing` / `completed` / `failed`（与 `DiaryEntries` 的 status 语义一致）。

### 4.2 正文文件 `<appDocDir>/daily/daily_summary_<date>.json`

```json
{
  "version": 1,
  "date": "2026-06-13",
  "title": "...",
  "summary": "<Markdown 正文>",
  "outline": "<播报文本>",
  "sourceEntryIds": ["uuid1", "uuid2"],
  "degraded": false
}
```

`degraded`：超长降级为 summary 聚合时为 true，UI 提示。

### 4.3 drift migration

`schemaVersion` 2 → 3。`onCreate` / `onUpgrade` 中执行 `await m.createTable(dailySummaries)`（drift migration API）。新表无数据迁移，完全向后兼容。改 `tables.dart` 后必须执行：

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4.4 数据兼容性

- 不修改 `DiaryEntries` / `Tags` / `DiaryTagRelations` / `ApiLogs` 表结构与数据。
- 不删除 / 重命名任何现有用户数据文件（`audio.*` / `transcript.json` / `llm_result.json`）。
- 正文文件带 `version` 字段，供未来格式升级。
- 新增异常类 `DailySummaryException extends AppException`（遵循 `lib/exceptions.dart` 规范，禁止 `throw Exception`、禁止 `e.toString().contains()` 区分类型）。

## 5. LLM 聚合服务

### 5.1 `LlmService.summarizeDay(List<DiaryEntry> entries)` → `DailySummaryResult`

- entries 按 `createdAt` 升序。
- 读取各 entry 的 `transcript.json` 全部 utterances，按篇拼接，篇间插入分隔标记 `### 第 N 段 · HH:mm`（取该篇 `createdAt` 时刻），保留时间线索。
- 单次 LLM 调用，system prompt 改写为「把用户一天的多段语音记录，写成一篇连贯的第一人称日记（summary）+ 全天概览口语播报（outline）+ 标题（title）」，输出 JSON `{title, summary, outline}`（与单篇同构，复用解析）。
- 返回 `DailySummaryResult { title, summary, outline, degraded, usage }`。

### 5.2 超长降级

- 阈值：拼接全文 > **25000 字**。
- 触发后：退回用各篇 `llm_result.json` 的 `summary` 聚合（而非全文），prompt 相应调整；结果 `degraded = true`。
- 日常一天 5~10 篇约 5k~15k 字，不触发；阈值仅作极端保护。

### 5.3 API 日志

调用走 `ApiLogService.logApiCall`，`apiType: 'llm_daily_summary'`，记录 token 用量与 degraded 标记，与现有日志体系一致。

## 6. 处理任务抽象

### 6.1 `ProcessingTask` 接口

```dart
abstract class ProcessingTask {
  String get id;                 // entryId 或 date
  String get taskType;           // 'diary' | 'daily_summary'
  String get notificationText;   // 通知文案
  Future<void> execute(ProcessingContext ctx);
}
```

`ProcessingContext` 封装共享依赖（storage / llm / asr / tos / apiLog / sendToMain），避免每个 Task 各自 new。

### 6.2 两个实现

- `DiaryProcessingTask(DiaryEntry entry)`：从现有 `ProcessingTaskHandler._processEntry` 及 `_doUpload / _doAsr / _doLlm / _doTagging / _doComplete` 提取，**行为完全不变**，仅搬进 Task 类。
- `DailySummaryProcessingTask(String date)`：
  1. 查当天 entries（`getEntriesByDate(date)`），按 `createdAt` 排序。
  2. 0 篇 → 标记完成（空总结）。
  3. 调 `llm.summarizeDay(entries)`（含降级）。
  4. 写 `daily_summary_<date>.json` + 更新 `DailySummaries(status=completed, title, sourceEntryIds, entryCount)`。
  5. 失败 → `status=failed`，抛 `DailySummaryException`，由调度器统一记日志 + 通知主 isolate。

### 6.3 `ProcessingTaskHandler` 退化为调度器

`onStart`：

1. 加载 dotenv。
2. 查 pending：`getPendingEntries()`（录音）+ `getPendingDailySummaries()`（每日总结）。
3. 分别包成 `DiaryProcessingTask` / `DailySummaryProcessingTask`，合并为任务列表。
4. 依次 `execute`；统一管理通知文案、`_sendToMain` 通信、错误捕获 + `logStep`、`_markFailed`。
5. 全部完成 → `processingDone` + 停服。

**任务顺序**：录音任务在前、每日总结在后（总结依赖当天录音已处理完成，保证 `transcript.json` 存在）。

## 7. 自动生成流程（启动钩子）

`main.dart` 新增 `_runDailySummaryIfNeeded()`（异步，仿 `_runTosMigrationIfNeeded`）：

1. 读 SharedPreferences `last_daily_summary_gen_date`。
2. 算「昨天」日期 `yesterday`。
3. 若 `last ≠ yesterday`：
   - 查昨天 entries 数量；≥ 1 才继续。
   - 查昨天是否已有 `DailySummaries`；无则插入一条 `status=processing`。
   - 启动 processing FGS（若未运行）：`FlutterForegroundTask.startService(callback: processingCallback)`。
   - 写 `last_daily_summary_gen_date = yesterday`。
4. **多天未打开**：只自动补「昨天」一天；更早的历史天由用户在 list 分组手动「生成」回填，避免一次多调用。

> 说明：每日总结复用现有 processing FGS（同一 channel、同一 `processingCallback`），不新增通知 channel。FGS 通知 channel 已在 `main` 初始化。

## 8. 手动生成 / 重新生成 / 删除

- **list 日期分组按钮**（无 summary：「生成本日总结」；有：「重新生成」；processing：转圈；failed：重试）：点击 → 更新该 date `status=processing` → 启动 FGS。
- **详情页操作菜单**：同款「重新生成」「删除」。
- **删除**：删 `daily_summary_<date>.json` + 删 `DailySummaries` 行（仅删总结，**不动当天录音**）。

## 9. UI

### 9.1 list 页日期分组（diary_list_page.dart）

`_buildDateGroups` 每个分组标题下新增「本日总结」行，按 DailySummary 状态自适应：

| DailySummary 状态 | 显示 |
|---|---|
| 无记录 | `📝 生成本日总结` 按钮 |
| completed | 标题预览（点击进详情页）+ `↻ 重新生成` |
| processing | `⏳ 正在生成…` 转圈 |
| failed | `⚠ 生成失败 · 重试` |

监听 FGS 消息刷新（复用 `FlutterForegroundTask.addTaskDataCallback`）。

### 9.2 DailySummary 详情页（新增 pages/daily_summary_page.dart）

- **AppBar**：日期标题（如「6月13日 周五」）+ **聚合天气**（地点众数 + 天气众数 emoji + 温度 min~max 范围，如「海淀区 ☁️ 18°~25°」）+ 操作菜单（重新生成 / 删除）。
- **正文**：summary（Markdown，复用 `DetailContentSection`）。
- **播报**：outline + TTS 播报按钮（复用现有 TTS / 播放器）。
- **当天录音列表**：各篇 displayTitle + 时间 + 时长，点击进 `DiaryDetailPage`。
- **状态横幅**：processing / failed（复用单篇 banner 模式）；degraded 显示「基于摘要生成」提示。

### 9.3 天气聚合逻辑（详情页现算，不入库）

- **天气众数**：统计当天各篇 `weatherIcon`（和风代码）频次，取最高 → `weatherEmoji(icon)` + 对应 `weatherText`。用 icon 代码统计比 text 文案稳；平局任取其一。
- **温度范围**：各篇 `temperature`（String→num）取 min~max。全相同显示 `24°`；有差异显示 `18°~25°`；无数据省略温度段。
- **地点**：各篇 `locationName` 众数前置。

### 9.4 FGS 通信消息（调度器 → 主 isolate）

新增（与现有 `stageUpdate / completed / failed` 并列）：

- `dailySummaryStage` `{type, date, stage}`
- `dailySummaryCompleted` `{type, date}`
- `dailySummaryFailed` `{type, date, error}`

## 10. 边界与错误处理

- 昨天 **0 篇**录音 → 启动钩子跳过，不创建总结。
- 昨天 **1 篇** → 仍重组（utterances 变日记体，独立价值）。
- 当天某篇录音仍 `processing`（`transcript.json` 未就绪）→ 该日总结任务判为 `status=failed` 并提示「录音尚未处理完成，请稍后重试」（明确失败比静默跳过清晰）。
- LLM 失败 → `status=failed`，详情页 / 分组可重试（`DailySummaryException`）。
- 并发：已 `processing` 则不重复创建 pending。
- 解析失败：复用单篇 `_parseResult` 容错（title 兜底）。

## 11. 测试策略

- `LlmService.summarizeDay`：mock LLM 响应，验证全文拼接顺序 / 分隔标记、超长降级触发与 `degraded` 标记、JSON 解析。
- DailySummary 存储：写 / 读 json、`version`、`sourceEntryIds` 往返。
- `ProcessingTask` 调度：mock 两类 Task，验证都能被调度执行、顺序（录音先于总结）、错误隔离（一个失败不中断其他）。
- drift migration：schemaVersion 2→3 建表，旧 DB 升级数据不丢。
- 启动钩子：昨天有 / 无录音、已生成 / 未生成、多天未打开只补昨天的分支。
- 天气聚合：众数 / 范围 / 空数据的边界。
- 实现阶段先核实 `test/` 现有基础设施再定测试粒度。

## 12. 实现拆分（供 writing-plans 参考）

1. **数据层**：`tables.dart` 加 `DailySummaries` + build_runner + migration + `DailySummaryStorage`（读写 json / DB）。
2. **LLM**：`summarizeDay` + 超长降级 + `DailySummaryResult`。
3. **任务抽象**：`ProcessingTask` 接口 + `ProcessingContext` + `DiaryProcessingTask`（提取现有逻辑，行为不变）+ `DailySummaryProcessingTask`。
4. **调度器改造**：`ProcessingTaskHandler.onStart` 查 pending 两类 + 调度。
5. **启动钩子**：`main.dart` `_runDailySummaryIfNeeded`。
6. **UI**：list 分组「本日总结」行 + `daily_summary_page`（含天气聚合）+ FGS 消息监听。
7. **手动生成 / 重新生成 / 删除**。
8. **测试 + `flutter analyze` 清零 + `dart format`**。

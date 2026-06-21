# Processing Tasks 表化重构 — 设计文档

- 日期：2026-06-21
- 状态：待评审

## 背景与目标

当前 processing 状态散落在多处：`DiaryEntries.status`/`processingStage`、`DailySummaries.status`、以及运行时的 `FgsRuntime.mode`/`ProcessingFgsController._isRunning`。导致：

- 无法确定知道某篇日记/某天总结是否正在处理（靠 status + mode 猜测）
- 队列视图分散（diary + daily_summary 两表各查）
- 任务无显式实体，易被绕过（如 daily-summary 引入的 `ensureProcessingFgsRunning` 自己启动 FGS 而不入队——已修但根因未除）

**目标**：把 processing task 实体化为独立 DB 表（消息队列语义），业务表回归纯数据，task 表成为处理状态的**单一真相源**，强化架构纪律（FGS 只认 task 表 → 入队成为唯一通道 → 防绕过）。

## 范围

### 做

- 新建 `processing_tasks` 表（统一队列 + 保留历史）
- `DiaryEntries` 去 `status`/`processingStage`/`asrTaskId`；`DailySummaries` 去 `status`
- 新建 `ProcessingTaskStore`（task 状态中心）；`ProcessingFgsController` 收窄为纯启停
- FGS 直接写 task 表（DB 权威）+ 发消息；store 收消息维护内存镜像
- UI 订阅 store（不再直接接 processing 消息、不再读业务表 status）
- retry/reanalyze 新建 task 行（方案 A：事件流，保留每次处理历史）
- 数据 migration（一次性）

### 不做

- recording FGS 的管理（不动，录音消息仍归录音组件）
- 业务表列的物理删除（保留废弃列，代码不读写）
- 已 completed 历史数据的回填（migration 只搬 processing/failed）
- 单 task 内部自动重试（DiaryProcessingTask 失败即 failed，不内部 retry）

## 数据模型

### 新建 `processing_tasks` 表

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | text PK | UUID |
| `task_type` | text | `'diary'` / `'daily_summary'`（可扩展） |
| `ref_id` | text | diary 的 entryId，或 daily_summary 的日期 `'yyyy-MM-dd'` |
| `status` | text | `'queued'` / `'running'` / `'completed'` / `'failed'` |
| `stage` | text nullable | 通用调度字段，FGS 续跑用。diary: `uploading`/`asr`/`llm`/`tagging`；daily_summary 目前 null（未来可扩展） |
| `failed_message` | text nullable | task 进入 failed 时的原因（异常 toString，含类型+消息）。只在 failed 时写 |
| `meta` | text (JSON) | 任务专有数据。diary 的 `{"asrTaskId":"..."}`；daily_summary 的 `{}` |
| `queued_at` | int | 入队时间（ms） |
| `started_at` | int nullable | FGS 开始处理时间 |
| `finished_at` | int nullable | 完成/失败时间 |

**设计原则**：
- **通用字段直接列**（task_type/ref_id/status/stage/failed_message/timestamps）——所有任务类型共有、schema 稳定、可查询（如"所有卡在 asr 阶段的 task"）。
- **专有数据进 `meta` (JSON)**——diary 的 asrTaskId 是 ASR 续跑专有。加新任务类型不用改 schema（只改 meta 内容）。meta 不需查询/索引，只在续跑时读。
- **去 `attempts`**：方案 A（每次 retry 新建行）下，"试了几次"= 同 ref_id 的行数，attempts 冗余。
- **completed/failed 行保留**（不删除）：作历史/审计。

### 业务表瘦身

- `DiaryEntries`：去掉 `status` / `processingStage` / `asrTaskId`（处理状态/中间态，迁到 task 表）。**保留** `tosKey`（上传后的永久资源=真实数据）、`uploadedAt`、所有内容字段。LLM 未处理时 `title=null`。
- `DailySummaries`：去掉 `status`。内容未生成时该行可能不存在。

## 架构

### 分层（main isolate 侧拆为 store + controller）

**`ProcessingTaskStore`（新建）— task 状态中心**
- 内存活跃集合：`activeTasks`（status in queued/running 的 task，按 ref_id 索引）+ `currentTaskId`（此刻 FGS 在跑的）
- 启动加载：app 启动时从 DB 读 active task 填内存（校准，防消息丢导致 stale）
- 消息接收：注册 `taskDataCallback`，收 processing 类消息（`stageUpdate`/`completed`/`failed`/`processingDone`/`dailySummaryStage`/`dailySummaryCompleted`/`dailySummaryFailed`）
- 入队：`enqueueTask(type, refId, {stage, meta})` → 写 task 表(queued) + 加内存 + 调 `controller.start`
- 查询（给 UI）：`getTask(refId)`（返回最新行）/ `isProcessing(refId)` / `activeCount` / `currentTask`
- 通知 UI：`ValueNotifier`（活跃集合变化）供页面订阅 rebuild

**`ProcessingFgsController`（已有，收窄）— FGS 启停**
- `start` / `stop` / `schedule` / `onStopped` / `isRunning` / `hasActivity`
- 不管 task 数据、不收消息（`onStopped` 被 store 调用）

**依赖方向**：`store → controller`（单向）。store 入队调 `controller.start`，收 `processingDone` 调 `controller.onStopped`。

**FGS isolate（DiaryProcessingTask/DailySummaryProcessingTask）**
- 执行处理
- **直接写 task 表**（status/stage/completed/failed/failed_message）← DB 权威
- 发消息（stageUpdate/completed/...）给 store 刷新内存

**UI**
- 订阅 store 的 `ValueNotifier`（不再直接接 processing 消息、不读业务表 status）

### 消息接收分工

- **Processing 类消息** → `ProcessingTaskStore` 统一接收（取代当前散落在各页面的 `_onTaskData`）
- **Recording 类消息**（`recording`/`amplitude`/`partialText`/`weather`/`recordingComplete`）→ 录音组件（RecordingPage）接收，和 task 无关

`FlutterForegroundTask` 允许多个 callback 并存，各自按 `type` 过滤。

### 完整数据流

```
① 入队（录音完成/重新分析/生成总结/启动钩子）
   → store.enqueueTask(type, refId, {stage, meta})
   → 写 task 表(queued) + store 内存加 + controller.start

② FGS 启动（controller.start）
   → ProcessingTaskHandler.onStart → 查 task 表(status in queued/running) → 执行

③ FGS 执行（DiaryProcessingTask 等）
   → 直接写 task 表（running/stage/completed/failed/failed_message）← DB 权威
   → 发消息（stageUpdate/completed/...）

④ store 收消息
   → 更新内存（与 DB 镜像一致）+ 通知 UI（ValueNotifier）
   → processingDone → 调 controller.onStopped（清 isRunning）

⑤ UI 订阅 store
   → banner / badge / 卡片刷新
```

**关键不变量**：FGS 直接写 DB（步骤③，权威）；store 内存是 DB 镜像（消息刷新 + 启动加载校准）；消息**只刷新不持久化**。消息丢不会丢数据（FGS 已写 DB），只会让内存短暂 stale，下次加载校准。

## retry vs reanalyze（方案 A：新建 task 行）

每次 retry/reanalyze **新建一行 task**（ref_id 指向同一篇，旧 completed/failed 行保留作历史）。一篇 diary 在 task 表可能有多行。

**"当前状态" = ref_id 最新行**（`store.getTask(refId)` 返回 `WHERE ref_id=? ORDER BY queued_at DESC LIMIT 1`）。UI 显示、FGS 续跑都用最新行。

**新 task 初始化区分两种语义**：

- **retry（失败续跑）**：新 task **继承**旧 failed task 的 `stage` + `meta.asrTaskId`（从失败处续跑）。入口：详情页失败横幅的「重新处理」。
- **reanalyze（全量重跑）**：新 task **重置** `stage=asr` + `meta.asrTaskId=null`（从头跑，清旧 ASR 任务）。入口：详情页 completed 的「重新分析」。

## migration

**schema**：`schemaVersion` +1（建 `processing_tasks` 表）。

**数据搬迁**（drift `onUpgrade`）：
- `DiaryEntries.status='processing'` → 插 task 行（`diary`, `queued`, `stage=processingStage`, `meta.asrTaskId`）
- `DiaryEntries.status='failed'` → 插 task 行（`diary`, `failed`, `failed_message='迁移自历史失败'`）
- `DailySummaries` 同理（`processing`→插、`failed`→插）
- **`completed` 不补**：老的 completed 已稳定（业务表有数据），不回填 task 行。新流程下新完成的会有 task 行。轻微不一致（老 completed 无 task 行、新有），不影响功能。

**业务表废弃列处理**：
- `DiaryEntries.status`/`processingStage`/`asrTaskId` 列**保留**（不删），代码不再读写。
- 理由：drift/SQLite 删列要重建表（migration 复杂、风险高）；CLAUDE.md「废弃保留」原则。未来彻底稳定后再考虑清理。

## UI 改造

| 页面 | 改造 |
|---|---|
| `DiaryDetailPage` | 订阅 `store.getTask(entry.id)` / `currentTask`；banner 按 `task.status`/`task.stage` 显示（取代读 `entry.status`/`processingStage`）；`_retry`→`store.enqueueTask(diary, 继承stage)`；`_reanalyze`→`store.enqueueTask(diary, 重置)` |
| `DiaryListPage` | 订阅 `store.activeTasks`；卡片按是否 active 显示处理中样式；daily_summary 行同理；手动生成→`store.enqueueTask(daily_summary)` |
| `DailySummaryPage` | 订阅 `store.getTask(date)`；banner 按 task 状态；`_regenerate`→`store.enqueueTask(daily_summary, date)` |
| `RecordingPage` | badge 订阅 `store.activeCount`（取代 `getProcessingEntryCount`） |
| `main.dart` 启动钩子 | `_runDailySummaryIfNeeded` 的 status 判断改为查 task 表；入队走 `store.enqueueTask` |

## 测试策略

- **store 单测**（fake FGS 消息）：内存集合、消息处理（喂 stageUpdate/completed/failed 看 store 更新）、enqueue（写 DB + 内存 + 触发 controller）、查询（getTask 取最新）、启动加载校准
- **migration 测试**：构造旧 DB（DiaryEntries 有 status 数据）→ migration → 验证 task 表正确生成（processing/failed 搬迁、completed 不补）
- **DiaryProcessingTask 写 task 表**：FGS + 真实处理难自动化，靠手动验证（处理流程跑通 + task 表状态正确）
- `flutter analyze` + `flutter test` 全过

## 文件影响面（约 16 文件）

- **DB 层**：`tables.dart`（新表 + 业务表字段废弃）、`app_database.dart`（schemaVersion + migration + 查询）
- **存储服务**：`diary_storage_service.dart`（task 表 CRUD + 业务表 status 方法废弃）
- **模型**：`diary_entry.dart`（去 status/processingStage/asrTaskId）、`daily_summary.dart`（去 status）、新建 `processing_task.dart`
- **处理任务**：`diary_processing_task.dart`（写 task 表取代写 entry status）、`daily_summary_processing_task.dart`、`recording_task_handler.dart`（录音完成入队）
- **调度**：`recording_processor.dart`（onStart 查 task 表）、`processing_fgs_controller.dart`（收窄）、**新建 `processing_task_store.dart`**
- **UI**：`diary_detail_page.dart`、`diary_list_page.dart`、`daily_summary_page.dart`、`recording_page.dart`
- **入口**：`main.dart`

## 开放问题（实现时定）

- `store` 的 `ValueNotifier` 通知粒度：整体 active 集合变化通知，还是按 ref_id 细粒度？倾向整体（简单，UI rebuild 开销小）。
- `meta` JSON 的 drift 实现：`TextColumn` + `TypeConverter<Map<String, dynamic>>`（标准做法）。
- FGS isolate 写 task 表用独立的 `AppDatabase` 连接（已是 `NativeDatabase.createInBackground`，每 isolate 一份）——和 main isolate 的 store 读 task 表无冲突（SQLite 并发读 + 单写隔离）。

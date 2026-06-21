# Processing Tasks 表化 · Plan B：切换 + 清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把运行时从「业务表 status」切换到「processing_tasks 表」——FGS 改写 task 表、store 收消息维护内存、UI 订阅 store、入队走 store.enqueueTask + controller.start、migration 搬迁历史数据、废弃业务表 status 读写。

**Architecture:** Plan A 已就绪基础设施（task 表 + model + storage CRUD + ProcessingTaskStore 内存/enqueue）。Plan B 接入运行时：FGS（DiaryProcessingTask/DailySummaryProcessingTask）改写 task 表（DB 权威）+ 发消息；ProcessingTaskStore 收消息更新内存 + enqueue 调 controller.start；UI 订阅 store.activeRefIds/activeCount；migration 把旧 status 数据搬到 task 表；最后废弃 status 读写。

**Tech Stack:** Flutter / drift / flutter_foreground_task / flutter_test。

完整设计见 `docs/superpowers/specs/2026-06-21-processing-tasks-table-design.md`。Plan A 见 `docs/superpowers/plans/2026-06-21-processing-tasks-plan-a-infrastructure.md`（已完成）。

---

## ⚠️ Plan B 的写法说明

Plan B 是迄今最复杂的 plan（运行时切换，~14 文件）。为保证可 review、可维护：

- **核心机制 task（Task 1-5）给完整 TDD 代码**：FGS 改写 task 表、onStart 查 task 表、store 收消息、入队、migration——这是难点，必须完整。
- **机械改造（Task 6 UI、Task 7 清理）给具体指引**：UI 4 页面是机械的「读 entry.status → 订阅 store」，给详情页一个完整示例 + 其他 3 页面的具体改动点（方法/订阅/替换），不重复展开完整 widget 代码（冗长且模式相同）。清理同理。

执行者（subagent）按指引改各页面时，参考详情页示例 + 每页的具体改动点即可。

## ⚠️ 风险：运行时切换，中间状态不 working

Plan A 不改变运行时（旧功能照常）。Plan B 改变运行时——**中间 task 完成后 app 可能行为不一致**（如 FGS 已切到写 task 表但 UI 还读 status → UI 显示 stale）。**只有全部 task 完成 + Task 8 验证通过，app 才完全 working**。中途不要在设备上测（会看到 stale）。最后统一验证。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/services/diary_processing_task.dart` | 改 | 写 task 表（status/stage/meta.asrTaskId）取代写 entry status/stage/asrTaskId |
| `lib/services/daily_summary_processing_task.dart` | 改 | 写 task 表取代写 daily_summary status |
| `lib/services/recording_processor.dart` | 改 | onStart 查 getPendingProcessingTasks + 按 task_type 分发 |
| `lib/services/processing_task_store.dart` | 改 | 收 FGS 消息 + enqueue 调 controller.start + loadFromDb 校准；`storage`→`_storage` 私有化 |
| `lib/services/processing_fgs_controller.dart` | 改 | （可能）onStopped 配合 store |
| `lib/pages/diary_detail_page.dart` | 改 | 订阅 store，banner 按 task.status/stage；_retry/_reanalyze → enqueueTask |
| `lib/pages/diary_list_page.dart` | 改 | 订阅 store.activeRefIds，卡片/行状态；手动生成 → enqueueTask |
| `lib/pages/daily_summary_page.dart` | 改 | 订阅 store，banner；_regenerate → enqueueTask |
| `lib/pages/recording_page.dart` | 改 | badge 订阅 store.activeCount；recordingComplete → store.enqueueTask |
| `lib/main.dart` | 改 | 启动 store.loadFromDb；_runDailySummaryIfNeeded → enqueueTask |
| `lib/services/database/app_database.dart` | 改 | migration 数据搬迁（status → task 表） |
| `lib/services/diary_storage_service.dart` | 改 | 废弃 status 方法（标记/移除调用） |

---

## Task 1: DiaryProcessingTask 改写 task 表

**Files:**
- Modify: `lib/services/diary_processing_task.dart`

> 本 task 把 DiaryProcessingTask 从「写 entry.status/processingStage/asrTaskId」改为「写 task 表」。FGS 是 DB 权威写入者。

- [ ] **Step 1: DiaryProcessingTask 加 task 参数**

DiaryProcessingTask 当前构造 `DiaryProcessingTask(this.entry)`。改为同时持有对应的 ProcessingTask（含 id）：

```dart
class DiaryProcessingTask implements ProcessingTask {
  final DiaryEntry entry;
  final ProcessingTask task; // 新增：对应的 processing_tasks 行（含 id）

  DiaryProcessingTask(this.entry, this.task);

  @override
  String get id => task.id; // 改为 task.id（任务 id，非 entry id）

  @override
  String get taskType => 'diary';

  @override
  String get notificationText => '语音日记 - ${entry.displayTitle}';
  ...
}
```

- [ ] **Step 2: execute 写 task 表 status=running**

`execute` 开头（logStep started 后）加：

```dart
    await ctx.storage.updateProcessingTaskStatus(task.id, TaskStatus.running);
    ctx.sendToMain({'type': 'taskStarted', 'taskId': task.id, 'refId': entry.id, 'taskType': 'diary'});
```

> import ProcessingTask/TaskStatus（从 models/processing_task.dart）。

- [ ] **Step 3: _processEntry 续跑逻辑改用 task.stage**

`_processEntry` 当前 `switch (entry.processingStage)`。改为 `switch (task.stage 解析)`：

```dart
  Future<void> _processEntry(ProcessingContext ctx) async {
    // task.stage 是字符串（'uploading'/'asr'/'llm'/'tagging'/'completed'），转 ProcessingStage
    final stage = task.stage != null
        ? ProcessingStage.fromString(task.stage!)
        : ProcessingStage.uploading;
    switch (stage) {
      case ProcessingStage.uploading:
        await _doUpload(ctx);
        if (await _doAsr(ctx)) break;
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);
      case ProcessingStage.asr:
        if (await _doAsr(ctx)) break;
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);
      case ProcessingStage.llm:
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);
      case ProcessingStage.tagging:
        await _doTagging(ctx);
        await _doComplete(ctx);
      case ProcessingStage.completed:
        await _doComplete(ctx);
    }
  }
```

- [ ] **Step 4: _doUpload / _doAsr / _doLlm 改写 task.stage（取代 entry.processingStage）**

把所有 `ctx.storage.updateTosKeyAndStage` / `updateAsrTaskIdAndStage` / `updateProcessingStage` 改为写 task 表。

`_doUpload`：tosKey 仍写 entry（`updateTosKey`，真实数据），stage 写 task：

```dart
    final tosKey = await ctx.tos.uploadAudio(audioFilePath, entry.id);
    await ctx.storage.updateTosKey(entry.id, tosKey); // tosKey 是数据，留 entry
    await ctx.storage.updateProcessingTaskStage(task.id, 'asr'); // stage 写 task
    ctx.sendToMain({'type': 'stageUpdate', 'entryId': entry.id, 'stage': 'asr'});
```

> `updateTosKey(entry.id, tosKey)` 需确认 DiaryStorageService 有此方法（只更 tosKey，不动 stage）。若无，加一个（或用 updateTosInfo）。`updateTosKeyAndStage` 不再用（stage 归 task）。

`_doAsr`：asrTaskId 写 task.meta（非 entry.asrTaskId），stage 写 task。asrTaskId 从 task.meta 读（续跑）：

```dart
    final existingAsrTaskId = task.meta['asrTaskId'] as String?;
    AsrResult asrResult;
    if (existingAsrTaskId != null) {
      // 恢复 poll
      try {
        asrResult = await ctx.asr.pollAsyncResult(existingAsrTaskId);
      } catch (e) {
        final newTaskId = await ctx.asr.submitAsync(presignedUrl);
        await ctx.storage.updateProcessingTaskMeta(task.id, {'asrTaskId': newTaskId});
        asrResult = await ctx.asr.pollAsyncResult(newTaskId);
      }
    } else {
      final asrTaskId = await ctx.asr.submitAsync(presignedUrl);
      await ctx.storage.updateProcessingTaskMeta(task.id, {'asrTaskId': asrTaskId});
      asrResult = await ctx.asr.pollAsyncResult(asrTaskId);
    }
    ...
    await ctx.storage.updateProcessingTaskStage(task.id, 'llm');
```

> 需 DiaryStorageService 加 `updateProcessingTaskMeta(id, Map)`（合并 meta，见 Step 6）。

`_doLlm`：`updateProcessingStage(tagging)` → `updateProcessingTaskStage(task.id, 'tagging')`。

- [ ] **Step 5: _doComplete / _markFailed 写 task 表**

`_doComplete`：当前 `updateEntry(status=completed, processingStage=completed)`。改为：entry 仍 updateEntry（但**不含 status/processingStage**，因业务表废弃这两列的写入——只更 title/uploadedAt 等）。task 写 completed：

```dart
  Future<void> _doComplete(ProcessingContext ctx) async {
    String title = entry.displayTitle;
    try {
      final llmResult = await ctx.storage.readLlmResult(entry.folderPath);
      title = llmResult.title;
    } catch (_) {}

    // entry 只更 title/uploadedAt（不含 status/processingStage）
    await ctx.storage.updateEntryTitleAndUploadedAt(entry.id, title);
    // task 标完成
    await ctx.storage.updateProcessingTaskStatus(task.id, TaskStatus.completed);

    FlutterForegroundTask.updateService(notificationTitle: '处理完成', notificationText: '语音日记 - $title');
    ctx.sendToMain({'type': 'completed', 'entryId': entry.id, 'taskId': task.id});
  }
```

> 需 DiaryStorageService 加 `updateEntryTitleAndUploadedAt(id, title)`（只更 title + uploadedAt，不碰 status）。

`_markFailed`：当前 `updateEntryTitleAndStatus(failed)`。改为 task failed：

```dart
  Future<void> _markFailed(ProcessingContext ctx, String error) async {
    await ctx.storage.updateProcessingTaskStatus(task.id, TaskStatus.failed, failedMessage: error);
    ctx.sendToMain({'type': 'failed', 'entryId': entry.id, 'taskId': task.id, 'error': error});
  }
```

- [ ] **Step 6: DiaryStorageService 加辅助方法**

在 `diary_storage_service.dart` 加：

```dart
  /// 只更 title + uploadedAt（不碰 status/processingStage——业务表废弃这两列）。
  Future<void> updateEntryTitleAndUploadedAt(String id, String title) async {
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id))).write(
      DiaryEntriesCompanion(
        title: Value(title),
        uploadedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 只更 tosKey（不动 stage）。
  Future<void> updateTosKey(String id, String tosKey) async {
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id))).write(
      DiaryEntriesCompanion(tosKey: Value(tosKey)),
    );
  }

  /// 合并更新 task.meta（用 jsonEncode 重新写整列）。
  Future<void> updateProcessingTaskMeta(String id, Map<String, dynamic> meta) async {
    await (_db.update(_db.processingTasks)..where((t) => t.id.equals(id))).write(
      ProcessingTasksCompanion(meta: Value(meta)),
    );
  }
```

- [ ] **Step 7: format + analyze**

Run:
```bash
dart format lib/services/diary_processing_task.dart lib/services/diary_storage_service.dart
flutter analyze
```
Expected: No issues found（DiaryProcessingTask 改完编译通过。recording_processor 的 DiaryProcessingTask.new 调用会在 Task 2 修，此处可能暂时报错——Task 2 紧接着修）。

> 若 analyze 因 recording_processor 的 `DiaryProcessingTask.new` 参数不匹配报错，先在 Task 2 修 recording_processor，再回来跑 analyze。两 task 衔接处允许短暂编译错误。

- [ ] **Step 8: Commit**

```bash
git add lib/services/diary_processing_task.dart lib/services/diary_storage_service.dart
git commit -m "$(cat <<'EOF'
refactor: DiaryProcessingTask 改写 processing_tasks 表（取代 entry status/stage）

- DiaryProcessingTask 持有 ProcessingTask（含 id），续跑读 task.stage
- _doUpload/_doAsr/_doLlm 写 task.stage + asrTaskId 进 task.meta
- _doComplete/_markFailed 写 task.status（completed/failed）
- entry 只更 title/uploadedAt/tosKey（废弃 status/processingStage/asrTaskId 写入）
- storage 加 updateEntryTitleAndUploadedAt/updateTosKey/updateProcessingTaskMeta

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: DailySummaryProcessingTask + onStart 查 task 表

**Files:**
- Modify: `lib/services/daily_summary_processing_task.dart`
- Modify: `lib/services/recording_processor.dart`

- [ ] **Step 1: DailySummaryProcessingTask 持有 task + 写 task 表**

类似 Task 1。DailySummaryProcessingTask(this.date) → DailySummaryProcessingTask(this.task)，task.refId = date。execute 写 task.status（running/completed/failed）。daily_summary 表只更内容（title/sourceEntryIds），不更 status。

```dart
class DailySummaryProcessingTask implements ProcessingTask {
  final ProcessingTask task;
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
    await ctx.storage.updateProcessingTaskStatus(task.id, TaskStatus.running);
    ctx.sendToMain({'type': 'taskStarted', 'taskId': task.id, 'refId': date, 'taskType': 'daily_summary'});
    // ... 现有逻辑（查 entries、summarizeDay、_saveCompleted/_markFailed）
    // _saveCompleted: 写 daily_summary 内容（不含 status）+ task.status=completed
    // _markFailed: task.status=failed
  }
  ...
}
```

> `_saveCompleted` 当前 `saveDailySummary(status=completed)`——改为 saveDailySummary 不含 status（或 status 字段废弃后忽略）+ `updateProcessingTaskStatus(task.id, completed)`。daily_summary 表的 status 列废弃（保留不读写）。

- [ ] **Step 2: onStart 查 getPendingProcessingTasks + 按 task_type 分发**

`recording_processor.dart` 的 `ProcessingTaskHandler.onStart` 当前查 `getPendingEntries` + `getPendingDailySummaries`。改为查 `getPendingProcessingTasks`（统一 task 表），按 task_type 分发：

```dart
    final tasks = await storage.getPendingProcessingTasks();
    final diaryTasks = <ProcessingTask>[];
    final summaryTasks = <ProcessingTask>[];
    for (final t in tasks) {
      if (t.taskType == TaskType.diary) {
        diaryTasks.add(t);
      } else {
        summaryTasks.add(t);
      }
    }

    // diary 在前、summary 在后（summary 依赖当天 diary 已处理）
    final handlers = <ProcessingTask>[];
    // 包装成 ProcessingTask handler（实现统一接口的 task handler）
    ...
```

> 这里需要重新设计 handler 包装：onStart 拿到 List<ProcessingTask>，diary 的要 getEntryById(refId) 拿 entry 再构造 DiaryProcessingTask(entry, task)；summary 的构造 DailySummaryProcessingTask(task)。

具体 onStart 改造：

```dart
    final pendingTasks = await storage.getPendingProcessingTasks();
    final List<Future<void> Function(ProcessingContext)> executors = [];

    for (final t in pendingTasks) {
      if (t.taskType == TaskType.diary) {
        final entry = await storage.getEntryById(t.refId);
        executors.add((ctx) => DiaryProcessingTask(entry, t).execute(ctx));
      } else {
        executors.add((ctx) => DailySummaryProcessingTask(t).execute(ctx));
      }
    }

    if (executors.isEmpty) {
      _sendToMain({'type': 'processingDone'});
      await _stopService();
      return;
    }

    for (final exec in executors) {
      try {
        await exec(ctx);
      } catch (e) {
        debugPrint('[ProcessingHandler] task 未捕获异常: $e');
      }
    }
```

> import TaskType、DiaryProcessingTask、DailySummaryProcessingTask、ProcessingTask（models）。

- [ ] **Step 3: format + analyze + Commit**

```bash
dart format lib/services/daily_summary_processing_task.dart lib/services/recording_processor.dart
flutter analyze
git add lib/services/daily_summary_processing_task.dart lib/services/recording_processor.dart
git commit -m "$(cat <<'EOF'
refactor: DailySummaryProcessingTask 写 task 表；onStart 查 processing_tasks

- DailySummaryProcessingTask 持有 ProcessingTask，写 task.status
- daily_summary 表 status 废弃（只存内容）
- onStart 查 getPendingProcessingTasks，按 task_type 分发（diary getEntryById 后构造）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: ProcessingTaskStore 收 FGS 消息 + enqueue 接 controller

**Files:**
- Modify: `lib/services/processing_task_store.dart`
- Modify: `lib/services/processing_fgs_controller.dart`（如需）

- [ ] **Step 1: store 注册 taskDataCallback 收消息**

store 加消息处理。注册一个 callback，收 processing 类消息（stageUpdate/completed/failed/taskStarted/processingDone/dailySummaryXxx），更新内存 + 通知 + 调 controller.onStopped（processingDone 时）。

在 `processing_task_store.dart` 加：

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'processing_fgs_controller.dart';

class ProcessingTaskStore {
  final DiaryStorageService _storage; // 改私有（清理 Task 7 的 _storage 私有化提前到这里）
  final ProcessingFgsController _controller;
  final _uuid = const Uuid();
  final Map<String, ProcessingTask> _activeByRefId = {};
  final ValueNotifier<Set<String>> activeRefIds = ValueNotifier(const {});

  ProcessingTaskStore({
    required DiaryStorageService storage,
    required ProcessingFgsController controller,
  })  : _storage = storage,
        _controller = controller;

  /// 注册 FGS 消息回调（app 启动时调）。收 processing 类消息更新内存。
  void startListening() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  /// 注销（app 退出/dispose）。
  void stopListening() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
  }

  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    final refId = data['refId'] as String? ?? data['entryId'] as String?;
    final taskId = data['taskId'] as String?;

    switch (type) {
      case 'taskStarted':
        // task 开始跑：从 DB 读最新行刷新内存（status=running）
        if (refId != null) _refreshFromDb(refId);
      case 'stageUpdate':
        // 阶段变化：更新内存 task.stage（UI 显示进度）
        if (refId != null && _activeByRefId.containsKey(refId)) {
          final stage = data['stage'] as String?;
          _activeByRefId[refId] = _activeByRefId[refId]!.copyWith(stage: stage);
          _notify();
        }
      case 'completed':
      case 'failed':
      case 'dailySummaryCompleted':
      case 'dailySummaryFailed':
        // task 结束：从内存移除（active→done）
        if (refId != null) {
          _activeByRefId.remove(refId);
          _notify();
        }
      case 'processingDone':
        // FGS 整体停止：通知 controller 清 isRunning
        _controller.onStopped();
    }
  }

  Future<void> _refreshFromDb(String refId) async {
    final latest = await _storage.getLatestProcessingTask(refId);
    if (latest != null && latest.isActive) {
      _activeByRefId[refId] = latest;
    } else {
      _activeByRefId.remove(refId);
    }
    _notify();
  }

  // enqueueTask 改为调 controller.start（触发 FGS）：
  Future<ProcessingTask> enqueueTask({
    required TaskType taskType,
    required String refId,
    String? stage,
    Map<String, dynamic> meta = const {},
  }) async {
    final task = ProcessingTask(
      id: _uuid.v4(),
      taskType: taskType,
      refId: refId,
      status: TaskStatus.queued,
      stage: stage,
      meta: meta,
      queuedAt: DateTime.now(),
    );
    await _storage.insertProcessingTask(task);
    _activeByRefId[refId] = task;
    _notify();
    await _controller.start(); // 触发 FGS 处理队列（Plan B 接入）
    return task;
  }

  // loadFromDb / getTask / isProcessing / activeCount 不变
  ...
}
```

> ProcessingTask.copyWith 需支持 stage（model 加 copyWith，或在 store 重新构造）。若 model 无 copyWith，store 里 `_activeByRefId[refId] = ProcessingTask(...全部字段..., stage: stage)` 重新构造。

- [ ] **Step 2: ProcessingTask model 加 copyWith（若需要）**

`lib/models/processing_task.dart` 加：

```dart
  ProcessingTask copyWith({String? stage, TaskStatus? status}) {
    return ProcessingTask(
      id: id,
      taskType: taskType,
      refId: refId,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      failedMessage: failedMessage,
      meta: meta,
      queuedAt: queuedAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
  }
```

- [ ] **Step 3: format + analyze + Commit**

```bash
dart format lib/services/processing_task_store.dart lib/models/processing_task.dart
flutter analyze
git add lib/services/processing_task_store.dart lib/models/processing_task.dart
git commit -m "$(cat <<'EOF'
feat: ProcessingTaskStore 收 FGS 消息 + enqueue 调 controller.start

- 注册 taskDataCallback 收 processing 类消息（taskStarted/stageUpdate/completed/
  failed/processingDone），更新内存 + 通知 UI
- processingDone → controller.onStopped（清 isRunning）
- enqueueTask 调 controller.start 触发 FGS（Plan B 接入）
- storage 私有化 _storage；model 加 copyWith

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 入口改 store.enqueueTask（录音完成 / 重新分析 / 生成总结 / 启动钩子）

**Files:**
- Modify: `lib/pages/recording_page.dart`（recordingComplete）
- Modify: `lib/pages/diary_detail_page.dart`（_reanalyze / _retry）
- Modify: `lib/pages/diary_list_page.dart`（手动生成 daily summary）
- Modify: `lib/pages/daily_summary_page.dart`（_regenerate）
- Modify: `lib/main.dart`（_runDailySummaryIfNeeded + store 初始化）

> 这些入口当前各自调 `ProcessingFgsController.start/schedule` 或直接设 status。改为统一调 `store.enqueueTask(...)`（store 内部调 controller.start）。

- [ ] **Step 1: app 启动初始化 store + loadFromDb + startListening**

`main.dart`：在 runApp 前初始化全局 store（单例），loadFromDb + startListening。

```dart
// main.dart 顶部
import 'services/processing_task_store.dart';
import 'services/processing_fgs_controller.dart';

late final ProcessingTaskStore processingTaskStore;

void main() async {
  ...
  // 初始化 task store（全局单例）
  processingTaskStore = ProcessingTaskStore(
    storage: DiaryStorageService(),
    controller: ProcessingFgsController(),
  );
  await processingTaskStore.loadFromDb();
  processingTaskStore.startListening();
  ...
  runApp(const VoiceDiaryApp());
}
```

> UI 通过全局 `processingTaskStore` 访问（或用 InheritedWidget/provider 注入，但项目用全局单例模式，参考 AppDatabase）。

- [ ] **Step 2: 各入口改 enqueueTask**

**recording_page recordingComplete**：当前 `ProcessingFgsController.schedule()`。改为录音完成后入队 diary task：

```dart
      case 'recordingComplete':
        FgsRuntime.setNone();
        // 入队 diary 处理任务（refId = 当前录音的 entryId）
        await processingTaskStore.enqueueTask(
          taskType: TaskType.diary,
          refId: _currentEntryId, // 录音完成时的 entry id
          stage: 'uploading',
        );
```

> 需确认 recording_page 怎么拿到当前 entryId（recording_task_handler 创建 entry 后存了 folderId/id，通过 getData 或返回值）。若当前没存 entryId，需在 recordingComplete 消息里带上，或 RecordingPage 持有。

**diary_detail_page _reanalyze**：当前 `resetEntryForReanalysis + ProcessingFgsController.start`。改为 enqueueTask（重置 stage=asr + 清 asrTaskId）：

```dart
  Future<void> _reanalyze() async {
    // 确认弹窗（保留）...
    await processingTaskStore.enqueueTask(
      taskType: TaskType.diary,
      refId: _entry.id,
      stage: 'asr', // 全量重跑（reanalyze 重置）
      meta: const {}, // 清 asrTaskId
    );
    // 乐观更新（订阅 store 自动刷新，可能不需要手动 setState）
  }
```

> `resetEntryForReanalysis` 不再需要（enqueueTask 新建 task 行，不碰 entry status）。

**diary_detail_page _retry**（失败续跑）：改为 enqueueTask（继承 stage）。需先读旧 failed task 的 stage + meta：

```dart
  Future<void> _retry() async {
    final oldTask = await _storage.getLatestProcessingTask(_entry.id);
    await processingTaskStore.enqueueTask(
      taskType: TaskType.diary,
      refId: _entry.id,
      stage: oldTask?.stage ?? 'asr', // 继承失败处的 stage（续跑）
      meta: oldTask?.meta ?? const {}, // 继承 asrTaskId
    );
  }
```

**diary_list_page 手动生成 daily summary / daily_summary_page _regenerate**：

```dart
    await processingTaskStore.enqueueTask(
      taskType: TaskType.dailySummary,
      refId: date, // 'yyyy-MM-dd'
    );
```

**main.dart _runDailySummaryIfNeeded**：判断改为查 task 表（有无该 date 的 active task），入队走 enqueueTask。

- [ ] **Step 3: format + analyze + Commit**

```bash
dart format lib/pages/recording_page.dart lib/pages/diary_detail_page.dart lib/pages/diary_list_page.dart lib/pages/daily_summary_page.dart lib/main.dart
flutter analyze
git add lib/pages/ lib/main.dart
git commit -m "$(cat <<'EOF'
refactor: 入口统一走 ProcessingTaskStore.enqueueTask

- recording_complete → enqueueTask(diary, uploading)
- _reanalyze → enqueueTask(diary, asr, 重置)
- _retry → enqueueTask(diary, 继承 stage/meta 续跑)
- 手动生成 daily summary / _regenerate → enqueueTask(dailySummary, date)
- main 启动初始化 processingTaskStore（loadFromDb + startListening）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: migration 数据搬迁（status → task 表）

**Files:**
- Modify: `lib/services/database/app_database.dart`（onUpgrade from<9 加数据搬迁）

- [ ] **Step 1: onUpgrade from<9 加数据搬迁**

当前 `from < 9` 只建表。加数据搬迁（从 DiaryEntries.status/DailySummaries.status 生成 task 行）：

```dart
      if (from < 9) {
        if (!await _tableExists('processing_tasks')) {
          await m.createTable(processingTasks);
          // 数据搬迁：旧 status → processing_tasks 行
          await _migrateStatusToTasks();
        }
      }
```

加 `_migrateStatusToTasks` 方法（customStatement 或 select+insert）：

```dart
  /// 把旧 DiaryEntries/DailySummaries 的 status 搬到 processing_tasks。
  /// processing/failed → 建 task 行；completed 不补。
  Future<void> _migrateStatusToTasks() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // diary
    final diaryRows = await customSelect(
      "SELECT id, status, processing_stage, asr_task_id FROM diary_entries "
      "WHERE status IN ('processing', 'failed')",
    ).get();
    for (final r in diaryRows) {
      final status = r.read<String>('status');
      final stage = r.read<String?>('processing_stage');
      final asrTaskId = r.read<String?>('asr_task_id');
      await into(processingTasks).insert(ProcessingTasksCompanion.insert(
        id: 'migrated-diary-${r.read<String>('id')}',
        taskType: 'diary',
        refId: r.read<String>('id'),
        status: Value(status == 'failed' ? 'failed' : 'running'),
        stage: Value(stage),
        meta: Value(asrTaskId != null ? {'asrTaskId': asrTaskId} : {}),
        queuedAt: now,
      ));
    }
    // daily_summary（同理，refId=date）
    final summaryRows = await customSelect(
      "SELECT date, status FROM daily_summaries WHERE status IN ('processing', 'failed')",
    ).get();
    for (final r in summaryRows) {
      final status = r.read<String>('status');
      await into(processingTasks).insert(ProcessingTasksCompanion.insert(
        id: 'migrated-summary-${r.read<String>('date')}',
        taskType: 'daily_summary',
        refId: r.read<String>('date'),
        status: Value(status == 'failed' ? 'failed' : 'running'),
        queuedAt: now,
      ));
    }
  }
```

- [ ] **Step 2: migration 测试（可选但推荐）**

构造旧 schema DB（status 数据）→ 触发 migration → 验证 task 表生成。drift 测试 migration 较复杂（需 MigrationStrategy 测试），可作为手动验证（Task 8）。

- [ ] **Step 3: format + analyze + Commit**

```bash
dart format lib/services/database/app_database.dart
flutter analyze
git add lib/services/database/app_database.dart
git commit -m "$(cat <<'EOF'
feat: migration 搬迁旧 status 数据到 processing_tasks

from<9 建表后，把 DiaryEntries/DailySummaries 的 processing/failed 行
生成对应 task 行（completed 不补）。幂等（仅建表时执行一次）。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: UI 订阅 store（详情页完整示例 + 其他页面指引）

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`（完整示例）
- Modify: `lib/pages/diary_list_page.dart` / `daily_summary_page.dart` / `recording_page.dart`（指引）

> UI 从「读 entry.status/processingStage」改为「订阅 processingTaskStore」。详情页给完整示例，其他页面按同样模式改。

- [ ] **Step 1: DiaryDetailPage 订阅 store（完整示例）**

详情页当前 `_buildStatusBanner` 读 `_entry.status`/`processingStage`。改为读 `processingTaskStore.getTask(_entry.id)` + 订阅 `activeRefIds`。

关键改动：
- `initState` 加 `processingTaskStore.activeRefIds.addListener(_onStoreChange)`
- `dispose` 移除 listener
- `_onStoreChange` → setState 刷新
- `_buildStatusBanner` 改为读 `processingTaskStore.getTask(_entry.id)`：

```dart
  Widget _buildStatusBanner() {
    final task = processingTaskStore.getTask(_entry.id);
    if (task == null) return const SizedBox.shrink(); // 无 active task = 不在处理

    if (task.status == TaskStatus.running || task.status == TaskStatus.queued) {
      final stageText = switch (task.stage) {
        'uploading' => '上传',
        'asr' => '语音识别',
        'llm' => 'AI 总结',
        'tagging' => '自动归类',
        _ => '处理中',
      };
      // ... 返回处理中横幅（用 stageText）
    }
    // failed 由 getLatestProcessingTask 读历史（或 store 内存只含 active，
    // failed 要查 DB）。这里简化：failed 横幅读 DB 最新 task。
    return const SizedBox.shrink();
  }
```

> failed 状态：store 内存只含 active（queued/running），failed 的要查 DB（`getLatestProcessingTask`）。详情页加载时查一次最新 task（含 failed）显示失败横幅。这部分细节执行者按现有 _buildStatusBanner 的 failed 分支适配（读 task failed_message/stage）。

- [ ] **Step 2: DiaryListPage 指引**

- 卡片状态：当前读 `entry.status`（processing/failed 样式）。改为 `processingTaskStore.isProcessing(entry.id)`（处理中样式）。订阅 `activeRefIds` 刷新。
- daily_summary 行状态：读 `processingTaskStore.isProcessing(date)` 或查 DB 最新 task。
- 订阅：`processingTaskStore.activeRefIds.addListener(_onStoreChange)` + setState。

- [ ] **Step 3: DailySummaryPage 指引**

- `_buildStatusBanner` 读 `processingTaskStore.getTask(date)` / DB 最新 task（failed）。
- 订阅 `activeRefIds`。

- [ ] **Step 4: RecordingPage 指引**

- badge：当前 `getProcessingEntryCount`。改为 `processingTaskStore.activeCount`。订阅 `activeRefIds` 刷新 badge。

- [ ] **Step 5: format + analyze + Commit**

```bash
dart format lib/pages/
flutter analyze
git add lib/pages/
git commit -m "$(cat <<'EOF'
refactor: UI 订阅 ProcessingTaskStore（取代读 entry.status）

- DiaryDetailPage banner 读 store.getTask + 订阅 activeRefIds（完整示例）
- DiaryListPage 卡片/行状态读 store.isProcessing
- DailySummaryPage banner 读 store
- RecordingPage badge 读 store.activeCount

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 清理废弃 status 读写

**Files:**
- Modify: `lib/services/diary_storage_service.dart`（废弃 status 方法）
- Modify: 各处残留 status 引用

- [ ] **Step 1: grep 残留 status/processingStage/asrTaskId 读写**

```bash
grep -rn "entry.status\|processingStage\|asrTaskId\|getPendingEntries\|getPendingDailySummaries\|updateEntryStatus\|updateEntryTitleAndStatus\|resetEntryForReanalysis\|updateProcessingStage\|updateTosKeyAndStage\|updateAsrTaskIdAndStage" lib/ --include="*.dart"
```

逐一确认：哪些已废弃（不再调用）、哪些还有残留。废弃的方法标记 `@deprecated` 或删除（CLAUDE.md 说废弃方法保留，所以标记 @deprecated 注释"已废弃，改用 task 表"）。

- [ ] **Step 2: 清理残留**

- `getPendingEntries`/`getPendingDailySummaries`/`getProcessingEntryCount`：已被 task 表查询取代，标记 @deprecated。
- `updateEntryStatus`/`updateEntryTitleAndStatus`/`resetEntryForReanalysis`/`updateProcessingStage`/`updateTosKeyAndStage`/`updateAsrTaskIdAndStage`：标记 @deprecated（业务表 status 写入废弃）。
- DiaryEntries model 的 status/processingStage/asrTaskId 字段：保留（drift 行类还有），但 model 层 DiaryEntry 可保留字段（向后兼容读）或标记废弃。**不删列**（CLAUDE.md）。

- [ ] **Step 3: format + analyze + Commit**

```bash
dart format lib/services/diary_storage_service.dart
flutter analyze
git add lib/services/diary_storage_service.dart
git commit -m "$(cat <<'EOF'
chore: 废弃业务表 status 相关方法（标记 @deprecated）

getPendingEntries/getPendingDailySummaries/getProcessingEntryCount/
updateEntryStatus/updateEntryTitleAndStatus/resetEntryForReanalysis/
updateProcessingStage/updateTosKeyAndStage/updateAsrTaskIdAndStage
均已由 task 表取代，标记废弃。列保留（不删，向后兼容）。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: 全量验证

- [ ] **Step 1: 全量 analyze + test**

Run: `flutter analyze` → No issues. `flutter test` → all pass.

- [ ] **Step 2: 手动验证清单（设备）**

这是运行时切换，**必须在设备上完整验证**：

- [ ] **正常录音**：录音 → 录音后 diary task 入队 → FGS 处理（ASR/LLM/tag）→ 详情页显示结果（task=completed）
- [ ] **详情页进度**：录音后立即看详情页 → banner 显示「语音识别中...」→ 流转 → 完成
- [ ] **badge**：处理中时 RecordingPage badge 显示数量 → 完成后归零
- [ ] **失败 + retry**：断网模拟 ASR 失败 → task=failed → 详情页失败横幅 → 点重新处理 → 新 task 继承 stage 续跑 → 完成
- [ ] **重新分析**：completed 日记点重新分析 → 新 task（stage=asr 重置）→ 全量重跑 → 结果更新
- [ ] **每日总结**：手动生成 → daily_summary task 入队 → FGS 处理 → 完成
- [ ] **启动恢复**：杀 app 有未完成 task → 重启 → store.loadFromDb 拾取 → FGS 续跑
- [ ] **migration**：旧版本 DB（有 status 数据）→ 升级 → task 表生成 processing/failed 行 → 续跑
- [ ] **录音中处理**：录音中触发处理 → 不中断录音（mode==recording 拒绝/入队等待）

- [ ] **Step 3: 回归确认**

- 既有功能（录音/播放/标签/列表）不受影响
- 旧数据（v1.0.0+）可读

---

## Self-Review

（执行前由计划作者完成）

**1. Spec coverage（Plan B 范围）**：
- FGS 写 task 表：Task 1/2 ✓
- store 收消息 + enqueue 接 controller：Task 3 ✓
- 入口 enqueueTask：Task 4 ✓
- migration 数据搬迁：Task 5 ✓
- UI 订阅 store：Task 6 ✓
- 废弃 status：Task 7 ✓
- 验证：Task 8 ✓

**2. Placeholder scan**：Task 6（UI）用指引而非完整代码（详情页完整 + 其他指引）——这是刻意的写法（文档开头说明），执行者按指引 + 详情页示例改。其余核心 task 完整代码。

**3. Type consistency**：
- ProcessingTask/TaskType/TaskStatus 跨 task 一致（Plan A 定义，Plan B 用）
- DiaryProcessingTask(entry, task) / DailySummaryProcessingTask(task) 构造跨 task 一致
- store.enqueueTask 签名跨 task 一致

**4. 风险**：运行时切换，中间不 working（文档开头说明）。Task 8 设备验证是必须的。

---

## Execution Handoff

Plan B 完成（切换 + 验证）后，processing tasks 表化重构全部完成。接着用 `superpowers:finishing-a-development-branch` 处理 `feature/re-processing` 的合并/PR（含 Plan A + Plan B + 之前的 reanalyze/ProcessingFgsController 重构/daily-summary 一致性修复/record 升级等）。

# Processing Tasks 表化 · Plan A：基础设施 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭建 processing_tasks 表 + model + storage CRUD + ProcessingTaskStore 的基础设施（内存集合/查询/enqueue/ValueNotifier），单测覆盖。**旧功能完全不变**（FGS/UI 还用 status），新代码就绪但未接入运行时。

**Architecture:** 新建 `processing_tasks` drift 表（通用字段直接列 + `meta` JSON）+ model；`DiaryStorageService` 加 task 表 CRUD；`ProcessingTaskStore`（main isolate 的 task 状态中心：内存活跃集合 + 查询 + enqueue + ValueNotifier + 启动加载）。本 plan **不接 FGS、不接 UI、不动业务表 status**——纯基础设施 + 单测。Plan B 负责切换接入。

**Tech Stack:** Flutter / drift（SQLite ORM + build_runner）/ flutter_test（+ NativeDatabase.memory 测 drift）。

完整设计见 `docs/superpowers/specs/2026-06-21-processing-tasks-table-design.md`。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/services/database/tables.dart` | 改 | 新增 `ProcessingTasks` 表 + `MapConverter`（meta JSON） |
| `lib/services/database/app_database.dart` | 改 | `@DriftDatabase` 加表、`schemaVersion` 8→9、migration 建表 |
| `lib/services/database/app_database.g.dart` | 重新生成 | drift codegen（勿手编） |
| `lib/models/processing_task.dart` | 新建 | `ProcessingTask` model + `TaskStatus`/`TaskType` enum |
| `lib/services/diary_storage_service.dart` | 改 | task 表 CRUD（insert/update status/update stage/get pending/get latest） |
| `lib/services/processing_task_store.dart` | 新建 | task 状态中心（内存 + 查询 + enqueue + ValueNotifier + 启动加载） |
| `test/processing_task_storage_test.dart` | 新建 | storage CRUD 单测 |
| `test/processing_task_store_test.dart` | 新建 | store 单测 |

**不动**：`processing_fgs_controller.dart`（Plan B 收窄）、FGS tasks、UI、业务表 status 字段。

---

## Task 1: `ProcessingTasks` 表 + migration + codegen

**Files:**
- Modify: `lib/services/database/tables.dart`（加 `MapConverter` + `ProcessingTasks`）
- Modify: `lib/services/database/app_database.dart`（`@DriftDatabase` 加表、schemaVersion、migration）
- Regenerate: `lib/services/database/app_database.g.dart`

- [ ] **Step 1: tables.dart 加 `MapConverter` + `ProcessingTasks` 表**

在 `lib/services/database/tables.dart` 顶部 import 区加：

```dart
import 'dart:convert';
```

在 import 区之后、`class DiaryEntries` 之前加 `MapConverter`：

```dart
/// drift TypeConverter：Map<String, dynamic> ↔ JSON text（用于 ProcessingTasks.meta）。
class MapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const MapConverter();
  @override
  Map<String, dynamic> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}
```

在文件末尾（`DailySummaries` class 之后）加 `ProcessingTasks` 表：

```dart
/// 处理任务队列表（消息队列语义）。每行一个处理任务，completed/failed 行保留作历史。
/// 行类名用 DataClassName 显式指定为 ProcessingTaskRow，避免与 model 层
/// ProcessingTask（lib/models/processing_task.dart）同名冲突。
@DataClassName('ProcessingTaskRow')
class ProcessingTasks extends Table {
  /// 任务 id（UUID）。
  TextColumn get id => text()();

  /// 'diary' | 'daily_summary'（可扩展）。
  TextColumn get taskType => text()();

  /// diary 的 entryId，或 daily_summary 的日期 'yyyy-MM-dd'。
  TextColumn get refId => text()();

  /// 'queued' | 'running' | 'completed' | 'failed'。
  TextColumn get status => text().withDefault(const Constant('queued'))();

  /// 通用调度字段，FGS 续跑用。diary: uploading/asr/llm/tagging；daily_summary 可 null。
  TextColumn get stage => text().nullable()();

  /// task 进入 failed 时的原因（异常 toString）。只在 failed 时写。
  TextColumn get failedMessage => text().nullable()();

  /// 任务专有数据（JSON）。diary 的 {"asrTaskId":"..."}；daily_summary 的 {}。
  TextColumn get meta => text().map(const MapConverter()).withDefault(const Constant('{}'))();

  /// 入队时间（毫秒）。
  IntColumn get queuedAt => integer()();

  /// FGS 开始处理时间。
  IntColumn get startedAt => integer().nullable()();

  /// 完成/失败时间。
  IntColumn get finishedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: app_database.dart 加表 + schemaVersion + migration**

在 `lib/services/database/app_database.dart` 的 `@DriftDatabase` 注解加 `ProcessingTasks`：

```dart
@DriftDatabase(
  tables: [DiaryEntries, Tags, DiaryTagRelations, ApiLogs, DailySummaries, ProcessingTasks],
)
```

把 `schemaVersion` 从 8 改为 9：

```dart
  @override
  int get schemaVersion => 9;
```

在 `onUpgrade` 的 `if (from < 8) { ... }` 之后加 `if (from < 9)` 块：

```dart
      if (from < 9) {
        if (!await _tableExists('processing_tasks')) {
          await m.createTable(processingTasks);
        }
      }
```

- [ ] **Step 3: 重新生成 drift codegen**

Run:
```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: 成功生成 `app_database.g.dart`（含 `ProcessingTaskRow`、`ProcessingTasksCompanion`、`_$AppDatabase.processingTasks` getter）。

- [ ] **Step 4: 验证编译 + analyze**

Run:
```bash
flutter analyze
```
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/database/app_database.g.dart
git commit -m "$(cat <<'EOF'
feat: 新增 processing_tasks 表（schemaVersion 9）

消息队列语义的处理任务表：通用字段直接列（task_type/ref_id/status/stage/
failed_message/timestamps）+ meta JSON 存专有数据。completed/failed 行保留。
migration 幂等建表。本 commit 只加表结构，不接入运行时。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `ProcessingTask` model

**Files:**
- Create: `lib/models/processing_task.dart`

- [ ] **Step 1: 新建 model**

新建 `lib/models/processing_task.dart`：

```dart
import 'package:flutter/foundation.dart';

/// 处理任务类型。
enum TaskType {
  diary,
  dailySummary;

  static TaskType fromString(String s) {
    switch (s) {
      case 'diary':
        return TaskType.diary;
      case 'daily_summary':
        return TaskType.dailySummary;
    }
    return TaskType.diary;
  }

  String get value {
    switch (this) {
      case TaskType.diary:
        return 'diary';
      case TaskType.dailySummary:
        return 'daily_summary';
    }
  }
}

/// 处理任务状态（消息队列语义）。
enum TaskStatus {
  queued,
  running,
  completed,
  failed;

  static TaskStatus fromString(String s) {
    switch (s) {
      case 'queued':
        return TaskStatus.queued;
      case 'running':
        return TaskStatus.running;
      case 'completed':
        return TaskStatus.completed;
      case 'failed':
        return TaskStatus.failed;
    }
    return TaskStatus.queued;
  }

  String get value {
    switch (this) {
      case TaskStatus.queued:
        return 'queued';
      case TaskStatus.running:
        return TaskStatus.running;
      case TaskStatus.completed:
        return TaskStatus.completed;
      case TaskStatus.failed:
        return TaskStatus.failed;
    }
  }
}

/// processing_tasks 表的 model（与 drift 行 ProcessingTaskRow 分离，同 DiaryEntry 模式）。
@immutable
class ProcessingTask {
  final String id;
  final TaskType taskType;
  final String refId;
  final TaskStatus status;
  final String? stage;
  final String? failedMessage;
  final Map<String, dynamic> meta;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const ProcessingTask({
    required this.id,
    required this.taskType,
    required this.refId,
    required this.status,
    required this.queuedAt,
    this.stage,
    this.failedMessage,
    this.meta = const {},
    this.startedAt,
    this.finishedAt,
  });

  /// 是否处于活跃状态（在队列或正在跑）。
  bool get isActive => status == TaskStatus.queued || status == TaskStatus.running;
}
```

- [ ] **Step 2: format + analyze + Commit**

```bash
dart format lib/models/processing_task.dart
flutter analyze
git add lib/models/processing_task.dart
git commit -m "$(cat <<'EOF'
feat: 新增 ProcessingTask model + TaskType/TaskStatus enum

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `DiaryStorageService` task 表 CRUD

**Files:**
- Modify: `lib/services/diary_storage_service.dart`
- Test: `test/processing_task_storage_test.dart`（新建）

- [ ] **Step 1: 写 storage 失败测试**

新建 `test/processing_task_storage_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/processing_task.dart';
import 'package:voice_diary/services/database/app_database.dart';
import 'package:voice_diary/services/diary_storage_service.dart';

void main() {
  late AppDatabase db;
  late DiaryStorageService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = DiaryStorageService.forTesting(db);
  });
  tearDown(() async => await db.close());

  ProcessingTask _sample({
    required String id,
    String refId = 'entry-1',
    TaskStatus status = TaskStatus.queued,
    String? stage = 'asr',
    Map<String, dynamic>? meta,
    DateTime? queuedAt,
  }) =>
      ProcessingTask(
        id: id,
        taskType: TaskType.diary,
        refId: refId,
        status: status,
        stage: stage,
        meta: meta ?? const {},
        queuedAt: queuedAt ?? DateTime(2026, 6, 21),
      );

  group('insertProcessingTask + getLatestProcessingTask', () {
    test('插入后能按 ref_id 取到最新行', () async {
      await service.insertProcessingTask(_sample(id: 't1', refId: 'e1'));
      final latest = await service.getLatestProcessingTask('e1');
      expect(latest, isNotNull);
      expect(latest!.id, 't1');
      expect(latest.status, TaskStatus.queued);
      expect(latest.stage, 'asr');
    });

    test('多条同 ref_id → 取 queued_at 最新', () async {
      await service.insertProcessingTask(
        _sample(id: 't1', refId: 'e1', queuedAt: DateTime(2026, 6, 21, 10)),
      );
      await service.insertProcessingTask(
        _sample(id: 't2', refId: 'e1', queuedAt: DateTime(2026, 6, 21, 14)),
      );
      final latest = await service.getLatestProcessingTask('e1');
      expect(latest!.id, 't2'); // t2 的 queued_at 更晚
    });

    test('meta JSON 读写正确', () async {
      await service.insertProcessingTask(
        _sample(id: 't1', meta: {'asrTaskId': 'asr-xyz'}),
      );
      final latest = await service.getLatestProcessingTask('entry-1');
      expect(latest!.meta['asrTaskId'], 'asr-xyz');
    });
  });

  group('updateProcessingTaskStatus', () {
    test('更新 status + 写 finished_at（completed/failed）', () async {
      await service.insertProcessingTask(_sample(id: 't1', refId: 'e1'));
      await service.updateProcessingTaskStatus('t1', TaskStatus.failed,
          failedMessage: 'ASR 超时');
      final latest = await service.getLatestProcessingTask('e1');
      expect(latest!.status, TaskStatus.failed);
      expect(latest.failedMessage, 'ASR 超时');
      expect(latest.finishedAt, isNotNull);
    });
  });

  group('getPendingProcessingTasks', () {
    test('只返回 queued + running，按 queued_at 升序', () async {
      await service.insertProcessingTask(
        _sample(id: 't1', refId: 'e1', status: TaskStatus.queued),
      );
      await service.insertProcessingTask(
        _sample(id: 't2', refId: 'e2', status: TaskStatus.completed),
      );
      await service.insertProcessingTask(
        _sample(id: 't3', refId: 'e3', status: TaskStatus.running),
      );
      final pending = await service.getPendingProcessingTasks();
      expect(pending.length, 2); // t1 + t3
      expect(pending.map((t) => t.id), containsAll(['t1', 't3']));
    });
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/processing_task_storage_test.dart`
Expected: FAIL — `insertProcessingTask` / `getLatestProcessingTask` 等方法未定义。

- [ ] **Step 3: 实现 storage CRUD**

在 `lib/services/diary_storage_service.dart` 顶部 import 区加：

```dart
import '../models/processing_task.dart';
```

在 `DiaryStorageService` 类内（末尾）加 task 表方法：

```dart
  // --- ProcessingTasks ---

  ProcessingTask _rowToModel(ProcessingTaskRow r) => ProcessingTask(
        id: r.id,
        taskType: TaskType.fromString(r.taskType),
        refId: r.refId,
        status: TaskStatus.fromString(r.status),
        stage: r.stage,
        failedMessage: r.failedMessage,
        meta: r.meta,
        queuedAt: DateTime.fromMillisecondsSinceEpoch(r.queuedAt),
        startedAt: r.startedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(r.startedAt!)
            : null,
        finishedAt: r.finishedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(r.finishedAt!)
            : null,
      );

  Future<void> insertProcessingTask(ProcessingTask task) async {
    await _db.insertProcessingTask(
      ProcessingTasksCompanion.insert(
        id: task.id,
        taskType: task.taskType.value,
        refId: task.refId,
        status: Value(task.status.value),
        stage: Value(task.stage),
        failedMessage: Value(task.failedMessage),
        meta: Value(task.meta),
        queuedAt: task.queuedAt.millisecondsSinceEpoch,
        startedAt: Value(task.startedAt?.millisecondsSinceEpoch),
        finishedAt: Value(task.finishedAt?.millisecondsSinceEpoch),
      ),
    );
  }

  /// 更新 status。completed/failed 时写 finished_at；failed 时写 failed_message。
  Future<void> updateProcessingTaskStatus(
    String id,
    TaskStatus status, {
    String? failedMessage,
  }) async {
    final companion = ProcessingTasksCompanion(
      status: Value(status.value),
      finishedAt: Value(
        (status == TaskStatus.completed || status == TaskStatus.failed)
            ? DateTime.now().millisecondsSinceEpoch
            : null,
      ),
      failedMessage: Value(failedMessage),
    );
    await (_db.update(_db.processingTasks)..where((t) => t.id.equals(id)))
        .write(companion);
  }

  /// 更新 stage（FGS 续跑进度）。
  Future<void> updateProcessingTaskStage(String id, String stage) async {
    await (_db.update(_db.processingTasks)..where((t) => t.id.equals(id)))
        .write(ProcessingTasksCompanion(stage: Value(stage)));
  }

  /// 取 ref_id 的最新一行（按 queued_at desc）。方案 A：当前状态 = 最新行。
  Future<ProcessingTask?> getLatestProcessingTask(String refId) async {
    final rows = await (_db.select(_db.processingTasks)
          ..where((t) => t.refId.equals(refId))
          ..orderBy([(t) => OrderingTerm.desc(t.queuedAt)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : _rowToModel(rows.first);
  }

  /// 取所有活跃任务（queued + running），按 queued_at 升序。FGS onStart 消费。
  Future<List<ProcessingTask>> getPendingProcessingTasks() async {
    final rows = await (_db.select(_db.processingTasks)
          ..where((t) =>
              t.status.equals('queued') | t.status.equals('running'))
          ..orderBy([(t) => OrderingTerm.asc(t.queuedAt)]))
        .get();
    return rows.map(_rowToModel).toList();
  }
```

> `insertProcessingTask`（`_db.insertProcessingTask`）需在 `app_database.dart` 加一个透传方法（drift 不自动生成 `into(processingTasks).insert` 的便捷方法）。在 `app_database.dart` 的 `// --- DailySummaries ---` 之前加 `// --- ProcessingTasks ---` 区块的数据库层方法：

```dart
  // --- ProcessingTasks ---

  Future<void> insertProcessingTask(ProcessingTasksCompanion task) {
    return into(processingTasks).insert(task);
  }
```

（其余 `update`/`select` 直接在 storage 用 `_db.update(_db.processingTasks)` / `_db.select(_db.processingTasks)`，不需要 db 层方法。）

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/processing_task_storage_test.dart`
Expected: 6 tests PASS。

- [ ] **Step 5: format + analyze + Commit**

```bash
dart format lib/services/diary_storage_service.dart lib/services/database/app_database.dart test/processing_task_storage_test.dart
flutter analyze
git add lib/services/diary_storage_service.dart lib/services/database/app_database.dart test/processing_task_storage_test.dart
git commit -m "$(cat <<'EOF'
feat: DiaryStorageService 加 processing_tasks 表 CRUD

insert/updateStatus/updateStage/getLatest/getPending + 行→model 转换。
单测覆盖（内存 drift DB）。不接入运行时。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `ProcessingTaskStore`（内存 + 查询 + enqueue + 通知）

**Files:**
- Create: `lib/services/processing_task_store.dart`
- Test: `test/processing_task_store_test.dart`（新建）

> 本 task 的 store 是 Plan A 版本：内存活跃集合 + 查询 + enqueue（写 DB+内存+通知）+ 启动加载。**不接 FGS 消息、不调 controller.start**（Plan B 加）。enqueue 只写 DB + 内存 + 通知。

- [ ] **Step 1: 写 store 失败测试**

新建 `test/processing_task_store_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/processing_task.dart';
import 'package:voice_diary/services/database/app_database.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/processing_task_store.dart';

void main() {
  late AppDatabase db;
  late DiaryStorageService storage;
  late ProcessingTaskStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = DiaryStorageService.forTesting(db);
    store = ProcessingTaskStore(storage: storage);
  });
  tearDown(() async {
    await db.close();
  });

  group('enqueueTask', () {
    test('入队后内存有该 ref，DB 有该行，ValueNotifier 通知', () async {
      var notifyCount = 0;
      store.activeRefIds.addListener(() => notifyCount++);

      await store.enqueueTask(
        taskType: TaskType.diary,
        refId: 'e1',
        stage: 'asr',
        meta: {'asrTaskId': 'x'},
      );

      expect(store.isProcessing('e1'), isTrue);
      expect(store.activeCount, 1);
      expect(store.activeRefIds.value, contains('e1'));
      expect(notifyCount, greaterThan(0)); // 通知触发了

      // DB 也有
      final dbTask = await storage.getLatestProcessingTask('e1');
      expect(dbTask, isNotNull);
      expect(dbTask!.status, TaskStatus.queued);
      expect(dbTask.meta['asrTaskId'], 'x');
    });

    test('同一 ref 再次入队 → 内存更新为最新行（方案 A：新建行）', () async {
      await store.enqueueTask(taskType: TaskType.diary, refId: 'e1', stage: 'asr');
      await store.enqueueTask(taskType: TaskType.diary, refId: 'e1', stage: 'llm');

      expect(store.activeCount, 1); // 同 ref，内存里还是一个
      final task = store.getTask('e1');
      expect(task!.stage, 'llm'); // 最新行的 stage
    });
  });

  group('启动加载', () {
    test('loadFromDb 把 DB active task 填进内存', () async {
      // 直接往 DB 插一个 active task（绕过 store）
      await storage.insertProcessingTask(ProcessingTask(
        id: 't1',
        taskType: TaskType.diary,
        refId: 'e1',
        status: TaskStatus.queued,
        stage: 'asr',
        queuedAt: DateTime(2026, 6, 21),
      ));
      // completed 的不入内存
      await storage.insertProcessingTask(ProcessingTask(
        id: 't2',
        taskType: TaskType.diary,
        refId: 'e2',
        status: TaskStatus.completed,
        queuedAt: DateTime(2026, 6, 21),
      ));

      await store.loadFromDb();

      expect(store.isProcessing('e1'), isTrue); // queued 入内存
      expect(store.isProcessing('e2'), isFalse); // completed 不入
      expect(store.activeCount, 1);
    });
  });

  group('查询', () {
    test('getTask 返回内存里的 active task', () async {
      await store.enqueueTask(taskType: TaskType.dailySummary, refId: '2026-06-21');
      final task = store.getTask('2026-06-21');
      expect(task, isNotNull);
      expect(task!.taskType, TaskType.dailySummary);
    });

    test('getTask 未入队返回 null', () {
      expect(store.getTask('nope'), isNull);
    });
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/processing_task_store_test.dart`
Expected: FAIL — `ProcessingTaskStore` 未定义。

- [ ] **Step 3: 实现 store**

新建 `lib/services/processing_task_store.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/processing_task.dart';
import 'diary_storage_service.dart';

/// Processing task 状态中心（main isolate）。
///
/// 维护内存活跃集合（queued/running 的 task，按 ref_id 索引），是 DB 的镜像：
/// - 启动时 loadFromDb 从 DB 加载（校准，防消息丢导致 stale）
/// - enqueueTask 写 DB + 内存 + 通知 UI
/// - （Plan B 加：FGS 消息实时刷新内存）
///
/// UI 通过 [activeRefIds]（ValueNotifier）订阅刷新，通过 [getTask]/[isProcessing] 查询。
///
/// 注意：本类是 Plan A 版本——只管内存 + 查询 + enqueue，不接 FGS 消息、不调
/// ProcessingFgsController.start（Plan B 接入）。
class ProcessingTaskStore {
  final DiaryStorageService _storage;
  final _uuid = const Uuid();

  /// ref_id → 最新 active task（内存镜像）。
  final Map<String, ProcessingTask> _activeByRefId = {};

  /// 活跃 ref_id 集合（供 UI 订阅 rebuild）。
  final ValueNotifier<Set<String>> activeRefIds =
      ValueNotifier<Set<String>>(const {});

  ProcessingTaskStore({required DiaryStorageService storage})
      : _storage = storage;

  /// 启动加载：从 DB 读 active（queued/running）填内存。app 启动时调。
  Future<void> loadFromDb() async {
    final pending = await _storage.getPendingProcessingTasks();
    _activeByRefId.clear();
    for (final t in pending) {
      // 同 ref 多行时，getPending 按 queued_at 升序，后面覆盖前面 → 留最新
      _activeByRefId[t.refId] = t;
    }
    _notify();
  }

  /// 入队：写 task 表(queued) + 加内存 + 通知。
  /// 返回新建的 task（调用方可拿 id）。
  ///
  /// 注意：Plan A 版本不触发 FGS（Plan B 加 controller.start）。
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
    _activeByRefId[refId] = task; // 覆盖旧的（方案 A：新行是最新）
    _notify();
    return task;
  }

  /// 取某 ref 的活跃 task（内存）。未入队/已完成返回 null。
  ProcessingTask? getTask(String refId) => _activeByRefId[refId];

  /// 某 ref 是否在处理（内存有 active task）。
  bool isProcessing(String refId) => _activeByRefId.containsKey(refId);

  /// 活跃任务数（badge 用）。
  int get activeCount => _activeByRefId.length;

  void _notify() {
    activeRefIds.value = Set<String>.from(_activeByRefId.keys);
  }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/processing_task_store_test.dart`
Expected: 6 tests PASS。

- [ ] **Step 5: format + analyze + Commit**

```bash
dart format lib/services/processing_task_store.dart test/processing_task_store_test.dart
flutter analyze
git add lib/services/processing_task_store.dart test/processing_task_store_test.dart
git commit -m "$(cat <<'EOF'
feat: 新增 ProcessingTaskStore（task 状态中心，Plan A 版本）

内存活跃集合（ref_id 索引）+ ValueNotifier 通知 UI + enqueue（写 DB+内存）
+ 启动加载（从 DB 校准）。单测覆盖。
Plan A 不接 FGS 消息、不调 controller.start（Plan B 接入）。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 全量验证

- [ ] **Step 1: 全量 analyze**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 2: 全量 test**

Run: `flutter test`
Expected: 所有测试 PASS（含新增的 processing_task_storage_test + processing_task_store_test + 既有测试）。

- [ ] **Step 3: 验证旧功能未受影响**

确认：
- `processing_tasks` 表已建（codegen 通过）
- 新 model/store/storage 方法存在且单测通过
- FGS/UI/业务表 status **完全未动**（grep 确认 `DiaryEntries.status` 仍被读写、`getPendingEntries` 未改）

---

## Self-Review

（执行前由计划作者完成）

**1. Spec coverage（Plan A 范围内）**：
- processing_tasks 表 + meta JSON：Task 1 ✓
- ProcessingTask model + enum：Task 2 ✓
- storage CRUD：Task 3 ✓
- ProcessingTaskStore（内存/查询/enqueue/通知/加载）：Task 4 ✓
- Plan A 明确**不覆盖**（留 Plan B）：FGS 写 task 表、UI 订阅、入队接 controller、migration 数据搬迁、业务表 status 废弃、controller 收窄——这些是 Plan B。

**2. Placeholder scan**：无 TBD/TODO/含糊。测试代码完整可运行。

**3. Type consistency**：
- `ProcessingTask` model 字段（id/taskType/refId/status/stage/failedMessage/meta/queuedAt/startedAt/finishedAt）跨 task 一致
- `TaskType`/`TaskStatus` enum 的 `value`/`fromString` 一致
- storage 方法名（insertProcessingTask/updateProcessingTaskStatus/updateProcessingTaskStage/getLatestProcessingTask/getPendingProcessingTasks）跨 task 一致
- store 方法名（enqueueTask/getTask/isProcessing/activeCount/loadFromDb/activeRefIds）跨 task 一致
- `_rowToModel` 字段映射与 model 一致

---

## Execution Handoff

Plan A 完成（基础设施就绪 + 单测）后，接着写 **Plan B（切换 + 清理）**。Plan B 才是真正改变运行时行为（FGS 写 task 表 + UI 订阅 store + 入队接 controller + migration 数据搬迁 + 废弃业务表 status）。

# 重新分析已完成的日记 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在日记详情页（仅 `completed` 状态）删除按钮旁加「重新分析」按钮，点击后全量重跑 ASR→LLM→tag 覆盖现有结果，走 FGS 后台处理。

**Architecture:** 方案 A——重置 DB 状态字段（`status→processing`、`processingStage→asr`、`asrTaskId→null`）让现有 `ProcessingTaskHandler` 自然全量重跑，handler 零改动。抽公共 `ProcessingFgsController` + 全局 `FgsRuntime` 模式追踪处理并发（不中断录音）。详见 `docs/superpowers/specs/2026-06-14-reanalyze-diary-design.md`。

**Tech Stack:** Flutter / drift（SQLite ORM）/ flutter_foreground_task（FGS）/ flutter_test。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/services/database/app_database.dart` | 改 | 加 `forTesting` 构造，支持注入内存 DB |
| `lib/services/diary_storage_service.dart` | 改 | 加 `forTesting` 构造 + `resetEntryForReanalysis` |
| `lib/services/fgs_runtime.dart` | 新建 | main isolate 全局 FGS 模式追踪（none/recording/processing） |
| `lib/services/processing_fgs_controller.dart` | 新建 | 公共 processing FGS 启动入口（含并发判断） |
| `lib/pages/recording_page.dart` | 改 | `_startProcessingFgs` 改调 controller + 各 FGS 生命周期点更新 `FgsRuntime` |
| `lib/pages/diary_detail_page.dart` | 改 | AppBar 加按钮 + `_reanalyze` 方法 |
| `test/diary_storage_service_test.dart` | 新建 | `resetEntryForReanalysis` 单测 |
| `test/fgs_runtime_test.dart` | 新建 | `FgsRuntime` 单测 |

**不改**：`lib/services/recording_processor.dart`（`ProcessingTaskHandler` 零改动）、失败重试入口（`_retry` + 失败横幅）。

---

## Task 1: `resetEntryForReanalysis` + 测试注入基础设施

**Files:**
- Modify: `lib/services/database/app_database.dart`（factory 之后加 `forTesting` 构造）
- Modify: `lib/services/diary_storage_service.dart`（加 `forTesting` 构造 + `resetEntryForReanalysis` 方法）
- Test: `test/diary_storage_service_test.dart`（新建）

- [ ] **Step 1: `AppDatabase` 加 `forTesting` 构造**

在 `lib/services/database/app_database.dart` 顶部 import 区加：

```dart
import 'package:meta/meta.dart';
```

在 `factory AppDatabase()` 之后（约第 27 行后）加命名构造：

```dart
  /// 测试用：注入内存执行器，绕过单例和文件连接。
  /// 生产代码请用 `AppDatabase()` 工厂。
  @visibleForTesting
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);
```

> `QueryExecutor` 由 `package:drift/drift.dart` 导出（已 import）。

- [ ] **Step 2: `DiaryStorageService` 加 `forTesting` 构造**

在 `lib/services/diary_storage_service.dart` 顶部 import 区加：

```dart
import 'package:meta/meta.dart';
```

在 `DiaryStorageService() : _db = AppDatabase();`（第 17 行）之后加：

```dart
  /// 测试用：注入已构造的 AppDatabase（通常是内存 DB）。
  @visibleForTesting
  DiaryStorageService.forTesting(this._db);
```

- [ ] **Step 3: 写 `resetEntryForReanalysis` 的失败测试**

新建 `test/diary_storage_service_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/processing_stage.dart';
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

  Future<void> _createEntry({
    required String id,
    String? tosKey,
    String? asrTaskId,
  }) async {
    await service.createEntry(DiaryEntry(
      id: id,
      title: '原标题',
      folderPath: '/tmp/$id',
      durationSeconds: 60,
      createdAt: DateTime(2026, 6, 14),
      tosKey: tosKey,
      audioFormat: 'wav',
      status: EntryStatus.completed,
      processingStage: ProcessingStage.completed,
      asrTaskId: asrTaskId,
    ));
  }

  test('resetEntryForReanalysis 有 tosKey 时重置为 asr 阶段', () async {
    await _createEntry(id: 'e1', tosKey: 'tos-key-1', asrTaskId: 'old-task');

    await service.resetEntryForReanalysis('e1');

    final reset = await service.getEntryById('e1');
    expect(reset.status, EntryStatus.processing);
    expect(reset.processingStage, ProcessingStage.asr);
    expect(reset.asrTaskId, isNull);
    expect(reset.tosKey, 'tos-key-1'); // 保留，不重新上传
  });

  test('resetEntryForReanalysis 无 tosKey 时落到 uploading 阶段', () async {
    await _createEntry(id: 'e2'); // tosKey=null

    await service.resetEntryForReanalysis('e2');

    final reset = await service.getEntryById('e2');
    expect(reset.status, EntryStatus.processing);
    expect(reset.processingStage, ProcessingStage.uploading);
    expect(reset.asrTaskId, isNull);
  });

  test('resetEntryForReanalysis 不改 title 等非处理字段', () async {
    await _createEntry(id: 'e3', tosKey: 'tos-key-3');

    await service.resetEntryForReanalysis('e3');

    final reset = await service.getEntryById('e3');
    expect(reset.title, '原标题');
    expect(reset.folderPath, '/tmp/e3');
    expect(reset.durationSeconds, 60);
  });
}
```

- [ ] **Step 4: 跑测试，确认失败**

Run: `flutter test test/diary_storage_service_test.dart`
Expected: FAIL — `resetEntryForReanalysis` 方法未定义。

> 若报 `sqlite3` 找不到（host 缺库），macOS 自带 libsqlite3，通常可跑。若确实失败，先确认 `sqlite3_flutter_libs` 在 dependencies（drift 依赖项）。

- [ ] **Step 5: 实现 `resetEntryForReanalysis`**

在 `lib/services/diary_storage_service.dart` 的 `getFullTagsForDiary` 附近（约第 351 行后）加：

```dart
  /// 重置日记条目到「可被全量重新分析」的状态：
  /// - status → processing（让 ProcessingTaskHandler.getPendingEntries 拾取）
  /// - processingStage → asr（tosKey 已存在则跳过重新上传；无 tosKey 落到 uploading）
  /// - asrTaskId → null（强制 _doAsr 重新 submit，而非 poll 旧 task 拿旧结果）
  ///
  /// 不动 title / folderPath / transcript.json / llm_result.json 等数据。
  /// 失败时抛异常（调用方负责 catch + 提示）。
  Future<void> resetEntryForReanalysis(String id) async {
    final entry = await _db.getEntryById(id);
    final stage = entry.tosKey != null
        ? ProcessingStage.asr
        : ProcessingStage.uploading;
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id))).write(
      DiaryEntriesCompanion(
        status: const Value('processing'),
        processingStage: Value(stage.value),
        asrTaskId: const Value(null),
      ),
    );
  }
```

- [ ] **Step 6: 跑测试，确认通过**

Run: `flutter test test/diary_storage_service_test.dart`
Expected: 3 tests PASS。

- [ ] **Step 7: format + analyze**

Run:
```bash
dart format lib/services/database/app_database.dart lib/services/diary_storage_service.dart test/diary_storage_service_test.dart
flutter analyze
```
Expected: No issues found.

- [ ] **Step 8: Commit**

```bash
git add lib/services/database/app_database.dart lib/services/diary_storage_service.dart test/diary_storage_service_test.dart
git commit -m "$(cat <<'EOF'
feat: DiaryStorageService 新增 resetEntryForReanalysis 重置条目到全量重分析状态

为「重新分析」功能准备：把 completed 条目重置为 processing[asr] 且清空
asrTaskId，让现有 ProcessingTaskHandler 全量重跑 ASR/LLM/tag。
附带 AppDatabase.forTesting / DiaryStorageService.forTesting 注入构造
（用内存 drift DB 支持单测）。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `FgsRuntime` 全局模式追踪

**Files:**
- Create: `lib/services/fgs_runtime.dart`
- Test: `test/fgs_runtime_test.dart`（新建）

- [ ] **Step 1: 写失败测试**

新建 `test/fgs_runtime_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/fgs_runtime.dart';

void main() {
  tearDown(FgsRuntime.setNone);

  test('默认 mode 为 none', () {
    FgsRuntime.setNone();
    expect(FgsRuntime.mode, FgsMode.none);
  });

  test('setRecording / setProcessing 切换 mode', () {
    FgsRuntime.setRecording();
    expect(FgsRuntime.mode, FgsMode.recording);
    FgsRuntime.setProcessing();
    expect(FgsRuntime.mode, FgsMode.processing);
  });

  test('setNone 回到 none', () {
    FgsRuntime.setProcessing();
    FgsRuntime.setNone();
    expect(FgsRuntime.mode, FgsMode.none);
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/fgs_runtime_test.dart`
Expected: FAIL — `fgs_runtime.dart` 不存在。

- [ ] **Step 3: 实现 `FgsRuntime`**

新建 `lib/services/fgs_runtime.dart`：

```dart
/// main isolate 感知的 FGS 当前模式，用于「重新分析」等操作的并发判断
///（避免中断正在进行的录音）。
///
/// 注意：仅服务 main isolate；FGS isolate 有自己独立的 static，不共享
///（这正是所需的——drift 连接和 FGS callback 都不能跨 isolate）。
enum FgsMode { none, recording, processing }

class FgsRuntime {
  FgsRuntime._();

  static FgsMode mode = FgsMode.none;

  static void setRecording() => mode = FgsMode.recording;
  static void setProcessing() => mode = FgsMode.processing;
  static void setNone() => mode = FgsMode.none;
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/fgs_runtime_test.dart`
Expected: 3 tests PASS。

- [ ] **Step 5: format + analyze**

Run:
```bash
dart format lib/services/fgs_runtime.dart test/fgs_runtime_test.dart
flutter analyze
```
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/services/fgs_runtime.dart test/fgs_runtime_test.dart
git commit -m "$(cat <<'EOF'
feat: 新增 FgsRuntime 全局 FGS 模式追踪

main isolate 感知当前 FGS 模式（none/recording/processing），
供「重新分析」并发判断使用（录音中不启动 processing FGS）。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `ProcessingFgsController` + 重构 `RecordingPage`

**Files:**
- Create: `lib/services/processing_fgs_controller.dart`
- Modify: `lib/pages/recording_page.dart`（import + `_doStartRecording` + `_startProcessingFgs` + `_onTaskData` 四处）

> 此任务为重构 + 平台交互代码，无单测（FGS 启动依赖 Android 平台）。靠 `flutter analyze` + Task 5 的手动验证保证。

- [ ] **Step 1: 新建 `ProcessingFgsController`**

新建 `lib/services/processing_fgs_controller.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'fgs_runtime.dart';
import 'recording_processor.dart' show processingCallback;

/// 启动 processing FGS 的公共入口。
///
/// 并发规则：若当前录音 FGS 在跑（`FgsRuntime.mode == recording`），返回 false
/// 且不启动——调用方应仅入队（resetEntryForReanalysis）+ 提示，录音结束后
/// `RecordingPage._scheduleProcessingFgs` 会拾取。
/// 否则 stopService + 启动 processing，成功返回 true。
class ProcessingFgsController {
  ProcessingFgsController._();

  /// 返回 true 表示已成功启动 processing FGS；
  /// false 表示未启动（录音中，或启动失败）。
  static Future<bool> start() async {
    if (FgsRuntime.mode == FgsMode.recording) {
      debugPrint('[ProcessingFgsController] 录音中，跳过启动 FGS');
      return false;
    }

    // 用 try/catch 兜底：startService 可能抛平台异常，统一返回 false，
    // 保证调用方（RecordingPage / DiaryDetailPage）无需再包 try/catch。
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(milliseconds: 500));

      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '正在处理',
        notificationText: '语音日记 - 处理中...',
        callback: processingCallback,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[ProcessingFgsController] 启动失败: ${result.error}');
        return false;
      }

      FgsRuntime.setProcessing();
      return true;
    } catch (e) {
      debugPrint('[ProcessingFgsController] 启动异常: $e');
      return false;
    }
  }
}
```

- [ ] **Step 2: `RecordingPage` 加 import**

在 `lib/pages/recording_page.dart` 顶部 import 区加：

```dart
import '../services/fgs_runtime.dart';
import '../services/processing_fgs_controller.dart';
```

- [ ] **Step 3: `_doStartRecording` 成功后标记 recording**

在 `_doStartRecording`（约第 225-226 行）的：

```dart
      setState(() => _state = RecordingState.recording);
      WakelockPlus.enable();
```

之间插入一行：

```dart
      setState(() => _state = RecordingState.recording);
      FgsRuntime.setRecording();
      WakelockPlus.enable();
```

- [ ] **Step 4: `_startProcessingFgs` 改为调 controller**

把 `_startProcessingFgs`（约第 278-304 行）整段替换为：

```dart
  Future<void> _startProcessingFgs() async {
    _isProcessingFgsRunning = true;
    final started = await ProcessingFgsController.start();
    if (!started) {
      debugPrint('[RecordingPage] Processing FGS 未启动');
      _isProcessingFgsRunning = false;
    }
    _refreshProcessingCount();
  }
```

- [ ] **Step 5: `_onTaskData` 各结束信号处重置 mode 为 none**

在 `_onTaskData`（约第 65-120 行）的三处 case 补 `FgsRuntime.setNone()`：

`'recordingComplete'` case（约第 98-100 行）改为：

```dart
      case 'recordingComplete':
        // 录音完成，延迟启动 Processing FGS
        FgsRuntime.setNone();
        _scheduleProcessingFgs();
```

`'processingDone'` case（约第 101-104 行）改为：

```dart
      case 'processingDone':
        // Processing FGS 结束（无论是否有条目被处理）
        FgsRuntime.setNone();
        _isProcessingFgsRunning = false;
        _refreshProcessingCount();
        if (_state == RecordingState.processing) {
          _doStartRecording();
        }
```

`'completed'` / `'failed'` case（约第 108-116 行）改为：

```dart
      case 'completed':
      case 'failed':
        // 处理完成或失败时刷新 Badge 数量
        FgsRuntime.setNone();
        _isProcessingFgsRunning = false;
        _refreshProcessingCount();
        if (_state == RecordingState.processing) {
          // 用户在等待 Processing FGS 停止后启动录音
          _doStartRecording();
        }
```

- [ ] **Step 6: format + analyze**

Run:
```bash
dart format lib/services/processing_fgs_controller.dart lib/pages/recording_page.dart
flutter analyze
```
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/services/processing_fgs_controller.dart lib/pages/recording_page.dart
git commit -m "$(cat <<'EOF'
refactor: 抽 ProcessingFgsController 公共启动入口，RecordingPage 接入 FgsRuntime

- 新建 ProcessingFgsController：封装 processing FGS 启动（initCommunicationPort
  + stopService + startService），录音中时拒绝启动
- RecordingPage._startProcessingFgs 改为调 controller
- RecordingPage 在录音启动 / recordingComplete / processingDone / completed /
  failed 各点更新 FgsRuntime.mode

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `DiaryDetailPage` 重新分析按钮与触发

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`（import + AppBar actions + `_reanalyze` 方法）

> 详情页依赖 AudioPlayer / Storage / FGS 等多个 service，widget test 搭建成本高、价值低（按钮可见性是简单条件判断）。核心数据逻辑（`resetEntryForReanalysis`）已在 Task 1 覆盖单测，UI 改动靠 Task 5 手动验证。

- [ ] **Step 1: 加 import**

在 `lib/pages/diary_detail_page.dart` 顶部 import 区加：

```dart
import '../services/processing_fgs_controller.dart';
```

- [ ] **Step 2: AppBar actions 加「重新分析」按钮**

把 `build` 方法里 AppBar 的 `actions`（约第 465-469 行）：

```dart
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteDiary),
        ],
```

替换为：

```dart
        actions: [
          if (_entry.status == EntryStatus.completed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新分析',
              onPressed: _reanalyze,
            ),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteDiary),
        ],
```

- [ ] **Step 3: 加 `_reanalyze` 方法**

在 `_deleteDiary` 方法（约第 287 行）之前加：

```dart
  Future<void> _reanalyze() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新分析'),
        content: const Text(
            '将重新识别语音并重新生成总结，当前的识别结果和总结会被覆盖。标签会保留，并追加新匹配的标签。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重新分析')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _storageService.resetEntryForReanalysis(_entry.id);
      if (!mounted) return;
      // 本地乐观更新：立即切到处理中横幅（_buildStatusBanner 按 processingStage 显示阶段文本）
      setState(() {
        _entry = _entry.copyWith(
          status: EntryStatus.processing,
          processingStage: ProcessingStage.asr,
        );
        _isActivelyProcessing = true;
      });

      final started = await ProcessingFgsController.start();
      if (!started && mounted) {
        // 录音中或其他原因未启动：entry 已入队（status=processing），稍后自动处理
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入处理队列，录音结束后将自动处理')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新分析启动失败: $e')),
        );
      }
    }
  }
```

- [ ] **Step 4: format + analyze**

Run:
```bash
dart format lib/pages/diary_detail_page.dart
flutter analyze
```
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "$(cat <<'EOF'
feat: 日记详情页新增「重新分析」按钮（仅 completed 状态）

删除按钮旁加 refresh 图标按钮，仅 status==completed 时显示。
点击 → 确认弹窗 → resetEntryForReanalysis + 启动 processing FGS +
本地乐观更新（立即显示处理中横幅）。录音中时 toast 提示已入队。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 全量验证与收尾

- [ ] **Step 1: 全量 analyze**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 2: 全量 test**

Run: `flutter test`
Expected: 所有测试 PASS（含新增的 `diary_storage_service_test` 和 `fgs_runtime_test`）。

- [ ] **Step 3: 手动验证清单**

构建到设备/模拟器（`./scripts/run_dev.sh` 或 `flutter run`），逐项验证：

- [ ] 打开一篇**已完成**的日记详情页 → 删除按钮**左侧**出现 refresh 图标按钮，长按显示「重新分析」tooltip
- [ ] 打开一篇**处理中**或**失败**的日记 → 不显示该按钮（失败横幅的「重新处理」入口仍在）
- [ ] 点重新分析 → 确认弹窗显示覆盖范围文案 → 确认后页面立即显示「语音识别中...」横幅 → 流转到「AI 总结」「自动归类」→ 完成后标题/总结更新为新结果
- [ ] （断网模拟）重新分析失败 → 落到失败横幅 + 「重新处理」按钮可用，点后能从失败步骤续跑
- [ ] 录音中（FGS 后台跑）进详情页点重新分析 → toast「已加入处理队列」→ 录音结束后该日记自动被处理
- [ ] **回归**：正常录音 → 录音后处理流程不受影响（录音后日记正常完成）

- [ ] **Step 4: 若手动验证中发现 format 偏差，补一次提交**

若 `flutter analyze` 或手动改动产生新 diff：

```bash
dart format .
flutter analyze
git add -A
git commit -m "style: 重新分析功能收尾格式化

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

否则跳过本步。

---

## Self-Review

（执行前由计划作者完成，见下）

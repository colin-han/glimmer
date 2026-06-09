# 双 FGS 架构重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将单一 RecordingTaskHandler（录音+处理）拆分为 Recording FGS + Processing FGS 双 FGS 架构，支持基于 processingStage 的阶段恢复和中断续处理。

**Architecture:** RecordingTaskHandler 精简为只做录音，录音结束后停止。ProcessingTaskHandler 从 DB 查询待处理任务，按 processingStage 恢复执行。DB 即队列，无需内存队列。主 isolate 负责两个 FGS 的启动/停止协调。

**Tech Stack:** Flutter + flutter_foreground_task + drift (SQLite) + dio (HTTP)

**Spec:** `docs/superpowers/specs/2026-06-09-processing-stages-design.md`

---

## Spec 与实际代码偏差说明

Spec 中说 ASR 是"异步（提交识别任务 → 轮询状态 → 获取结果）"，但实际代码中 `AsrService` 使用的是火山引擎 **Flash ASR**（`/api/v3/auc/bigmodel/recognize/flash`），这是一个**同步 API**——单次 POST 直接返回识别结果，没有 taskId，没有轮询。

**影响**：
- **不需要 `asrTaskId` 字段**——当前 ASR 没有 taskId 概念
- **ASR 阶段的恢复逻辑更简单**：不需要区分"有 taskId 直接查询"和"无 taskId 重新提交"，统一就是"重新调 transcribeFromUrl"
- 如果未来切换到异步 ASR API（如长音频识别），再按 spec 添加 asrTaskId 字段即可

**决策**：本次实施跳过 `asrTaskId` 字段，ASR 阶段统一为"重新识别"。

---

## 文件结构

### 需要创建的文件

| 文件 | 职责 |
|------|------|
| `lib/models/processing_stage.dart` | ProcessingStage 枚举定义 |

### 需要修改的文件

| 文件 | 改动 |
|------|------|
| `lib/services/database/tables.dart` | 新增 processingStage 字段 |
| `lib/services/database/app_database.dart` | 新增 migration (v5→v6)，新增 getPendingEntries() |
| `lib/services/database/app_database.g.dart` | 自动生成，build_runner 重新生成 |
| `lib/models/diary_entry.dart` | DiaryEntry 新增 processingStage 字段 |
| `lib/services/diary_storage_service.dart` | 新增 processingStage 相关方法，parse 逻辑更新 |
| `lib/services/recording_task_handler.dart` | 精简为只做录音，删除 ASR/LLM/TOS 逻辑；新增 RecordingCompleteHandler；删除 RetryTaskHandler |
| `lib/services/recording_processor.dart` | 重写为 ProcessingTaskHandler + processingCallback，基于 DB 队列和 processingStage 恢复 |
| `lib/pages/recording_page.dart` | 双 FGS 协调逻辑（录音结束后启动 Processing FGS，录音开始前停止 Processing FGS） |
| `lib/pages/diary_list_page.dart` | 重试按钮改为启动 Processing FGS |

### 不需要改动的文件

| 文件 | 原因 |
|------|------|
| `lib/services/asr_service.dart` | 同步 API，不改动 |
| `lib/services/llm_service.dart` | 同步 API，不改动 |
| `lib/services/tos_upload_service.dart` | 同步 API，不改动 |
| `android/app/src/main/AndroidManifest.xml` | 已有 microphone + dataSync 声明 |

---

## Task 1: ProcessingStage 枚举和 DB Schema

**Files:**
- Create: `lib/models/processing_stage.dart`
- Modify: `lib/services/database/tables.dart`
- Modify: `lib/services/database/app_database.dart`
- Modify: `lib/models/diary_entry.dart`

- [ ] **Step 1: 创建 ProcessingStage 枚举**

创建 `lib/models/processing_stage.dart`:

```dart
/// 日记条目的处理阶段，表示"当前/下一个要执行的处理阶段"。
///
/// 含义是：当恢复处理时，应该从这个阶段开始执行。
/// 录制阶段不创建 DB 条目，因此没有 recording 值。
enum ProcessingStage {
  uploading('uploading'),
  asr('asr'),
  llm('llm'),
  tagging('tagging'),
  completed('completed');

  const ProcessingStage(this.value);
  final String value;

  static ProcessingStage fromString(String? value) {
    return ProcessingStage.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ProcessingStage.uploading,
    );
  }
}
```

- [ ] **Step 2: 更新 tables.dart，新增 processingStage 字段**

在 `lib/services/database/tables.dart` 的 `DiaryEntries` 类中，在 `status` 字段后添加：

```dart
TextColumn get processingStage => text().withDefault(const Constant('uploading'))();
```

- [ ] **Step 3: 更新 app_database.dart，新增 migration v5→v6**

在 `lib/services/database/app_database.dart` 中：

1. `schemaVersion` 从 5 改为 6
2. 在 `onUpgrade` 中添加：

```dart
if (from < 6) {
  try { await m.addColumn(diaryEntries, diaryEntries.processingStage); } catch (_) {}
}
```

3. 新增查询方法 `getPendingEntries`:

```dart
Future<List<DiaryEntry>> getPendingEntries() {
  return (select(diaryEntries)
        ..where((t) => t.status.equals('processing'))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .get();
}
```

- [ ] **Step 4: 更新 DiaryEntry 模型**

在 `lib/models/diary_entry.dart` 中：

1. 添加 import: `import 'processing_stage.dart';`
2. 在 `DiaryEntry` 类中添加字段: `final ProcessingStage processingStage;`
3. 构造函数中添加: `this.processingStage = ProcessingStage.uploading,`
4. 在 `getAllEntries()` 映射和 `getEntryById()` 映射中解析 processingStage（在 diary_storage_service.dart 中处理）

- [ ] **Step 5: 重新生成 drift 代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 成功生成 app_database.g.dart

- [ ] **Step 6: 更新 diary_storage_service.dart 中的解析逻辑**

在 `lib/services/diary_storage_service.dart` 的 `getAllEntries()` 和 `getEntryById()` 方法中，给 DiaryEntry 构造添加 processingStage 参数：

```dart
processingStage: ProcessingStage.fromString(r.processingStage),
```

同时更新 `createEntry` 方法，在 `DiaryEntriesCompanion.insert` 中添加：

```dart
processingStage: Value(entry.processingStage.value),
```

以及 `updateEntry` 方法中添加对应字段。

- [ ] **Step 7: 新增 storage 方法**

在 `lib/services/diary_storage_service.dart` 中添加：

```dart
/// 查询所有待处理的条目（status=processing），按创建时间升序
Future<List<DiaryEntry>> getPendingEntries() => _db.getPendingEntries();

/// 更新处理阶段
Future<void> updateProcessingStage(String id, ProcessingStage stage) async {
  await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id)))
      .write(DiaryEntriesCompanion(
    processingStage: Value(stage.value),
  ));
}

/// 更新处理阶段和 tosKey
Future<void> updateTosKeyAndStage(String id, String tosKey, ProcessingStage stage) async {
  await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id)))
      .write(DiaryEntriesCompanion(
    tosKey: Value(tosKey),
    processingStage: Value(stage.value),
  ));
}
```

- [ ] **Step 8: 运行 analyze 确认无错误**

Run: `flutter analyze`
Expected: 无新增 error/warning

- [ ] **Step 9: 提交**

```bash
git add -A
git commit -m "refactor: 新增 ProcessingStage 枚举和数据库字段"
```

---

## Task 2: 精简 RecordingTaskHandler

将 `RecordingTaskHandler` 从"录音 + 处理"精简为"只做录音"。录音结束后保存音频文件、INSERT DB 条目、通知主 isolate、停止 FGS。删除所有 ASR/LLM/TOS 相关逻辑。

**Files:**
- Modify: `lib/services/recording_task_handler.dart`

- [ ] **Step 1: 重写 RecordingTaskHandler**

在 `lib/services/recording_task_handler.dart` 中：

1. 删除不再需要的 import 和服务实例：`AsrService`、`TosUploadService`、`LlmService`、`TtsService`
2. 保留的服务：`AudioRecorderService`、`RealtimeAsrService`、`DiaryStorageService`、`LocationService`、`WeatherService`
3. 重写 `_requestStop` 方法——不再调用 `_processRecording`，而是：
   - 停止录音器，获取 audioFilePath 和 duration
   - INSERT DB 条目（title="正在处理中..."，status=processing，processingStage=uploading，weather 信息）
   - 发送完成消息给主 isolate：`{'type': 'recordingComplete', 'entryId': folderId}`
   - 调用 `stopService()`
4. 删除 `_processRecording` 方法
5. 删除 `_markEntryAsFailed` 方法
6. 删除 `_speakReply` 方法和 `_replyTemplates`
7. 保留 `onStart`、`onReceiveData`、`onDestroy` 中的录音相关逻辑

`_requestStop` 改为：

```dart
void _requestStop() {
  if (_stopRequested) return;
  _stopRequested = true;

  () async {
    try {
      // 停止计时和监听
      _durationTimer?.cancel();
      _durationTimer = null;
      await _amplitudeSub?.cancel();
      _amplitudeSub = null;
      _realtimeAsr?.sendLastFrame();
      _realtimeAsr?.disconnect();
      await _audioStreamSub?.cancel();
      _audioStreamSub = null;
      await _partialResultSub?.cancel();
      _partialResultSub = null;

      // 停止录音
      String? audioFilePath;
      int duration = _recordingSeconds;
      try {
        final result = await _recorderService!.stopRecording();
        audioFilePath = result.filePath;
        duration = result.durationSeconds;
      } catch (e) {
        debugPrint('[TaskHandler] stopRecording 失败: $e');
      }

      // 创建 DB 条目
      await _storageService.createEntry(DiaryEntry(
        id: _folderId!,
        title: '正在处理中...',
        folderPath: _folderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
        audioFormat: 'ogg',
        status: EntryStatus.processing,
        processingStage: ProcessingStage.uploading,
        weatherIcon: _weatherLocation?.icon,
        weatherText: _weatherLocation?.text,
        temperature: _weatherLocation?.temp,
        locationName: _weatherLocation?.locationName,
        locationLat: _location?.lat,
        locationLon: _location?.lon,
      ));

      debugPrint('[TaskHandler] 录音完成，已创建 DB 条目');

      // 通知主 isolate
      _sendToMain({'type': 'recordingComplete', 'entryId': _folderId!});
    } catch (e) {
      debugPrint('[TaskHandler] 停止录音异常: $e');
      _sendToMain({
        'type': 'failed',
        'entryId': _folderId ?? '',
        'step': 0,
        'error': '停止录音失败: $e',
      });
    } finally {
      await _stopService();
    }
  }();
}
```

- [ ] **Step 2: 删除 RetryTaskHandler 和 retryCallback**

删除 `retryCallback` 函数和 `RetryTaskHandler` 类（不再需要，重试统一走 ProcessingTaskHandler）。

- [ ] **Step 3: 更新 _onTaskData 中的消息类型处理**

`recording_page.dart` 的 `_onTaskData` 需要处理新的 `recordingComplete` 消息类型（在 Task 4 中处理）。这里先确保 `completed` 和 `failed` 消息不再从 RecordingTaskHandler 发出。

- [ ] **Step 4: 运行 analyze 确认无错误**

Run: `flutter analyze`
Expected: 可能有 recording_page.dart 中引用 recordingComplete 的编译错误（Task 4 中修复）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor: 精简 RecordingTaskHandler 为只做录音"
```

---

## Task 3: 创建 ProcessingTaskHandler

新建 ProcessingTaskHandler，基于 DB 中的 processingStage 执行阶段恢复。替代原有的 RecordingProcessor 和 RetryTaskHandler。

**Files:**
- Modify: `lib/services/recording_processor.dart`（重写）

- [ ] **Step 1: 重写 recording_processor.dart**

完全重写为 ProcessingTaskHandler。文件重命名不是必须的（保持 import 兼容），但类名和逻辑完全改变。

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import 'asr_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'tos_upload_service.dart';

/// Processing FGS 入口函数
@pragma('vm:entry-point')
void processingCallback() {
  FlutterForegroundTask.setTaskHandler(ProcessingTaskHandler());
}

/// 处理阶段 TaskHandler，运行在 FGS isolate 中。
/// 从 DB 查询所有 status=processing 的条目，按 processingStage 恢复处理。
class ProcessingTaskHandler extends TaskHandler {
  final _tosService = TosUploadService();
  final _asrService = AsrService();
  final _llmService = LlmService();
  final _storageService = DiaryStorageService();

  void _sendToMain(Map<String, dynamic> data) {
    FlutterForegroundTask.sendDataToMain(data);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ProcessingHandler] onStart');

    // 加载 dotenv
    try {
      await dotenv.load(fileName: '.env.local');
    } catch (e) {
      debugPrint('[ProcessingHandler] dotenv.load 失败: $e');
    }

    // 从 DB 查询所有待处理条目
    final entries = await _storageService.getPendingEntries();
    if (entries.isEmpty) {
      debugPrint('[ProcessingHandler] 无待处理任务，停止');
      await _stopService();
      return;
    }

    debugPrint('[ProcessingHandler] 待处理任务: ${entries.length} 个');

    for (final entry in entries) {
      try {
        await _processEntry(entry);
      } catch (e) {
        debugPrint('[ProcessingHandler] 处理异常 (${entry.id}): $e');
        await _markFailed(entry.id, '处理失败');
      }
    }

    debugPrint('[ProcessingHandler] 全部处理完成');
    await _stopService();
  }

  Future<void> _processEntry(DiaryEntry entry) async {
    debugPrint('[ProcessingHandler] 开始处理: ${entry.id}, stage=${entry.processingStage.value}');

    switch (entry.processingStage) {
      case ProcessingStage.uploading:
        await _doUpload(entry);
        await _doAsr(entry);
        await _doLlm(entry);
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.asr:
        // TOS 已上传（tosKey 存在），直接 ASR
        await _doAsr(entry);
        await _doLlm(entry);
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.llm:
        // ASR 已完成，transcript.json 已存在
        await _doLlm(entry);
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.tagging:
        // LLM 已完成，llm_result.json 已存在
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.completed:
        // 已完成，跳过（可能是上次中断前刚好完成）
        await _doComplete(entry);
    }
  }

  /// 阶段 2: 上传音频到 TOS
  Future<void> _doUpload(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 上传音频...',
    );

    // 查找音频文件
    String? audioFilePath;
    for (final name in ['audio.ogg', 'audio.wav']) {
      final f = File('${entry.folderPath}/$name');
      if (await f.exists()) {
        audioFilePath = f.path;
        break;
      }
    }
    if (audioFilePath == null) {
      throw Exception('音频文件不存在: ${entry.folderPath}');
    }

    final tosKey = await _tosService.uploadAudio(audioFilePath, entry.id);
    await _storageService.updateTosKeyAndStage(entry.id, tosKey, ProcessingStage.asr);
    debugPrint('[ProcessingHandler] 上传完成: $tosKey');
  }

  /// 阶段 3: ASR 识别（同步 Flash ASR）
  Future<void> _doAsr(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 语音识别...',
    );

    final tosKey = await _storageService.getTosKey(entry.id);
    if (tosKey == null) {
      throw Exception('tosKey 为空，无法进行 ASR');
    }

    final presignedUrl = await _tosService.getPresignedUrl(tosKey);
    final asrResult = await _asrService.transcribeFromUrl(presignedUrl);

    await _storageService.writeTranscriptJson(
      entry.folderPath,
      TranscriptData(version: 1, utterances: asrResult.utterances),
    );
    await _storageService.updateProcessingStage(entry.id, ProcessingStage.llm);
    debugPrint('[ProcessingHandler] ASR 完成');
  }

  /// 阶段 4: LLM 润色汇总
  Future<void> _doLlm(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - AI 总结...',
    );

    final transcript = await _storageService.readTranscriptJson(entry.folderPath);
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
    await _storageService.updateProcessingStage(entry.id, ProcessingStage.tagging);
    debugPrint('[ProcessingHandler] LLM 完成');
  }

  /// 阶段 5: 标签归类（失败不阻塞）
  Future<void> _doTagging(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 自动归类...',
    );

    try {
      final llmResult = await _storageService.readLlmResult(entry.folderPath);
      final allTags = await _storageService.getAllTags();
      final tagsWithPrompt =
          allTags.where((t) => t.matchPrompt.isNotEmpty).toList();
      if (tagsWithPrompt.isNotEmpty) {
        final tagInfos = tagsWithPrompt
            .map((t) => TagInfo(id: t.id, name: t.name, matchPrompt: t.matchPrompt))
            .toList();
        final matchedTagIds =
            await _llmService.matchTags(llmResult.content, tagInfos);
        if (matchedTagIds.isNotEmpty) {
          await _storageService.autoTagDiary(entry.id, matchedTagIds);
        }
      }
    } catch (e) {
      debugPrint('[ProcessingHandler] 自动归类失败（不阻塞）: $e');
    }
    debugPrint('[ProcessingHandler] 标签归类完成');
  }

  /// 阶段 6: 完成
  Future<void> _doComplete(DiaryEntry entry) async {
    // 读取 LLM 结果获取标题
    String title = entry.displayTitle;
    try {
      final llmResult = await _storageService.readLlmResult(entry.folderPath);
      title = llmResult.title;
    } catch (_) {}

    await _storageService.updateEntry(DiaryEntry(
      id: entry.id,
      title: title,
      folderPath: entry.folderPath,
      durationSeconds: entry.durationSeconds,
      createdAt: entry.createdAt,
      tosKey: entry.tosKey,
      audioFormat: entry.audioFormat,
      uploadedAt: DateTime.now(),
      weatherIcon: entry.weatherIcon,
      weatherText: entry.weatherText,
      temperature: entry.temperature,
      locationName: entry.locationName,
      locationLat: entry.locationLat,
      locationLon: entry.locationLon,
      status: EntryStatus.completed,
      processingStage: ProcessingStage.completed,
    ));

    FlutterForegroundTask.updateService(
      notificationTitle: '处理完成',
      notificationText: '语音日记 - $title',
    );

    _sendToMain({'type': 'completed', 'entryId': entry.id});
    debugPrint('[ProcessingHandler] 处理完成: ${entry.id}');
  }

  Future<void> _markFailed(String id, String title) async {
    try {
      await _storageService.updateEntryTitleAndStatus(id, title, EntryStatus.failed);
    } catch (e) {
      debugPrint('[ProcessingHandler] 标记 failed 失败: $e');
    }
    _sendToMain({'type': 'failed', 'entryId': id, 'step': 0, 'error': ''});
  }

  Future<void> _stopService() async {
    await Future.delayed(const Duration(seconds: 2));
    FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
    _sendToMain({
      'type': 'notificationPressed',
      'state': 'processing',
      'entryId': '',
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ProcessingHandler] onDestroy, isTimeout=$isTimeout');
  }
}
```

注意：需要新增 `getTosKey` 方法到 `DiaryStorageService`:

```dart
Future<String?> getTosKey(String id) async {
  final entry = await _db.getEntryById(id);
  return entry.tosKey;
}
```

- [ ] **Step 2: 运行 analyze 确认无错误**

Run: `flutter analyze`
Expected: 可能有 recording_page.dart 的编译错误（Task 4 中修复），recording_processor.dart 本身无错误

- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "refactor: 创建 ProcessingTaskHandler，基于 processingStage 阶段恢复"
```

---

## Task 4: 更新主 isolate 协调逻辑

更新 RecordingPage 的 FGS 协调逻辑：录音结束后启动 Processing FGS，录音开始前停止 Processing FGS。更新 DiaryListPage 的重试逻辑。

**Files:**
- Modify: `lib/pages/recording_page.dart`
- Modify: `lib/pages/diary_list_page.dart`

- [ ] **Step 1: 更新 RecordingPage**

在 `lib/pages/recording_page.dart` 中：

1. 修改 import：将 `import '../services/recording_processor.dart'` 替换为 `import 'package:flutter_foreground_task/flutter_foreground_task.dart';`（已有）
   删除 `RecordingProcessor` 相关 import
   新增 `import '../services/recording_processor.dart' show processingCallback;`

2. 修改 `_startRecording`：在启动 Recording FGS 之前，先停止可能正在运行的 Processing FGS：

```dart
Future<void> _startRecording() async {
  try {
    // 检查麦克风权限
    if (!await AudioRecorder().hasPermission()) {
      _showError('需要麦克风权限才能录音');
      return;
    }

    // 先停止可能正在运行的 Processing FGS
    FlutterForegroundTask.stopService();

    // 设置通信端口
    FlutterForegroundTask.initCommunicationPort();

    // 启动 Recording FGS
    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: '正在录音',
      notificationText: '语音日记 - 录音中...',
      callback: startCallback,
    );

    if (result is ServiceRequestFailure) {
      throw Exception(result.error);
    }

    setState(() => _state = RecordingState.recording);
  } catch (e) {
    _showError('录音启动失败：$e');
  }
}
```

3. 修改 `_stopRecording`：发送 stop 后，不再需要调 `_refreshProcessingCount()`，因为 Processing FGS 会发消息过来

4. 修改 `_onTaskData`：处理 `recordingComplete` 消息——启动 Processing FGS：

```dart
case 'recordingComplete':
  // 录音完成，启动 Processing FGS
  _startProcessingFgs();
```

5. 新增 `_startProcessingFgs` 方法：

```dart
Future<void> _startProcessingFgs() async {
  try {
    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 处理中...',
      callback: processingCallback,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('[RecordingPage] 启动 Processing FGS 失败: ${result.error}');
    }
    _refreshProcessingCount();
  } catch (e) {
    debugPrint('[RecordingPage] 启动 Processing FGS 异常: $e');
  }
}
```

6. 确保 `completed` 和 `failed` 消息仍然触发 `_refreshProcessingCount()`

- [ ] **Step 2: 更新 DiaryListPage 重试逻辑**

在 `lib/pages/diary_list_page.dart` 中：

1. 修改 import：`import '../services/recording_processor.dart'` 改为 `import '../services/recording_processor.dart' show processingCallback;`（删除 `RecordingProcessor` 相关引用）

2. 修改 `_retryEntry` 方法——启动 Processing FGS 而不是调用 `RecordingProcessor.instance.retryEntry`：

```dart
Future<void> _retryEntry(DiaryEntry entry) async {
  // 更新状态为 processing（processingStage 保持 failed 时的值）
  await DiaryStorageService().updateEntryTitleAndStatus(
    entry.id,
    '正在处理中...',
    EntryStatus.processing,
  );

  // 启动 Processing FGS
  try {
    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: '正在重新处理',
      notificationText: '语音日记 - 处理中...',
      callback: processingCallback,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('[DiaryListPage] 启动 Processing FGS 失败: ${result.error}');
    }
  } catch (e) {
    debugPrint('[DiaryListPage] 启动 Processing FGS 异常: $e');
  }

  _loadData();
}
```

3. 删除 `RecordingProcessor` 相关的 `_tasksSubscription` 和 `_processingTasks` 逻辑（`RecordingProcessor` 不再有 stream）

4. 保留 FGS 消息监听（`completed`/`failed` 时 `_loadData()`）

- [ ] **Step 3: 运行 analyze 确认无错误**

Run: `flutter analyze`
Expected: 无 error/warning（info 级别的已有提示可忽略）

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "refactor: 主 isolate 双 FGS 协调，录音结束后启动 Processing FGS"
```

---

## Task 5: 清理和验证

清理废弃代码，确保整体一致性。

**Files:**
- Modify: `lib/services/recording_processor.dart`（如果 `RecordingProcessor` class 残留）
- Various: 清理未使用的 import

- [ ] **Step 1: 清理 RecordingProcessor 残留**

确保 `lib/services/recording_processor.dart` 中不再有 `RecordingProcessor` 类、`ProcessingTask` 模型、`_queue`、`_processing` 等队列管理代码。文件应该只包含 `processingCallback` 和 `ProcessingTaskHandler`。

- [ ] **Step 2: 清理未使用的 import**

全局搜索 `recording_processor` 的 import，确保没有引用旧的 `RecordingProcessor` 类。

Run: `grep -rn "RecordingProcessor" lib/`
Expected: 无结果（只有 `RecordingProcessor` 不再被引用）

- [ ] **Step 3: 全量 analyze**

Run: `flutter analyze`
Expected: 无新增 error/warning

- [ ] **Step 4: 端到端测试**

手动测试以下场景：
1. 录音 → 停止 → 等待处理完成 → 日记显示正确
2. 录音 → 停止 → 立刻开始新录音 → 停止 → 两条日记都处理完成
3. 日记列表中失败条目 → 点重试 → 处理完成
4. 首页 Badge 显示 processing + failed 数量
5. 杀进程重启 → Processing FGS 是否自动恢复（需要验证主 isolate 启动时是否有恢复逻辑）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor: 清理废弃代码，确保双 FGS 架构一致性"
```

---

## 自审清单

| Spec 要求 | 对应 Task |
|-----------|----------|
| ProcessingStage 枚举（uploading/asr/llm/tagging/completed） | Task 1 |
| DB 新增 processingStage 字段 | Task 1 |
| RecordingTaskHandler 只做录音 | Task 2 |
| ProcessingTaskHandler 基于 processingStage 恢复 | Task 3 |
| DB 即队列（getPendingEntries） | Task 1 (DB) + Task 3 (Handler) |
| FGS 切换：录音开始前 stopService | Task 4 |
| FGS 切换：录音结束后启动 Processing FGS | Task 4 |
| 失败标记为 failed，processingStage 保持 | Task 3 |
| 重试从 processingStage 恢复 | Task 3 + Task 4 |
| FIFO 顺序 | Task 1 (getPendingEntries 按 createdAt ASC) |
| 标签归类失败不阻塞 | Task 3 (_doTagging try-catch) |
| Badge 统计 processing + failed | 已在前次提交实现，无需改动 |
| ASR 失败直接标记 failed | Task 3 (异常由 _processEntry 的 catch 处理) |

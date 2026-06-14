# 重新分析已完成的日记 — 设计文档

- 日期：2026-06-14
- 状态：待评审

## 背景与目标

为已分析完成（`status == completed`）的日记提供「重新分析」入口：在详情页 AppBar 删除按钮旁加一个按钮，点击后重跑完整的 ASR → LLM → tag 流程，覆盖现有结果。走 FGS 后台处理，与录音后处理体验一致（可离开页面、可锁屏、详情页实时进度）。

## 范围

### 做

- 详情页（仅 `completed` 状态）加「重新分析」按钮
- 全量重跑 ASR / LLM / tag，覆盖现有结果
- FGS 后台执行

### 不做（与失败重试区分）

- **失败重试入口保持不变**：现有 `_retry()` + 失败横幅的「重新处理」按钮仅在 `failed` 状态出现，根据 `processingStage` 从失败步骤**断点续跑**。这是另一个功能、另一个入口，本次不动。
- 重新分析**不重新录音**，复用现有 `audio.wav` / `audio.ogg`。

## 关键决策（已与用户确认）

| 决策点 | 选择 | 说明 |
|---|---|---|
| 标签处理 | 保留全部、仅追加 | 不删除现有标签（含手动 `source=manual`），新匹配的自动标签（`source=auto`）追加进来 |
| ASR | 强制重跑 | 通过清空 `asrTaskId` 让 `_doAsr` 重新 submit，而非 poll 旧 task 拿旧结果 |
| 执行方式 | FGS 后台处理 | 复用 `ProcessingTaskHandler`，与录音后处理一致 |
| 入口可见性 | 仅 `completed` 状态显示 | 处理中 / 失败的条目不显示（失败有自己的重试入口） |

## 架构

**方案 A：重置状态字段 + 复用现有 `ProcessingTaskHandler`。`ProcessingTaskHandler` 零改动。**

核心思路：全量重跑 = 「把一条 completed 重新塞回 processing 队列，且强制重跑 ASR」。这恰好能靠重置 DB 状态字段 + 现有续跑机制实现，无需新代码路径。

`ProcessingTaskHandler._processEntry` 靠 `processingStage` 续跑（`recording_processor.dart:92-122`）：`stage=asr` 时走完整 ASR→LLM→tagging→complete。而 `_doAsr`（`recording_processor.dart:153-233`）在 `asrTaskId == null` 时会重新 submit ASR，`asrTaskId != null` 时会先尝试 poll 旧 task——所以强制重跑 ASR 的关键是清空 `asrTaskId`。

### 组件改动

**① `DiaryStorageService` 加方法 `resetEntryForReanalysis(String id)`**

一条 update 语句重置处理状态字段，不动 `title` / `folderPath` / `transcript.json` 等数据：

- `status → processing`（让 `getPendingEntries` 拾取）
- `processingStage → asr`（tosKey 已存在，跳过重新上传；tosKey 不存在的保险情况落到 `uploading`）
- `asrTaskId → null`（**关键**：强制 `_doAsr` 重新 submit）

无 schema 变更、向后兼容、不动用户数据文件。伪代码：

```dart
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

**② 抽公共函数 `startProcessingFgs()`**

启动逻辑目前写在 `RecordingPage._startProcessingFgs()`（`recording_page.dart:278-304`，含 `initCommunicationPort` + 防冲突 `stopService` + `startService(callback: processingCallback)`）。详情页也要用，抽到公共位置（如新建 `lib/services/processing_fgs_controller.dart`）。`RecordingPage` 原方法改为调用公共函数。

**③ `DiaryDetailPage` 改动**

- AppBar `actions` 里，删除按钮**前**加「重新分析」`IconButton`（图标 `Icons.refresh`），**仅当 `_entry.status == completed` 时显示**。
- 点击 → 确认弹窗 → `resetEntryForReanalysis` + `startProcessingFgs()` + 本地乐观更新。
- 进度展示**完全复用**现有 `_onTaskData`（`diary_detail_page.dart:74-107`，已监听 `stageUpdate` / `completed` / `failed` / `processingDone`）。

### 不改

- `ProcessingTaskHandler`（零改动）
- 失败重试入口（`_retry` + 失败横幅）
- `RecordingPage` 其余逻辑（仅改为调用公共 `startProcessingFgs()`）

## 数据流

点击「重新分析」后的完整流程（正常路径）：

1. **确认弹窗** —— 文案：「将重新识别语音并重新生成总结，当前的识别结果和总结会被覆盖。标签会保留，并追加新匹配的标签。」→ 用户点「重新分析」确认
2. **`await resetEntryForReanalysis(id)`** —— DB 写入（快，毫秒级）
3. **本地乐观更新** —— `setState`：`_entry = _entry.copyWith(status: processing, processingStage: asr)`、`_isActivelyProcessing = true`。页面立即显示「语音识别中...」处理横幅（`_buildStatusBanner` 的 processing 分支按 `processingStage` 显示阶段文本），无需等 FGS 启动
4. **`await startProcessingFgs()`** —— 启动后台 FGS
5. **FGS 处理** —— `ProcessingTaskHandler.onStart` → `getPendingEntries` 拾取这条 → `_processEntry(stage=asr)`：
   - `_doAsr`（`asrTaskId=null` → 重新 submit，覆盖写 `transcript.json`）
   - `_doLlm`（覆盖写 `llm_result.json`）
   - `_doTagging`（`autoTagDiary` 追加新标签）
   - `_doComplete`（`status → completed`，`title` 更新为新 LLM 标题）
6. **实时进度** —— 每阶段 `sendDataToMain(stageUpdate / completed)`，详情页 `_onTaskData` 刷新横幅（语音识别 → AI 总结 → 自动归类）与标题
7. **完成** —— 收到 `completed` → `_loadContent()` 加载最终结果

## 状态转换

```
completed ──(点重新分析 + 确认)──▶ processing[asr] ──(FGS)─▶ asr ─▶ llm ─▶ tagging ─▶ completed
```

对详情页而言，整个过程与「录音后处理」体验完全一致：同一套横幅、同一套进度文本、同一套消息监听。

## 错误处理

分阶段：

- **reset / 启动阶段失败**：`resetEntryForReanalysis` 抛错 → catch、toast「重新分析启动失败」、不改 UI（entry 保持 `completed`，无副作用）。`startProcessingFgs` 失败 → entry 已是 `processing`、已入队，toast「已加入处理队列，稍后自动处理」。
- **FGS 处理中失败**：复用 `ProcessingTaskHandler` 现有逻辑——ASR/LLM 失败 → `_markFailed`（`status → failed`，`stage` 停在失败处）→ 详情页显示**失败横幅 + 现有「重新处理」按钮**。即「重新分析失败后自动落到失败重试路径」，用户可从失败步骤断点续跑，无需新错误入口。
- **tag 失败**：不阻塞（现有行为）。
- **ASR 结果为空**：走 `_handleEmptyAsr`（写占位结果 + `completed`，现有行为）。

## 并发冲突

核心约束：**不能中断正在进行的录音**。

需要一个 main isolate 的全局 FGS 模式感知（`none / recording / processing`，由录音页 / 处理启动时写入；只服务 main isolate，不跨 isolate）。点击「重新分析」后的行为：

| 当前 FGS | 动作 |
|---|---|
| 录音中 | 仅 `resetEntryForReanalysis`（入队）+ toast「录音结束后将自动处理」，**不启动**新 FGS。录音完成后 `RecordingPage._scheduleProcessingFgs` 会拾取 |
| processing 中 | `stopService` + 重启 processing FGS——被中断的那条 entry 靠保留的 `processingStage` 下次续跑，不丢 |
| 无 | 直接启动 processing FGS |

## 测试策略

- **单元测试** `resetEntryForReanalysis`：用内存 drift DB，验证重置后 `status=processing`、`stage=asr`（有 tosKey）/ `uploading`（无 tosKey）、`asrTaskId=null`、tosKey 保留、`transcript.json` 未被改动。
- **手动验证**（FGS + 真实 ASR/LLM 无法自动化）：
  1. completed 日记点重新分析 → 进度横幅流转 → 完成后标题 / 总结更新。
  2. 重新分析失败 → 落到失败横幅、「重新处理」可用。
  3. 录音中点 → toast、录音后自动处理。
- `flutter analyze` + `flutter test` 确保无回归。

## 开放问题（实现时确认）

- `flutter_foreground_task` 是否提供查询当前运行 callback 类型的 API；若不能，用 main isolate 全局 FGS 模式标志（`none / recording / processing`）实现并发判断。

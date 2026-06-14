# 缺陷 1：录音静默中断后台 processing

- 严重度：中高
- 状态：待修复
- 相关边界用例：#1 / #3 / #4 / #9 / #12（同源）

## 问题描述

`RecordingPage._startRecording` 启动录音 FGS 时，会停掉正在运行的 processing FGS（`FlutterForegroundTask` 同一时刻只允许一个 FGS）。但它只检查局部状态 `_isProcessingFgsRunning`，**不检查全局 `FgsRuntime.mode`**——而「重新分析」启动的 processing FGS 走 `ProcessingFgsController`，不经过 `RecordingPage`，所以 `_isProcessingFgsRunning` 保持 false。

结果：用户在详情页触发「重新分析」（processing FGS 在后台跑 ASR/LLM）→ 切到 `RecordingPage` 录音 → `_startRecording` 误判"没有 processing 在跑" → 直接 `startService(recording)` → **静默中断正在跑的重新分析**。

## 触发条件 / 复现

1. 打开一篇 `completed` 日记详情页，点「重新分析」（processing FGS 开始跑）
2. 立即返回 `RecordingPage`，点录音按钮
3. 录音启动 → processing FGS 被停掉 → 重新分析的 ASR/LLM 调用被中断

## 根因

`lib/pages/recording_page.dart` `_startRecording`：

```dart
Future<void> _startRecording() async {
  _processingDelayTimer?.cancel();
  _processingDelayTimer = null;

  if (_isProcessingFgsRunning) {   // ← 只跟踪 RecordingPage 自己启动的 processing FGS
    setState(() => _state = RecordingState.processing);
    FlutterForegroundTask.stopService();
    return;
  }
  await _doStartRecording();        // ← 重新分析的 processing 不在此判断内，直接启动录音
}
```

`_isProcessingFgsRunning` 仅在 `RecordingPage._startProcessingFgs` 里设 true。`ProcessingFgsController.start()`（详情页重新分析路径）不触碰它。

**对称性缺失**：`FgsRuntime.mode` 被用于 `ProcessingFgsController.start()` 的 recording 方向检查（录音中拒绝启动 processing），但**没有用于 `RecordingPage._startRecording` 的 processing 方向检查**。

## 影响

- 正在进行的 ASR/LLM API 调用被中断，**浪费 API 配额**
- 用户**无感知**（没有任何提示）
- 被中断的 entry 不会丢数据——`processingStage` 已持久化，录音结束后 `_scheduleProcessingFgs` 的 `getPendingEntries` 会拾取并续跑。但续跑前用户看到的是「处理中」状态，体验不一致

## 修复方案

`_startRecording` 的判断条件扩展为也看 `FgsRuntime.mode`：

```dart
if (_isProcessingFgsRunning || FgsRuntime.mode == FgsMode.processing) {
  setState(() => _state = RecordingState.processing);
  if (FgsRuntime.mode == FgsMode.processing) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已暂停后台处理，录音结束后自动继续')),
    );
  }
  FlutterForegroundTask.stopService();
  return;
}
await _doStartRecording();
```

**行为不变**（仍是"录音优先、中断 processing、靠 `processingStage` 续跑"），只是覆盖范围从"RecordingPage 启动的 processing"扩到"任何 processing"。`processingDone` 回调后现有的 `_doStartRecording` 逻辑接管。

**改动文件**：`lib/pages/recording_page.dart`。风险低（扩展判断条件，不改现有流程）。

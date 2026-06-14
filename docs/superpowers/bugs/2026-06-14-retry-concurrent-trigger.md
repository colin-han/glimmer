# 缺陷 2：_retry 离开页面后可重复触发（并发）

- 严重度：中
- 状态：待修复
- 相关边界用例：#6

## 问题描述

失败重试 `_retry` 仅靠详情页实例的局部 `_retrying` 标志防止重复点击。用户离开详情页（dispose）后，`_retrying` 随实例消失，但 `_retry` 的 async 链在后台继续跑。用户重新进入详情页（新实例、`_retrying=false`），失败横幅仍显示「重新处理」按钮，可再次点击 → **两个 `_retry` 并发跑同一日记的 ASR/LLM**。

## 触发条件 / 复现

1. 打开一篇 `failed` 日记详情页，点「重新处理」（`_retry` 开始跑，ASR/LLM 耗时）
2. `_retry` 跑到一半，返回上一页（详情页 dispose，`_retry` 在后台继续）
3. 重新进入该日记详情页（新实例，`_retrying=false`）
4. 失败横幅的「重新处理」按钮仍在 → 点击 → 第二个 `_retry` 启动，与第一个并发

## 根因

`lib/pages/diary_detail_page.dart` `_retry`：

```dart
Future<void> _retry() async {
  setState(() => _retrying = true);   // ← 仅详情页实例局部 state
  try {
    ... // await ASR / LLM / 写文件 / updateTitle
  } catch (e) { ... }
}
```

`_retrying` 是 `_DiaryDetailPageState` 的实例字段，不跨实例、不跨页面。没有任何全局锁。

失败横幅的按钮显示条件（`_buildStatusBanner`）：
```dart
if (_retrying)
  const SizedBox(... CircularProgressIndicator ...)   // 转圈
else
  TextButton.icon(onPressed: _retry, ...);            // 按钮
```
同一实例内 `_retrying` 锁有效；跨实例失效。

## 影响

- **浪费 API**：同一日记的 ASR/LLM 被调用两次
- **写入竞态**：两次 `writeLlmResult`。`_writeAtomic`（临时文件 + rename）保证不损坏文件，但"最后写赢"——先完成的 LLM 结果可能被后完成的覆盖，结果不确定
- **加剧因素**：缺陷 3（`_retry` 不更新 status）让失败横幅 + 按钮在 `_retry` 成功后仍存在，用户更可能重复点

## 修复方案

`FgsRuntime` 加全局 `_retry` 锁（单个进行中的重试 entryId）：

```dart
// fgs_runtime.dart
static String? activeRetryEntryId;
static bool isRetrying(String id) => activeRetryEntryId == id;
static void markRetrying(String id) => activeRetryEntryId = id;
static void clearRetrying() => activeRetryEntryId = null;
```

`_retry` 入口加锁、`finally` 清锁：

```dart
Future<void> _retry() async {
  if (FgsRuntime.activeRetryEntryId != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已有重试在进行，请稍候')),
    );
    return;
  }
  FgsRuntime.markRetrying(_entry.id);
  setState(() => _retrying = true);
  try {
    ... // 现有逻辑
  } finally {
    FgsRuntime.clearRetrying();
  }
}
```

**为何用全局 entryId 锁而非 DB status 作锁**：`_retry` 走 main isolate，若改 `status=processing` 会被 `getPendingEntries` 拾取，导致 FGS 和 `_retry` **并发处理同一 entry**（更糟）。全局静态锁只在 main isolate 可见，不影响 FGS 的 `getPendingEntries`。单值锁（同时只一个 retry）合理——`_retry` 资源密集，串行更稳。

**改动文件**：`lib/services/fgs_runtime.dart` + `lib/pages/diary_detail_page.dart`。风险低（新增锁，不改现有处理流程）。

# 缺陷 3：_retry 成功后不更新 status

- 严重度：中
- 状态：待修复
- 相关边界用例：NEW（深入分析时发现）

## 问题描述

失败重试 `_retry` 的正常成功路径只写 `llm_result.json`、更新 title、自动打标，但**不更新 entry 的 `status`**（`failed → completed`）。只有空结果路径 `_finishAsEmpty` 会更新 status。

结果：`failed` 日记 `_retry` 成功后，内容已正确写入，但 DB `status` 仍是 `failed` → 详情页同时显示**失败横幅 + 「重新处理」按钮**和**成功的内容**，自相矛盾。

## 触发条件 / 复现

1. 一篇 `failed` 日记（如断网导致 LLM 失败）
2. 详情页点「重新处理」，`_retry` 成功（网络恢复，LLM 返回结果）
3. `_retry` 写入 `llm_result.json`、更新 title
4. 详情页刷新：`_hasLlm=true` 显示内容，但 `status` 仍 `failed` → 失败横幅 + 「重新处理」按钮仍在

## 根因

`lib/pages/diary_detail_page.dart` `_retry` 正常成功路径（约 231-274 行）：

```dart
final llmResult = await _llmService.summarize(utterances);
await _storageService.writeLlmResult(...);
await _storageService.updateTitle(_entry.id, llmResult.title);   // ← 只改 title，无 status
// 自动打 tag ...
setState(() { _retrying = false; _loading = true; });
await _loadContent();
```

**没有 `updateEntryStatus(EntryStatus.completed)`**。

对比：
- 空结果路径 `_finishAsEmpty`（285+ 行）：调 `updateEntryTitleAndStatus(id, title, completed)` ✓
- FGS 路径 `ProcessingTaskHandler._doComplete`（`recording_processor.dart:378-412`）：调 `updateEntry(status=completed)` ✓

`_retry` 是 main isolate 的早期代码（早于 `status` 字段——该字段在 drift schema v5 引入），漏了等价的 status 更新。历史遗留。

## 影响

- **UI 自相矛盾**：失败横幅（含「重新处理」按钮）+ 成功内容同时显示，用户困惑
- **加剧缺陷 2**：失败横幅的按钮一直在，用户更可能重复点击触发并发 `_retry`
- 列表页 `_onTaskData`（`diary_list_page.dart`）只在收到 `completed`/`failed` 消息时刷新，`_retry` 不发消息 → 列表页该日记的状态/分组不更新（仍显示失败样式）

## 修复方案

`_retry` 成功路径把 `updateTitle` 改为 `updateEntryTitleAndStatus`（一次 DB 写 title + status）：

```dart
// 原：
// await _storageService.updateTitle(_entry.id, llmResult.title);

// 改为：
await _storageService.updateEntryTitleAndStatus(
  _entry.id, llmResult.title, EntryStatus.completed);
```

与 `_finishAsEmpty`、`_doComplete` 的 status 更新方式一致。改后 failed 日记 `_retry` 成功 → `status=completed` → 失败横幅消失、内容正常。

**改动文件**：`lib/pages/diary_detail_page.dart`。风险极低（一行替换，`updateEntryTitleAndStatus` 已存在于 `DiaryStorageService`）。

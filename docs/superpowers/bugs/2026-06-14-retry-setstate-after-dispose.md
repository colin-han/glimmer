# 次要缺陷 #5：_retry 成功路径 setState 无 mounted 检查

- 严重度：低
- 状态：待修复（次要）
- 相关边界用例：#5

## 问题描述

`_retry` 正常成功路径在 `await _loadContent()` 前调用 `setState`，但**没有 `if (mounted)` 检查**。若 `_retry` 完成时详情页已 dispose（用户在 `_retry` 跑到一半离开了页面），`setState` 会触发 Flutter 异常。

catch 分支有 `mounted` 检查，正常成功路径漏了。

## 触发条件 / 复现

1. `failed` 日记点「重新处理」，`_retry` 开始跑（ASR/LLM 耗时）
2. `_retry` 跑到一半，返回上一页（详情页 dispose）
3. `_retry` 在后台继续，成功完成后到达 `setState` → 页面已 dispose → 控制台抛异常

## 根因

`lib/pages/diary_detail_page.dart` `_retry` 约 270-274 行：

```dart
setState(() {              // ← 无 if (mounted)
  _retrying = false;
  _loading = true;
});
await _loadContent();
```

对比 catch 分支（276 行）有 `if (mounted)`：
```dart
} catch (e) {
  if (mounted) {
    setState(() => _retrying = false);
    ...
  }
}
```

成功路径漏了对称的 `mounted` 检查。`_loadContent` 内部已有 `mounted` 检查，但前面这个 `setState` 没有。

## 影响

- 控制台 Flutter 异常（`setState() called after dispose()`），不影响数据正确性
- 用户无感知（除非看日志），但属于应避免的 framework 异常

## 修复方案

加 `if (mounted)`：

```dart
if (mounted) {
  setState(() {
    _retrying = false;
    _loading = true;
  });
}
await _loadContent();   // _loadContent 内部已有 mounted 检查
```

**改动文件**：`lib/pages/diary_detail_page.dart`。风险极低。

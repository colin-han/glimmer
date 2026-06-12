# 日记详情页自适应展示 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日记详情页根据数据文件完整性渐进展示内容，所有有音频的条目均可点击进入详情页。

**Architecture:** 基于文件探测（audio.* → transcript.json → llm_result.json）决定展示层级，不依赖 processingStage 字段。详情页监听 FGS 消息自动刷新，processing/failed 状态通过横幅组件展示进度和重试。

**Tech Stack:** Flutter, flutter_foreground_task, flutter_markdown, just_audio

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/pages/diary_list_page.dart` | Modify | `_buildEntryCard` 统一所有状态可点击 |
| `lib/pages/diary_detail_page.dart` | Major rewrite | 文件探测加载、渐进展示、状态横幅、FGS 监听 |

---

### Task 1: 列表页统一可点击

**Files:**
- Modify: `lib/pages/diary_list_page.dart:300-368`（`_buildEntryCard` 方法）

- [ ] **Step 1: 修改 `_buildEntryCard`，所有状态均可点击进入详情页**

将 `_buildEntryCard` 中的 `onTap` 和 `trailing` 逻辑改为：

```dart
Widget _buildEntryCard(DiaryEntry entry) {
  final tags = _entryTags[entry.id] ?? [];
  final isProcessing = entry.status == EntryStatus.processing;
  final isFailed = entry.status == EntryStatus.failed;
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    color: isFailed ? Colors.red[50] : null,
    child: ListTile(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.displayTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: tags
                    .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _getTagColor(tag)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(tag.name,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _getTagColor(tag))),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
            '${entry.formattedDate}  ${entry.durationDisplay}${entry.weatherDisplay.isNotEmpty ? '  ${entry.weatherDisplay}' : ''}'),
      ),
      trailing: isProcessing
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400]),
            )
          : isFailed
              ? Icon(Icons.error_outline, color: Colors.red[400], size: 20)
              : const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => DiaryDetailPage(entry: entry)))
            .then((_) => _loadData());
      },
    ),
  );
}
```

关键变化：
- `isProcessing`/`isFailed` 条目不再拦截 `onTap`，统一跳转详情页
- `isFailed` trailing 从重试按钮改为错误图标
- 移除 `_retryEntry` 中通过列表页重试的入口（保留方法供详情页重试时复用 FGS 启动逻辑）

- [ ] **Step 2: 代码分析**

Run: `flutter analyze lib/pages/diary_list_page.dart`
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add lib/pages/diary_list_page.dart
git commit -m "refactor: 日记列表页所有状态条目统一可点击进入详情页"
```

---

### Task 2: 详情页数据加载重构

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: 重写 `_loadContent` 为基于文件探测的渐进加载**

替换 `_loadContent()` 方法，新增状态变量：

```dart
// 新增状态变量（替换原有的 _loading, _needsRetry, _retrying, _retryError）
bool _loading = true;
bool _audioExists = false;
bool _transcriptExists = false;
bool _hasLlm = false;
String _summary = '';
String _content = '';
List<Utterance> _summaryUtterances = [];
TranscriptData? _transcriptData;
List<Tag> _tags = [];
bool _retrying = false;
```

新的 `_loadContent`：

```dart
Future<void> _loadContent() async {
  final audioPath = _storageService.getAudioPath(
      widget.entry.folderPath, widget.entry.audioFormat);
  final audioExists = File(audioPath).existsSync();
  final transcriptExists =
      await File(p.join(widget.entry.folderPath, 'transcript.json')).exists();
  final hasLlm = await _storageService.hasLlmResult(widget.entry.folderPath);

  TranscriptData? transcriptData;
  if (transcriptExists) {
    try {
      transcriptData =
          await _storageService.readTranscriptJson(widget.entry.folderPath);
    } catch (_) {}
  }

  String summary = '';
  String content = '';
  List<Utterance> summaryUtterances = [];

  if (hasLlm) {
    final llmData =
        await _storageService.readLlmResult(widget.entry.folderPath);
    summary = llmData.summary.isNotEmpty ? llmData.summary : llmData.content;
    content = llmData.content;
    summaryUtterances = llmData.utterances;
  } else if (transcriptExists) {
    // 无 LLM 结果但有转写：用转写文本作为摘要
    try {
      summary = transcriptData?.fullText ?? '';
    } catch (_) {}
  }

  if (mounted) {
    setState(() {
      _audioExists = audioExists;
      _transcriptExists = transcriptExists;
      _hasLlm = hasLlm;
      _summary = summary;
      _content = content;
      _summaryUtterances = summaryUtterances;
      _transcriptData = transcriptData;
      _loading = false;
    });

    if (widget.autoPlaySummary && summary.isNotEmpty && hasLlm) {
      _speakSummary(summary);
    }
  }
  _loadTags();
}
```

移除 `_needsRetry` 和 `_retryError` 变量及所有引用。

- [ ] **Step 2: 代码分析**

Run: `flutter analyze lib/pages/diary_detail_page.dart`
Expected: 编译错误（因为 `build()` 还引用了 `_needsRetry`），这是预期的，下一步修复

- [ ] **Step 3: 提交**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "refactor: 详情页数据加载改为基于文件探测的渐进加载"
```

---

### Task 3: 详情页 UI 重构 — 状态横幅 + 渐进内容

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: 添加 FGS 消息监听**

在 `initState` 中注册回调，在 `dispose` 中移除：

```dart
@override
void initState() {
  super.initState();
  _loadContent();
  FlutterForegroundTask.addTaskDataCallback(_onTaskData);
}

@override
void dispose() {
  FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
  _playerService.dispose();
  super.dispose();
}

void _onTaskData(Object data) {
  if (data is! Map<String, dynamic>) return;
  final type = data['type'] as String;
  if ((type == 'completed' || type == 'processingDone') && mounted) {
    // 处理完成，重新加载内容
    _loadContent();
  }
}
```

需要在文件顶部添加 import：
```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
```

- [ ] **Step 2: 新增 `_buildStatusBanner` 方法**

```dart
Widget _buildStatusBanner() {
  final isProcessing = widget.entry.status == EntryStatus.processing;
  final isFailed = widget.entry.status == EntryStatus.failed;
  if (!isProcessing && !isFailed) return const SizedBox.shrink();

  if (isProcessing) {
    final stageText = switch (widget.entry.processingStage) {
      ProcessingStage.uploading => '上传中...',
      ProcessingStage.asr => '语音识别中...',
      ProcessingStage.llm => 'AI 总结中...',
      ProcessingStage.tagging => '自动归类中...',
      ProcessingStage.completed => '即将完成...',
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue[700]),
                ),
                const SizedBox(width: 8),
                Text('🔄 正在处理: $stageText',
                    style: TextStyle(color: Colors.blue[900])),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(color: Colors.blue[300]),
          ],
        ),
      ),
    );
  }

  // failed
  final failedStage = switch (widget.entry.processingStage) {
    ProcessingStage.uploading => '上传失败',
    ProcessingStage.asr => '语音识别失败',
    ProcessingStage.llm => 'AI 总结失败',
    ProcessingStage.tagging => '归类失败',
    ProcessingStage.completed => '处理失败',
  };
  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: Colors.red[50],
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('❌ $failedStage',
                style: TextStyle(color: Colors.red[900])),
          ),
          if (_retrying)
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新处理'),
            ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3: 重写 `build` 方法**

```dart
@override
Widget build(BuildContext context) {
  final audioPath = _storageService.getAudioPath(
      widget.entry.folderPath, widget.entry.audioFormat);

  return Scaffold(
    appBar: AppBar(
      title: AppTitle.wrap(Text(widget.entry.displayTitle)),
      actions: [
        IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteDiary),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 元信息行
                Text(
                  '${widget.entry.formattedDate}  ${widget.entry.durationDisplay}${widget.entry.weatherDisplay.isNotEmpty ? '  ${widget.entry.weatherDisplay}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // 标签行
                if (!_hasLlm)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('⏳ 处理中...',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  )
                else if (_tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ..._tags.map((tag) => Chip(
                              label: Text(tag.name,
                                  style: const TextStyle(fontSize: 12)),
                              onDeleted: () async {
                                await _storageService.removeDiaryTag(
                                    widget.entry.id, tag.id);
                                final updatedTag =
                                    await _storageService.getTagById(tag.id);
                                if (mounted) {
                                  await showTagEditorSheet(context,
                                      tag: updatedTag, isRemoval: true);
                                  _loadTags();
                                }
                              },
                              deleteIconColor: Colors.grey,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            )),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: const Text('标签',
                              style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            final selectedIds = await showTagSelectorSheet(
                              context,
                              selectedTagIds:
                                  _tags.map((t) => t.id).toList(),
                            );
                            if (selectedIds != null && mounted) {
                              final currentIds =
                                  _tags.map((t) => t.id).toSet();
                              final newIds = selectedIds.toSet();
                              for (final id
                                  in newIds.difference(currentIds)) {
                                await _storageService.addDiaryTag(
                                    widget.entry.id, id);
                                final tag = await _storageService
                                    .getTagById(id);
                                if (mounted) {
                                  await showTagEditorSheet(context,
                                      tag: tag, isRemoval: false);
                                }
                              }
                              for (final id
                                  in currentIds.difference(newIds)) {
                                await _storageService.removeDiaryTag(
                                    widget.entry.id, id);
                                final tag = await _storageService
                                    .getTagById(id);
                                if (mounted) {
                                  await showTagEditorSheet(context,
                                      tag: tag, isRemoval: true);
                                }
                              }
                              _loadTags();
                            }
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // 音频播放器
                if (_audioExists)
                  AudioPlayerBar(
                      playerService: _playerService,
                      audioFilePath: audioPath),
                const SizedBox(height: 16),
                // 处理状态横幅
                _buildStatusBanner(),
                const SizedBox(height: 16),
                // 内容区域（渐进展示）
                if (_transcriptExists)
                  ExpansionTile(
                    title: const Text('原始识别文本'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _transcriptData?.fullText ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                if (_hasLlm) ...[
                  if (_summaryUtterances.isNotEmpty)
                    TimestampedTextView(
                      utterances: _summaryUtterances,
                      playerService: _playerService,
                    )
                  else
                    MarkdownBody(data: _summary),
                  ExpansionTile(
                    title: const Text('润色正文'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: MarkdownBody(data: _content),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
  );
}
```

- [ ] **Step 4: 更新 `_retry` 方法**

重试后不再设置 `_needsRetry`，而是直接重新加载：

```dart
Future<void> _retry() async {
  setState(() => _retrying = true);

  try {
    final audioPath = _storageService.getAudioPath(
        widget.entry.folderPath, widget.entry.audioFormat);
    final transcriptPath =
        p.join(widget.entry.folderPath, 'transcript.json');
    final transcriptExists = File(transcriptPath).existsSync();

    List<Utterance> utterances;

    if (!transcriptExists) {
      // 无转写：尝试同步 ASR（直接用本地音频）
      final asrResult = await _asrService.transcribe(audioPath);
      await _storageService.writeTranscriptJson(widget.entry.folderPath,
          TranscriptData(version: 1, utterances: asrResult.utterances));
      utterances = asrResult.utterances;
    } else {
      final transcriptData =
          await _storageService.readTranscriptJson(widget.entry.folderPath);
      utterances = transcriptData.utterances;
    }

    final llmResult = await _llmService.summarize(utterances);
    await _storageService.writeLlmResult(
        widget.entry.folderPath,
        LlmResultData(
          version: 1,
          title: llmResult.title,
          content: llmResult.content,
          summary: llmResult.summary,
          outline: llmResult.outline,
          utterances: llmResult.utterances,
        ));

    await _storageService.updateTitle(widget.entry.id, llmResult.title);

    // 自动打 tag
    try {
      final allTags = await _storageService.getAllTags();
      final tagsWithPrompt =
          allTags.where((t) => t.matchPrompt.isNotEmpty).toList();
      if (tagsWithPrompt.isNotEmpty) {
        final tagInfos = tagsWithPrompt
            .map((t) => TagInfo(
                id: t.id, name: t.name, matchPrompt: t.matchPrompt))
            .toList();
        final matchedTagIds =
            await _llmService.matchTags(llmResult.content, tagInfos);
        if (matchedTagIds.isNotEmpty) {
          await _storageService.autoTagDiary(
              widget.entry.id, matchedTagIds);
        }
      }
    } catch (e) {
      debugPrint('[重试] 自动归类失败（不阻塞）: $e');
    }

    setState(() {
      _retrying = false;
      _loading = true;
    });
    await _loadContent();
  } catch (e) {
    if (mounted) {
      setState(() => _retrying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重试失败: $e')),
      );
    }
  }
}
```

- [ ] **Step 5: 删除旧的 `_buildRetryView` 方法**

整个 `_buildRetryView` 方法已不再需要，删除。

- [ ] **Step 6: 代码分析**

Run: `flutter analyze lib/pages/diary_detail_page.dart`
Expected: No issues found

- [ ] **Step 7: 提交**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "feat: 详情页渐进展示 + 状态横幅 + FGS 监听自动刷新"
```

---

### Task 4: 清理列表页废弃的重试入口

**Files:**
- Modify: `lib/pages/diary_list_page.dart`

- [ ] **Step 1: 移除 `_retryEntry` 方法和无用 import**

`_retryEntry` 方法不再被 `_buildEntryCard` 调用（重试已移入详情页）。删除 `_retryEntry` 方法。

同时移除不再使用的 import：
```dart
// 移除这行（如果不再被其他代码引用）：
import '../services/recording_processor.dart' show processingCallback;
```

检查 `_onTaskData` 是否仍需要 `FlutterForegroundTask` — 是的，它监听 `completed`/`failed` 消息刷新列表，保留。

- [ ] **Step 2: 代码分析**

Run: `flutter analyze lib/pages/diary_list_page.dart`
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add lib/pages/diary_list_page.dart
git commit -m "refactor: 移除列表页重试入口，重试已移入详情页"
```

---

### Task 5: 真机端到端验证

**Files:** 无代码改动

- [ ] **Step 1: 部署到真机**

Run: `flutter run --flavor prod -d d7c69821`

- [ ] **Step 2: 测试 processing 状态**

1. 录音 → 停止 → 立即点击列表中的条目
2. 预期：进入详情页，显示音频播放器 + processing 横幅 + 「⏳ 处理中...」标签占位
3. 等待处理完成
4. 预期：详情页自动刷新，横幅消失，转写文本和 LLM 内容渐次出现

- [ ] **Step 3: 测试 completed 状态**

1. 点击已完成条目
2. 预期：与现有行为一致，完整展示所有内容

- [ ] **Step 4: 测试 failed 状态**

1. 如有 failed 条目，点击进入
2. 预期：显示失败横幅 + 重新处理按钮 + 已有的音频/转写内容
3. 点击重新处理
4. 预期：切换为 processing 展示，完成后自动刷新

- [ ] **Step 5: 最终提交**

```bash
git push origin bugfix/lock-screen
```

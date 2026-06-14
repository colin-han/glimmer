# 日记详情页重构 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重新设计日记详情页布局，拆分为信息栏、播放器区域（带字幕同步）、润色正文三个独立子组件，移除「原始识别文本」展示。

**Architecture:** 新建 `lib/widgets/detail/` 目录存放三个子组件。`DetailInfoBar` 展示元信息，`DetailPlayerSection` 封装播放器 + 字幕同步 + 展开文本，`DetailContentSection` 展示润色正文 + 复制。详情页作为组装层加载数据并传递给子组件。

**Tech Stack:** Flutter, just_audio, flutter_markdown, flutter_foreground_task

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/widgets/detail/detail_info_bar.dart` | Create | 信息栏：日期/时间/时长/位置/天气/温度 |
| `lib/widgets/detail/detail_player_section.dart` | Create | 播放器 + 字幕行 + 展开文本 + 复制 |
| `lib/widgets/detail/detail_content_section.dart` | Create | 润色正文 + 复制按钮 |
| `lib/pages/diary_detail_page.dart` | Modify | 组装层：加载数据、传递 props、标签行、状态横幅 |

---

### Task 1: 创建 DetailInfoBar 组件

**Files:**
- Create: `lib/widgets/detail/detail_info_bar.dart`

- [ ] **Step 1: 创建目录并编写 DetailInfoBar**

```dart
import 'package:flutter/material.dart';

import '../../models/diary_entry.dart';

class DetailInfoBar extends StatelessWidget {
  final DiaryEntry entry;

  const DetailInfoBar({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final parts = <Widget>[];

    // 日期 + 时间
    parts.add(Text('${entry.formattedDate}', style: style));

    // 时长
    parts.add(Text('⏰${entry.durationDisplay}', style: style));

    // 位置
    if (entry.locationName != null && entry.locationName!.isNotEmpty) {
      parts.add(Text('📍${entry.locationName}', style: style));
    }

    // 天气
    if (entry.weatherIcon != null || entry.weatherText != null) {
      final emoji = entry.weatherIcon != null
          ? (DiaryEntry.weatherEmoji(entry.weatherIcon!) ?? entry.weatherText ?? '')
          : entry.weatherText ?? '';
      if (emoji.isNotEmpty) {
        parts.add(Text(emoji, style: style));
      }
    }

    // 温度
    if (entry.temperature != null && entry.temperature!.isNotEmpty) {
      parts.add(Text('🌡️${entry.temperature}°C', style: style));
    }

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }
}
```

- [ ] **Step 2: 代码分析**

Run: `flutter analyze lib/widgets/detail/detail_info_bar.dart`
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/detail/detail_info_bar.dart
git commit -m "feat: 创建 DetailInfoBar 信息栏组件"
```

---

### Task 2: 创建 DetailContentSection 组件

**Files:**
- Create: `lib/widgets/detail/detail_content_section.dart`

- [ ] **Step 1: 编写 DetailContentSection**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DetailContentSection extends StatelessWidget {
  final String content;

  const DetailContentSection({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '润色正文',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 20),
              tooltip: '复制',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
        const Divider(),
        MarkdownBody(data: content),
      ],
    );
  }
}
```

- [ ] **Step 2: 代码分析**

Run: `flutter analyze lib/widgets/detail/detail_content_section.dart`
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/detail/detail_content_section.dart
git commit -m "feat: 创建 DetailContentSection 润色正文组件"
```

---

### Task 3: 创建 DetailPlayerSection 组件

**Files:**
- Create: `lib/widgets/detail/detail_player_section.dart`

这是最复杂的组件，包含播放器、字幕同步、展开文本和复制功能。

- [ ] **Step 1: 编写 DetailPlayerSection**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/utterance.dart';
import '../../services/audio_player_service.dart';
import '../audio_player_bar.dart';

class DetailPlayerSection extends StatefulWidget {
  final AudioPlayerService playerService;
  final String audioFilePath;
  final List<Utterance> utterances;
  final bool hasTranscript;

  const DetailPlayerSection({
    super.key,
    required this.playerService,
    required this.audioFilePath,
    required this.utterances,
    required this.hasTranscript,
  });

  @override
  State<DetailPlayerSection> createState() => _DetailPlayerSectionState();
}

class _DetailPlayerSectionState extends State<DetailPlayerSection> {
  Duration _position = Duration.zero;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.playerService.positionStream.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });
  }

  int get _currentIndex {
    if (widget.utterances.isEmpty) return -1;
    final posMs = _position.inMilliseconds;
    for (var i = 0; i < widget.utterances.length; i++) {
      final u = widget.utterances[i];
      if (posMs >= u.startTime && posMs < u.endTime) {
        return i;
      }
    }
    if (posMs >= widget.utterances.last.endTime) {
      return widget.utterances.length - 1;
    }
    return -1;
  }

  String get _currentText {
    final idx = _currentIndex;
    if (idx < 0 || idx >= widget.utterances.length) return '';
    return widget.utterances[idx].text;
  }

  String get _fullText =>
      widget.utterances.map((u) => u.text).join();

  void _copyFullText() {
    Clipboard.setData(ClipboardData(text: _fullText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUtterances = widget.hasTranscript && widget.utterances.isNotEmpty;

    return Column(
      children: [
        // 播放器
        AudioPlayerBar(
          playerService: widget.playerService,
          audioFilePath: widget.audioFilePath,
        ),
        if (hasUtterances) ...[
          const SizedBox(height: 8),
          // 字幕行（可点击跳转）
          if (_currentText.isNotEmpty)
            GestureDetector(
              onTap: () {
                final idx = _currentIndex;
                if (idx >= 0) {
                  widget.playerService.seek(
                    Duration(milliseconds: widget.utterances[idx].startTime),
                  );
                }
              },
              child: Text(
                _currentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 4),
          // 展开/收起按钮
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _expanded ? '收起识别文本' : '展开识别文本',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
          // 展开区域
          if (_expanded)
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: 8,
                      right: 32,
                    ),
                    child: _buildExpandedText(theme),
                  ),
                  // 右上角复制按钮
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: '复制',
                      onPressed: _copyFullText,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildExpandedText(ThemeData theme) {
    final currentIndex = _currentIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.utterances.length; i++)
          _buildSentence(
            widget.utterances[i],
            i == currentIndex,
            i < currentIndex,
            theme,
          ),
      ],
    );
  }

  Widget _buildSentence(
    Utterance utterance,
    bool isCurrent,
    bool isPlayed,
    ThemeData theme,
  ) {
    final Color textColor;
    final FontWeight fontWeight;

    if (isCurrent) {
      textColor = theme.colorScheme.primary;
      fontWeight = FontWeight.w600;
    } else if (isPlayed) {
      textColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
      fontWeight = FontWeight.normal;
    } else {
      textColor = theme.colorScheme.onSurface;
      fontWeight = FontWeight.normal;
    }

    return GestureDetector(
      onTap: () {
        widget.playerService
            .seek(Duration(milliseconds: utterance.startTime));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          utterance.text,
          style: TextStyle(
            fontSize: 14,
            color: textColor,
            fontWeight: fontWeight,
            height: 1.8,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 代码分析**

Run: `flutter analyze lib/widgets/detail/detail_player_section.dart`
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/detail/detail_player_section.dart
git commit -m "feat: 创建 DetailPlayerSection 播放器+字幕+展开文本组件"
```

---

### Task 4: 重构详情页组装层

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

这一步重写 `build()` 方法，用新组件替换旧布局，移除「原始识别文本」，调整数据传递逻辑。

- [ ] **Step 1: 更新 imports**

在 `diary_detail_page.dart` 顶部，添加新组件 import，移除不再需要的 import：

```dart
// 添加：
import '../widgets/detail/detail_info_bar.dart';
import '../widgets/detail/detail_player_section.dart';
import '../widgets/detail/detail_content_section.dart';

// 移除（不再直接使用）：
// import '../widgets/timestamped_text_view.dart';
```

- [ ] **Step 2: 在 _loadContent 中计算 utterances 优先级**

修改 `_loadContent()` 方法，新增 `_activeUtterances` 和 `_hasTranscript` 状态变量。

在状态变量区域添加：

```dart
List<Utterance> _activeUtterances = [];
bool _hasTranscript = false;
```

在 `_loadContent()` 中，加载完数据后、`setState` 之前，添加 utterances 优先级计算：

```dart
// utterances 优先级：LLM > Transcript
List<Utterance> activeUtterances = [];
final hasTranscript = transcriptExists || hasLlm;

if (hasLlm && summaryUtterances.isNotEmpty) {
  activeUtterances = summaryUtterances;
} else if (transcriptData != null) {
  activeUtterances = transcriptData.utterances;
}
```

在 `setState` 内添加：

```dart
_activeUtterances = activeUtterances;
_hasTranscript = hasTranscript;
```

- [ ] **Step 3: 重写 build 方法**

替换整个 `build` 方法：

```dart
@override
Widget build(BuildContext context) {
  final audioPath = _storageService.getAudioPath(
      widget.entry.folderPath, widget.entry.audioFormat);

  return Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Flexible(
            child: Text(
              widget.entry.displayTitle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (AppTitle.isDev) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'dev',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
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
                // 信息栏
                DetailInfoBar(entry: widget.entry),
                // 标签行
                if (!_hasLlm)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('⏳ 处理中...',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
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
                // 播放器区域
                if (_audioExists)
                  DetailPlayerSection(
                    playerService: _playerService,
                    audioFilePath: audioPath,
                    utterances: _activeUtterances,
                    hasTranscript: _hasTranscript,
                  ),
                const SizedBox(height: 16),
                // 处理状态横幅
                _buildStatusBanner(),
                const SizedBox(height: 16),
                // 润色正文
                if (_hasLlm && _content.isNotEmpty)
                  DetailContentSection(content: _content),
              ],
            ),
          ),
  );
}
```

- [ ] **Step 4: 清理不再使用的变量和 import**

移除 `_summaryUtterances` 状态变量（已被 `_activeUtterances` 替代）。
移除 `_summary` 状态变量（不再直接渲染）。
移除 `_transcriptData` 状态变量（不再直接使用；utterances 已在 `_loadContent` 中提取）。
移除 `import '../widgets/timestamped_text_view.dart'`（不再直接使用）。
移除 `import 'package:flutter_markdown/flutter_markdown.dart'`（已移入 `DetailContentSection`）。

注意：`_loadContent` 中仍需读取 `summaryUtterances`（LLM utterances）和 `transcriptData.utterances`（ASR utterances）用于优先级计算，但不再需要存储到成员变量。

修改后的 `_loadContent` 方法：

```dart
Future<void> _loadContent() async {
  final audioPath = _storageService.getAudioPath(
      widget.entry.folderPath, widget.entry.audioFormat);
  final audioExists = File(audioPath).existsSync();
  final transcriptExists =
      await File(p.join(widget.entry.folderPath, 'transcript.json'))
          .exists();
  final hasLlm = await _storageService.hasLlmResult(widget.entry.folderPath);

  TranscriptData? transcriptData;
  if (transcriptExists) {
    try {
      transcriptData =
          await _storageService.readTranscriptJson(widget.entry.folderPath);
    } catch (_) {}
  }

  String content = '';
  List<Utterance> summaryUtterances = [];

  if (hasLlm) {
    final llmData =
        await _storageService.readLlmResult(widget.entry.folderPath);
    content = llmData.content;
    summaryUtterances = llmData.utterances;
  }

  // utterances 优先级：LLM > Transcript
  List<Utterance> activeUtterances = [];
  final hasTranscript = transcriptExists || hasLlm;

  if (hasLlm && summaryUtterances.isNotEmpty) {
    activeUtterances = summaryUtterances;
  } else if (transcriptData != null) {
    activeUtterances = transcriptData.utterances;
  }

  if (mounted) {
    setState(() {
      _audioExists = audioExists;
      _transcriptExists = transcriptExists;
      _hasLlm = hasLlm;
      _content = content;
      _activeUtterances = activeUtterances;
      _hasTranscript = hasTranscript;
      _loading = false;
    });
  }
  _loadTags();
}
```

同步移除 `_speakSummary` 方法及其调用（`autoPlaySummary` 参数保留在构造函数中以防列表页调用方报错，但方法体清空）。

- [ ] **Step 5: 代码分析**

Run: `flutter analyze lib/pages/diary_detail_page.dart`
Expected: No issues found

- [ ] **Step 6: 提交**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "feat: 详情页重构为新布局，使用独立子组件组装"
```

---

### Task 5: 全局代码分析 + 清理

**Files:** 无新增

- [ ] **Step 1: 全项目代码分析**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 2: 检查 TimestampedTextView 是否仍被其他文件引用**

Run: `grep -r 'TimestampedTextView' lib/`
如果只在 `timestamped_text_view.dart` 自身定义处出现（详情页已移除引用），说明该组件不再被使用。不删除文件，但确认无残留引用。

- [ ] **Step 3: 提交（如有清理改动）**

```bash
git add -A
git commit -m "refactor: 清理详情页重构后的残留引用"
```

---

### Task 6: 真机验证

**Files:** 无代码改动

- [ ] **Step 1: 部署到真机**

Run: `./run_dev.sh`

- [ ] **Step 2: 测试已完成条目**

1. 点击一条已完成的日记
2. 验证：信息栏显示日期/时间/时长/位置/天气
3. 验证：播放器正常播放，字幕行同步显示当前句
4. 验证：点击展开/收起，文本区域显示正确，当前句高亮
5. 验证：点击复制按钮，剪贴板内容正确
6. 验证：润色正文区域显示 Markdown 渲染内容
7. 验证：润色正文复制按钮正常工作

- [ ] **Step 3: 测试处理中条目**

1. 录音 → 停止 → 立即点击列表中的条目
2. 验证：信息栏显示，播放器可用，无字幕/展开按钮
3. 验证：处理中横幅显示
4. 等待处理完成
5. 验证：详情页自动刷新，字幕和展开区域出现

- [ ] **Step 4: 测试失败条目**

1. 如有 failed 条目，点击进入
2. 验证：失败横幅 + 重新处理按钮
3. 点击重新处理
4. 验证：处理后自动刷新

- [ ] **Step 5: 推送**

```bash
git push origin bugfix/lock-screen
```

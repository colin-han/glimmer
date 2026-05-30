# LLM 四段输出改造 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 LLM 输出从 3 字段（title/content/oneLineSummary）扩展为 4 字段（title/content/summary/outline），用 JSON 文件存储替换 summary.md，调整详情页展示和 TTS 播报。

**Architecture:** LLM 一次调用返回 title + content（润色正文）+ summary（日记体提炼）+ outline（口语化播报文本）+ utterances（时间戳）。存储从 summary.md 切换到 llm_result.json。详情页以 summary 为主视图，content 折叠。TTS 直接播报 outline，废弃二次 LLM 调用。

**Tech Stack:** Dart/Flutter, drift, dio, flutter_markdown

**Design Doc:** `docs/superpowers/specs/2026-05-30-llm-four-part-output-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/models/utterance.dart` | 修改 | 新增 `LlmResultData` 模型类 |
| `lib/services/llm_service.dart` | 修改 | LlmResult 改 4 字段，提示词重写，删除 `generateSummaryAnnouncement` |
| `lib/services/diary_storage_service.dart` | 修改 | 新增 `writeLlmResult`/`readLlmResult`，废弃 `writeSummary`/`readSummary`/`writeSummaryUtterances`/`readSummaryUtterances` |
| `lib/pages/recording_page.dart` | 修改 | 存储调用改为 `writeLlmResult`，TTS 播报用 `outline` 替换 `oneLineSummary` |
| `lib/pages/diary_detail_page.dart` | 修改 | 读取 `llm_result.json`，summary 为主视图，content 折叠，向后兼容 `summary.md` |

---

### Task 1: 新增 LlmResultData 模型类

**Files:**
- Modify: `lib/models/utterance.dart`

- [ ] **Step 1: 在 utterance.dart 末尾添加 LlmResultData 类**

在 `SummaryUtteranceData` 类后面追加：

```dart
class LlmResultData {
  final int version;
  final String title;
  final String content;
  final String summary;
  final String outline;
  final List<Utterance> utterances;

  const LlmResultData({
    required this.version,
    required this.title,
    required this.content,
    required this.summary,
    required this.outline,
    required this.utterances,
  });

  factory LlmResultData.fromJson(Map<String, dynamic> json) {
    return LlmResultData(
      version: json['version'] as int,
      title: json['title'] as String,
      content: json['content'] as String,
      summary: json['summary'] as String,
      outline: json['outline'] as String,
      utterances: (json['utterances'] as List)
          .map((u) => Utterance.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'title': title,
        'content': content,
        'summary': summary,
        'outline': outline,
        'utterances': utterances.map((u) => u.toJson()).toList(),
      };
}
```

- [ ] **Step 2: 运行 flutter analyze 验证**

Run: `flutter analyze lib/models/utterance.dart`
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/models/utterance.dart
git commit -m "feat: 添加 LlmResultData 模型类用于 JSON 存储"
```

---

### Task 2: 改造 LlmService — LlmResult 和提示词

**Files:**
- Modify: `lib/services/llm_service.dart`

- [ ] **Step 1: 修改 LlmResult 类**

将 `LlmResult` 类（第 8-19 行）替换为：

```dart
class LlmResult {
  final String title;
  final String content;
  final String summary;
  final String outline;
  final List<Utterance> utterances;

  LlmResult({
    required this.title,
    required this.content,
    required this.summary,
    required this.outline,
    required this.utterances,
  });
}
```

- [ ] **Step 2: 重写 summarize 方法的 system prompt**

将 `summarize` 方法中的 system prompt（第 41-59 行）替换为：

```dart
'你是一个日记助手。用户会给你一段语音识别的口语文本（带时间戳），请完成以下四项任务：\n'
'\n'
'1. **润色正文（content）**：按以下规则整理为 Markdown 格式日记正文：\n'
'   - 最大程度保留原文的句子结构和用词，不添加、不删除实质内容\n'
'   - 仅删除无意义的口语填充词（嗯、啊、那个、就是说、然后呢等）\n'
'   - 消除重复、结巴、停顿导致的不通顺\n'
'   - 按语义自然分段（话题转换、时间线变化处分段）\n'
'   - 适当将口语化词汇替换为书面表达（如觉得→认为、挺→很），保持自然\n'
'\n'
'2. **日记体提炼（summary）**：以第一人称「我」的视角，写一篇精炼版日记（Markdown 格式）：\n'
'   - 保留原文中的情感、感受、思考\n'
'   - 合并相似内容，省略无关紧要的细节\n'
'   - 自然流畅，300-500字，不要分条列举\n'
'\n'
'3. **口语化播报（outline）**：生成一段完整的口语化播报文本：\n'
'   - 提炼最重要的前5个主题或事件\n'
'   - 如果主题超过5个，末尾补充「还有其他几条，就不一一念了」类的收尾\n'
'   - 口语化、适合 TTS 朗读，不要使用条目列表格式\n'
'   - 示例：「日记整理完成，今天讨论了很多事情：首先是工作上的项目进展；然后是关于周末旅行的计划；还提到了最近在读的一本书。此外还有一些其他内容，就不一一念了。」\n'
'\n'
'4. **标题（title）**：从内容中提炼简短标题，不超过20个字\n'
'\n'
'时间戳规则：\n'
'- 每个片段都有 startTime 和 endTime（毫秒），润色正文时必须保留\n'
'- 合并多个片段时，取第一个的 startTime 和最后一个的 endTime\n'
'- 不要拆分任何片段的时间戳\n'
'\n'
'严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
'{"title": "标题", "content": "润色正文(Markdown)", "summary": "日记体提炼(Markdown)", '
'"outline": "口语化播报文本", '
'"utterances": [{"text": "润色后文本", "startTime": 0, "endTime": 1000}]}'
```

- [ ] **Step 3: 修改 _parseResult 方法**

将 `_parseResult` 方法（第 139-167 行）替换为：

```dart
LlmResult _parseResult(String content) {
  try {
    final cleaned = content
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
    final json = jsonDecode(cleaned) as Map<String, dynamic>;

    final utterancesList = json['utterances'] as List<dynamic>?;
    final utterances = utterancesList
            ?.map((u) => Utterance.fromJson(u as Map<String, dynamic>))
            .toList() ??
        [];

    return LlmResult(
      title: json['title'] as String? ?? '未命名日记',
      content: json['content'] as String? ?? content,
      summary: json['summary'] as String? ?? '',
      outline: json['outline'] as String? ?? '',
      utterances: utterances,
    );
  } catch (_) {
    return LlmResult(
      title: _extractTitle(content),
      content: content,
      summary: '',
      outline: '',
      utterances: [],
    );
  }
}
```

- [ ] **Step 4: 删除 generateSummaryAnnouncement 方法**

删除 `generateSummaryAnnouncement` 方法（第 108-137 行），该方法不再需要。

- [ ] **Step 5: 运行 flutter analyze 验证**

Run: `flutter analyze lib/services/llm_service.dart`
Expected: 无错误（会有其他文件引用旧字段的警告，后续 Task 修复）

- [ ] **Step 6: 提交**

```bash
git add lib/services/llm_service.dart
git commit -m "feat: LLM 输出改为四段式（title/content/summary/outline）"
```

---

### Task 3: 改造 DiaryStorageService — JSON 存储

**Files:**
- Modify: `lib/services/diary_storage_service.dart`

- [ ] **Step 1: 新增 writeLlmResult 和 readLlmResult 方法**

在 `readSummaryUtterances` 方法后（第 79 行），替换 `// --- 查询 ---` 注释之前，添加：

```dart
// --- llm_result.json ---

Future<void> writeLlmResult(String folderPath, LlmResultData data) async {
  final file = File(p.join(folderPath, 'llm_result.json'));
  await file.writeAsString(jsonEncode(data.toJson()));
}

Future<LlmResultData> readLlmResult(String folderPath) async {
  final file = File(p.join(folderPath, 'llm_result.json'));
  final content = await file.readAsString();
  return LlmResultData.fromJson(
      jsonDecode(content) as Map<String, dynamic>);
}

/// 检查 llm_result.json 是否存在（用于向后兼容判断）
Future<bool> hasLlmResult(String folderPath) async {
  final file = File(p.join(folderPath, 'llm_result.json'));
  return file.exists();
}
```

- [ ] **Step 2: 添加 import**

确认文件顶部已有 `import '../models/utterance.dart';`（第 8 行已有，无需改动）。

- [ ] **Step 3: 运行 flutter analyze 验证**

Run: `flutter analyze lib/services/diary_storage_service.dart`
Expected: 无错误

- [ ] **Step 4: 提交**

```bash
git add lib/services/diary_storage_service.dart
git commit -m "feat: DiaryStorageService 新增 llm_result.json 读写方法"
```

---

### Task 4: 改造 RecordingPage — 存储和 TTS

**Files:**
- Modify: `lib/pages/recording_page.dart`

- [ ] **Step 1: 修改 _stopAndProcess 中的存储逻辑**

将第 187-192 行的存储调用：

```dart
await _storageService.writeSummary(
    _currentFolderPath!, llmResult.content);
await _storageService.writeSummaryUtterances(
    _currentFolderPath!,
    SummaryUtteranceData(
        version: 1, utterances: llmResult.utterances));
```

替换为：

```dart
await _storageService.writeLlmResult(
    _currentFolderPath!,
    LlmResultData(
      version: 1,
      title: llmResult.title,
      content: llmResult.content,
      summary: llmResult.summary,
      outline: llmResult.outline,
      utterances: llmResult.utterances,
    ));
```

- [ ] **Step 2: 修改 TTS 播报调用**

将第 208 行：

```dart
_speakSummary(llmResult.oneLineSummary);
```

替换为：

```dart
_speakSummary(llmResult.outline);
```

- [ ] **Step 3: 修改 _speakSummary 方法**

将 `_speakSummary` 方法（第 257-269 行）替换为：

```dart
void _speakSummary(String outline) {
  if (outline.isEmpty) return;
  debugPrint('[播报] 触发点2 开始: text="$outline"');
  () async {
    try {
      await _ttsService.speak(outline, VoiceType.maleDeep);
      debugPrint('[播报] 触发点2 完成');
    } catch (e) {
      debugPrint('TTS 总结播报失败: $e');
    }
  }();
}
```

- [ ] **Step 4: 运行 flutter analyze 验证**

Run: `flutter analyze lib/pages/recording_page.dart`
Expected: 无错误

- [ ] **Step 5: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "feat: RecordingPage 改用 llm_result.json 存储和 outline 播报"
```

---

### Task 5: 改造 DiaryDetailPage — 展示逻辑和向后兼容

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: 修改状态变量**

将状态变量（第 27-30 行）：

```dart
String _summary = '';
List<Utterance> _summaryUtterances = [];
TranscriptData? _transcriptData;
bool _loading = true;
```

替换为：

```dart
String _summary = '';
String _content = '';
List<Utterance> _summaryUtterances = [];
TranscriptData? _transcriptData;
bool _loading = true;
```

- [ ] **Step 2: 重写 _loadContent 方法**

将 `_loadContent` 方法（第 38-61 行）替换为：

```dart
Future<void> _loadContent() async {
  final transcriptData =
      await _storageService.readTranscriptJson(widget.entry.folderPath);

  String summary = '';
  String content = '';
  List<Utterance> summaryUtterances = [];

  if (await _storageService.hasLlmResult(widget.entry.folderPath)) {
    // 新格式：llm_result.json
    final llmData =
        await _storageService.readLlmResult(widget.entry.folderPath);
    summary = llmData.summary.isNotEmpty
        ? llmData.summary
        : llmData.content;
    content = llmData.content;
    summaryUtterances = llmData.utterances;
  } else {
    // 向后兼容：旧格式 summary.md
    try {
      summary = await _storageService.readSummary(widget.entry.folderPath);
    } catch (_) {
      summary = '';
    }
    content = summary;
    try {
      final summaryData = await _storageService
          .readSummaryUtterances(widget.entry.folderPath);
      summaryUtterances = summaryData.utterances;
    } catch (_) {}
  }

  if (mounted) {
    setState(() {
      _summary = summary;
      _content = content;
      _summaryUtterances = summaryUtterances;
      _transcriptData = transcriptData;
      _loading = false;
    });
  }
}
```

- [ ] **Step 3: 修改 build 方法中的展示逻辑**

将 build 方法中（第 127-147 行）：

```dart
if (audioExists && _summaryUtterances.isNotEmpty)
  TimestampedTextView(
    utterances: _summaryUtterances,
    playerService: _playerService,
  )
else
  MarkdownBody(data: _summary),
const SizedBox(height: 24),
ExpansionTile(
  title: const Text('原始识别文本'),
```

替换为：

```dart
if (audioExists && _summaryUtterances.isNotEmpty)
  TimestampedTextView(
    utterances: _summaryUtterances,
    playerService: _playerService,
  )
else
  MarkdownBody(data: _summary),
const SizedBox(height: 24),
ExpansionTile(
  title: const Text('润色正文'),
  children: [
    Padding(
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(data: _content),
    ),
  ],
),
ExpansionTile(
  title: const Text('原始识别文本'),
```

- [ ] **Step 4: 运行 flutter analyze 验证**

Run: `flutter analyze lib/pages/diary_detail_page.dart`
Expected: 无错误

- [ ] **Step 5: 提交**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "feat: 详情页以 summary 为主视图，content 折叠，兼容旧格式"
```

---

### Task 6: 全局验证

- [ ] **Step 1: 运行 flutter analyze 全量检查**

Run: `flutter analyze`
Expected: 无错误

- [ ] **Step 2: 运行 flutter test（如有测试）**

Run: `flutter test`
Expected: 全部通过

- [ ] **Step 3: 确认无残留的旧字段引用**

Run: `grep -rn "oneLineSummary" lib/`
Expected: 无结果

Run: `grep -rn "generateSummaryAnnouncement" lib/`
Expected: 无结果

- [ ] **Step 4: 最终提交（如有 lint 修复）**

```bash
git add -A
git commit -m "chore: 四段输出改造全局验证通过"
```

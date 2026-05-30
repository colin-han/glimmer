# 带时间戳语音识别与播放同步 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ASR 返回句子级时间戳，LLM 润色保留时间戳，播放录音时同步高亮对应文字。

**Architecture:** Flash ASR 请求加 `show_utterances` 参数获取时间戳。新增 `Utterance` 数据模型贯穿 ASR→存储→LLM→UI 全链路。系统级存储版本管理，0→1 migration 清除旧数据。播放页监听 positionStream 做句子级高亮同步。

**Tech Stack:** Flutter, Dart, drift (SQLite), just_audio, shared_preferences, dio

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| 新建 | `lib/models/utterance.dart` | `Utterance` 数据模型 + `TranscriptData` / `SummaryUtteranceData` |
| 修改 | `lib/services/asr_service.dart` | 加 `show_utterances`，返回 `AsrResult` 替代 `String` |
| 修改 | `lib/services/llm_service.dart` | 输入 utterances，输出带 utterances 的 `LlmResult` |
| 修改 | `lib/services/diary_storage_service.dart` | 新增 JSON 读写方法，移除 txt 方法 |
| 修改 | `lib/main.dart` | 启动时运行 migration |
| 新建 | `lib/services/storage_migration_service.dart` | 存储版本管理与 migration |
| 修改 | `lib/pages/recording_page.dart` | 适配新的 ASR/LLM/存储接口 |
| 修改 | `lib/pages/diary_detail_page.dart` | 加载 utterances，播放同步 UI |
| 新建 | `lib/widgets/timestamped_text_view.dart` | 句子级同步高亮组件 |

---

### Task 1: 数据模型 — Utterance

**Files:**
- Create: `lib/models/utterance.dart`

- [ ] **Step 1: 创建 Utterance 数据模型**

```dart
class Utterance {
  final String text;
  final int startTime;
  final int endTime;

  const Utterance({
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  factory Utterance.fromJson(Map<String, dynamic> json) {
    return Utterance(
      text: json['text'] as String,
      startTime: json['startTime'] as int,
      endTime: json['endTime'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'startTime': startTime,
        'endTime': endTime,
      };
}

class TranscriptData {
  final int version;
  final List<Utterance> utterances;

  const TranscriptData({required this.version, required this.utterances});

  String get fullText => utterances.map((u) => u.text).join();

  factory TranscriptData.fromJson(Map<String, dynamic> json) {
    return TranscriptData(
      version: json['version'] as int,
      utterances: (json['utterances'] as List)
          .map((u) => Utterance.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'utterances': utterances.map((u) => u.toJson()).toList(),
      };
}

class SummaryUtteranceData {
  final int version;
  final List<Utterance> utterances;

  const SummaryUtteranceData({required this.version, required this.utterances});

  factory SummaryUtteranceData.fromJson(Map<String, dynamic> json) {
    return SummaryUtteranceData(
      version: json['version'] as int,
      utterances: (json['utterances'] as List)
          .map((u) => Utterance.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'utterances': utterances.map((u) => u.toJson()).toList(),
      };
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/models/utterance.dart
git commit -m "feat: 添加 Utterance 数据模型及 TranscriptData/SummaryUtteranceData"
```

---

### Task 2: 存储版本管理与 Migration

**Files:**
- Create: `lib/services/storage_migration_service.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: 添加 shared_preferences 依赖**

Run: `flutter pub add shared_preferences`

- [ ] **Step 2: 创建 StorageMigrationService**

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageMigrationService {
  static const _versionKey = 'storage_version';
  static const _currentVersion = 1;

  Future<void> runMigrations() async {
    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getInt(_versionKey) ?? 0;

    if (currentVersion >= _currentVersion) return;

    for (var v = currentVersion + 1; v <= _currentVersion; v++) {
      await _runMigration(v);
    }

    await prefs.setInt(_versionKey, _currentVersion);
  }

  Future<void> _runMigration(int version) async {
    switch (version) {
      case 1:
        await _migrateV0ToV1();
        break;
    }
  }

  Future<void> _migrateV0ToV1() async {
    // 清除所有现有日记数据
    final docDir = await getApplicationDocumentsDirectory();
    final diariesDir = Directory(p.join(docDir.path, 'diaries'));
    if (await diariesDir.exists()) {
      await diariesDir.delete(recursive: true);
    }

    // 清除数据库
    final dbFile = File(p.join(docDir.path, 'voice_diary.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  }
}
```

- [ ] **Step 3: 修改 main.dart 启动时运行 migration**

在 `main.dart` 中 `await dotenv.load(...)` 之后、`runApp` 之前，加入：

```dart
import 'services/storage_migration_service.dart';

// 在 main() 中：
final migrationService = StorageMigrationService();
await migrationService.runMigrations();
```

完整的 `main()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');
  final migrationService = StorageMigrationService();
  await migrationService.runMigrations();
  runApp(const VoiceDiaryApp());
}
```

- [ ] **Step 4: 提交**

```bash
git add pubspec.yaml pubspec.lock lib/services/storage_migration_service.dart lib/main.dart
git commit -m "feat: 添加系统存储版本管理，0→1 migration 清除旧数据"
```

---

### Task 3: ASR 服务 — 返回带时间戳的结果

**Files:**
- Modify: `lib/services/asr_service.dart`

- [ ] **Step 1: 修改 AsrService**

将 `transcribe` 返回类型从 `String` 改为 `AsrResult`，请求中加 `show_utterances: true`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

import '../models/utterance.dart';

class AsrResult {
  final String text;
  final List<Utterance> utterances;

  const AsrResult({required this.text, required this.utterances});
}

class AsrService {
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  Future<AsrResult> transcribe(String audioFilePath) async {
    final appid = dotenv.get('VOLCENGINE_SPEECH_APPID');
    final token = dotenv.get('VOLCENGINE_SPEECH_TOKEN');

    final audioBytes = await File(audioFilePath).readAsBytes();
    final audioBase64 = base64Encode(audioBytes);

    final requestId = _uuid.v4();

    final response = await _dio.post(
      'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash',
      data: {
        'user': {'uid': appid},
        'audio': {
          'data': audioBase64,
          'format': 'wav',
        },
        'request': {
          'model_name': 'bigmodel',
          'show_utterances': true,
        },
      },
      options: Options(headers: {
        'X-Api-App-Key': appid,
        'X-Api-Access-Key': token,
        'X-Api-Resource-Id': 'volc.bigasr.auc_turbo',
        'X-Api-Request-Id': requestId,
        'X-Api-Sequence': '-1',
      }),
    );

    final statusCode = response.headers.value('X-Api-Status-Code');
    if (statusCode != '20000000') {
      final message = response.headers.value('X-Api-Message') ?? '未知错误';
      throw Exception('ASR 识别失败 ($statusCode): $message');
    }

    final result = response.data['result'] as Map<String, dynamic>?;
    if (result == null) {
      throw Exception('ASR 识别结果为空');
    }

    final text = result['text'] as String? ?? '';
    if (text.isEmpty) {
      throw Exception('ASR 识别结果为空');
    }

    final utterancesList = result['utterances'] as List<dynamic>?;
    if (utterancesList == null || utterancesList.isEmpty) {
      throw Exception('ASR 未返回 utterances 数据，需要切换到录音文件识别 API');
    }

    final utterances = utterancesList
        .map((u) => Utterance(
              text: u['text'] as String,
              startTime: u['start_time'] as int,
              endTime: u['end_time'] as int,
            ))
        .toList();

    return AsrResult(text: text, utterances: utterances);
  }
}
```

注意：火山引擎 API 返回的字段名是 `start_time` / `end_time`，我们的模型用 `startTime` / `endTime`（camelCase），在 `fromJson` / ASR 解析处做映射。

- [ ] **Step 2: 提交**

```bash
git add lib/services/asr_service.dart
git commit -m "feat: ASR 服务返回带时间戳的 AsrResult，加 show_utterances 参数"
```

---

### Task 4: 存储服务 — JSON 读写

**Files:**
- Modify: `lib/services/diary_storage_service.dart`

- [ ] **Step 1: 更新 DiaryStorageService**

移除 `writeTranscript` / `readTranscript`，新增 JSON 读写方法：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import 'database/app_database.dart' hide DiaryEntry;

class DiaryStorageService {
  final AppDatabase _db;

  DiaryStorageService() : _db = AppDatabase();

  Future<String> get _baseDir async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, 'diaries');
  }

  Future<String> createDiaryFolder(String id) async {
    final base = await _baseDir;
    final folder = Directory(p.join(base, id));
    await folder.create(recursive: true);
    return folder.path;
  }

  Future<void> createEntry(DiaryEntry entry) async {
    await _db.insertEntry(DiaryEntriesCompanion.insert(
      id: entry.id,
      title: entry.title,
      folderPath: entry.folderPath,
      durationSeconds: entry.durationSeconds,
      createdAt: entry.createdAt.millisecondsSinceEpoch,
    ));
  }

  // --- transcript.json ---

  Future<void> writeTranscriptJson(
      String folderPath, TranscriptData data) async {
    final file = File(p.join(folderPath, 'transcript.json'));
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  Future<TranscriptData> readTranscriptJson(String folderPath) async {
    final file = File(p.join(folderPath, 'transcript.json'));
    final content = await file.readAsString();
    return TranscriptData.fromJson(
        jsonDecode(content) as Map<String, dynamic>);
  }

  // --- summary.md ---

  Future<void> writeSummary(String folderPath, String content) async {
    final file = File(p.join(folderPath, 'summary.md'));
    await file.writeAsString(content);
  }

  Future<String> readSummary(String folderPath) async {
    final file = File(p.join(folderPath, 'summary.md'));
    return file.readAsString();
  }

  // --- summary_utterances.json ---

  Future<void> writeSummaryUtterances(
      String folderPath, SummaryUtteranceData data) async {
    final file = File(p.join(folderPath, 'summary_utterances.json'));
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  Future<SummaryUtteranceData> readSummaryUtterances(
      String folderPath) async {
    final file = File(p.join(folderPath, 'summary_utterances.json'));
    final content = await file.readAsString();
    return SummaryUtteranceData.fromJson(
        jsonDecode(content) as Map<String, dynamic>);
  }

  // --- 查询 ---

  Future<List<DiaryEntry>> getAllEntries() async {
    final rows = await _db.getAllEntries();
    return rows
        .map((r) => DiaryEntry(
              id: r.id,
              title: r.title,
              folderPath: r.folderPath,
              durationSeconds: r.durationSeconds,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ))
        .toList();
  }

  Future<DiaryEntry> getEntryById(String id) async {
    final r = await _db.getEntryById(id);
    return DiaryEntry(
      id: r.id,
      title: r.title,
      folderPath: r.folderPath,
      durationSeconds: r.durationSeconds,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    );
  }

  Future<void> deleteEntry(String id, String folderPath) async {
    await _db.deleteEntry(id);
    final folder = Directory(folderPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/diary_storage_service.dart
git commit -m "feat: 存储服务改为 JSON 读写，支持 transcript.json 和 summary_utterances.json"
```

---

### Task 5: LLM 服务 — 保留时间戳的润色

**Files:**
- Modify: `lib/services/llm_service.dart`

- [ ] **Step 1: 更新 LlmResult 和 summarize 方法**

`LlmResult` 新增 `utterances` 字段。`summarize` 输入改为 `List<Utterance>`，prompt 要求保留时间戳：

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/utterance.dart';

class LlmResult {
  final String title;
  final String content;
  final String oneLineSummary;
  final List<Utterance> utterances;

  LlmResult({
    required this.title,
    required this.content,
    required this.oneLineSummary,
    required this.utterances,
  });
}

class LlmService {
  final Dio _dio = Dio();

  Future<LlmResult> summarize(List<Utterance> utterances) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    // 将 utterances 格式化为带时间戳的文本给 LLM
    final utterancesJson = utterances
        .map((u) =>
            '{"text": "${u.text}", "startTime": ${u.startTime}, "endTime": ${u.endTime}}')
        .join('\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记助手。用户会给你一段语音识别的口语文本（带时间戳），'
                '请按以下规则整理为日记正文（Markdown 格式）：\n'
                '1. 最大程度保留原文的句子结构和用词，不添加、不删除实质内容\n'
                '2. 仅删除无意义的口语填充词（嗯、啊、那个、就是说、然后呢等）\n'
                '3. 消除重复、结巴、停顿导致的不通顺\n'
                '4. 按语义自然分段（话题转换、时间线变化处分段）\n'
                '5. 适当将口语化词汇替换为书面表达（如觉得→认为、挺→很），保持自然\n'
                '\n'
                '时间戳规则：\n'
                '- 每个片段都有 startTime 和 endTime（毫秒），润色文本时必须保留\n'
                '- 合并多个片段时，取第一个的 startTime 和最后一个的 endTime\n'
                '- 不要拆分任何片段的时间戳\n'
                '\n'
                '同时从内容中提炼一个简短标题（不超过 20 个字），'
                '以及一句话总结（不超过 30 个字）。'
                '严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
                '{"title": "标题", "content": "日记正文(Markdown)", '
                '"oneLineSummary": "一句话总结", '
                '"utterances": [{"text": "润色后文本", "startTime": 0, "endTime": 1000}]}',
          },
          {
            'role': 'user',
            'content': utterancesJson,
          },
        ],
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }),
    );

    final content =
        response.data['choices'][0]['message']['content'] as String;
    return _parseResult(content);
  }

  Future<String> generateReply(String realtimeText) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个温暖的日记助手。用户刚录完一段语音，'
                '你会根据他说的话，生成一句简短的回应（不超过 20 个字）。'
                '语气亲切温暖，就像朋友在回应。不要加引号或其他格式符号，只输出纯文本。',
          },
          {
            'role': 'user',
            'content': realtimeText,
          },
        ],
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }),
    );

    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<String> generateSummaryAnnouncement(String oneLineSummary) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记助手。用户今天的日记已经整理完成，'
                '一句话总结是：「$oneLineSummary」\n'
                '请生成一句播报文本（不超过 30 个字），告知用户日记整理完成并包含这个总结。'
                '语气沉稳专业。不要加引号或其他格式符号，只输出纯文本。',
          },
          {
            'role': 'user',
            'content': '请生成播报文本',
          },
        ],
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }),
    );

    return response.data['choices'][0]['message']['content'] as String;
  }

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
        oneLineSummary: json['oneLineSummary'] as String? ?? '',
        utterances: utterances,
      );
    } catch (_) {
      return LlmResult(
        title: _extractTitle(content),
        content: content,
        oneLineSummary: '',
        utterances: [],
      );
    }
  }

  String _extractTitle(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && trimmed.startsWith('#')) {
        return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      }
    }
    return content.length > 20
        ? '${content.substring(0, 20)}...'
        : content;
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/llm_service.dart
git commit -m "feat: LLM 润色保留时间戳，输入输出均为 utterances 结构"
```

---

### Task 6: 录音页面 — 适配新接口

**Files:**
- Modify: `lib/pages/recording_page.dart`

- [ ] **Step 1: 修改 `_stopAndProcess` 方法**

关键改动：
- `transcribe` 返回 `AsrResult` 而非 `String`
- `llmService.summarize` 输入 `List<Utterance>` 而非 `String`
- 存储 `transcript.json` 而非 `transcript.txt`
- 存储 `summary_utterances.json`

替换 `_stopAndProcess` 中步骤 1-3 的代码块：

```dart
    try {
      final sw = Stopwatch()..start();
      final recordingResult = await _recorderService.stopRecording();
      debugPrint('[流程] stopRecording 完成: ${sw.elapsedMilliseconds}ms');

      // TTS 触发点 1：甜美女声应答（固定模板，无需等 LLM）
      _speakReply();

      // 步骤 1: Flash ASR 识别（带时间戳）
      setState(() => _processingStep = 1);
      final asrResult =
          await _asrService.transcribe(recordingResult.filePath);
      final transcriptData = TranscriptData(
        version: 1,
        utterances: asrResult.utterances,
      );
      await _storageService.writeTranscriptJson(
          _currentFolderPath!, transcriptData);
      debugPrint('[流程] Flash ASR 完成: ${sw.elapsedMilliseconds}ms');

      // 步骤 2: LLM 润色（保留时间戳）
      setState(() => _processingStep = 2);
      final llmResult =
          await _llmService.summarize(asrResult.utterances);
      await _storageService.writeSummary(
          _currentFolderPath!, llmResult.content);
      await _storageService.writeSummaryUtterances(
          _currentFolderPath!,
          SummaryUtteranceData(
              version: 1, utterances: llmResult.utterances));
      debugPrint('[流程] LLM summarize 完成: ${sw.elapsedMilliseconds}ms');

      // 步骤 3: 保存元数据
      setState(() => _processingStep = 3);
      final entry = DiaryEntry(
        id: _currentFolderId!,
        title: llmResult.title,
        folderPath: _currentFolderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
      );
      await _storageService.createEntry(entry);
      debugPrint('[流程] 保存元数据完成: ${sw.elapsedMilliseconds}ms');

      // TTS 触发点 2：低沉男声播报总结（失败不阻塞）
      _speakSummary(llmResult.oneLineSummary);

      // ... Navigator 部分不变
```

在文件顶部的 import 中新增：

```dart
import '../models/utterance.dart';
```

- [ ] **Step 2: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "feat: 录音页面适配带时间戳的 ASR/LLM/存储接口"
```

---

### Task 7: 时间戳同步文本组件

**Files:**
- Create: `lib/widgets/timestamped_text_view.dart`

- [ ] **Step 1: 创建 TimestampedTextView 组件**

监听播放位置，句子级高亮同步：

```dart
import 'package:flutter/material.dart';

import '../models/utterance.dart';
import '../services/audio_player_service.dart';

class TimestampedTextView extends StatefulWidget {
  final List<Utterance> utterances;
  final AudioPlayerService playerService;

  const TimestampedTextView({
    super.key,
    required this.utterances,
    required this.playerService,
  });

  @override
  State<TimestampedTextView> createState() => _TimestampedTextViewState();
}

class _TimestampedTextViewState extends State<TimestampedTextView> {
  Duration _position = Duration.zero;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.playerService.positionStream.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int get _currentIndex {
    final posMs = _position.inMilliseconds;
    for (var i = 0; i < widget.utterances.length; i++) {
      final u = widget.utterances[i];
      if (posMs >= u.startTime && posMs < u.endTime) {
        return i;
      }
    }
    // 如果已播放完所有片段，返回最后一个
    if (widget.utterances.isNotEmpty &&
        posMs >= widget.utterances.last.endTime) {
      return widget.utterances.length - 1;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.utterances.length; i++)
          _buildSentence(
            widget.utterances[i],
            i,
            i == currentIndex,
            i < currentIndex,
            theme,
          ),
      ],
    );
  }

  Widget _buildSentence(
    Utterance utterance,
    int index,
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
        widget.playerService.play('');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          utterance.text,
          style: TextStyle(
            fontSize: 16,
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

- [ ] **Step 2: 提交**

```bash
git add lib/widgets/timestamped_text_view.dart
git commit -m "feat: 添加 TimestampedTextView 播放同步高亮组件"
```

---

### Task 8: 详情页 — 集成播放同步

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: 更新 DiaryDetailPage**

替换原有 `_loadContent` 和 `build` 中的内容：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import '../services/audio_player_service.dart';
import '../services/diary_storage_service.dart';
import '../widgets/audio_player_bar.dart';
import '../widgets/timestamped_text_view.dart';
import 'diary_list_page.dart';

class DiaryDetailPage extends StatefulWidget {
  final DiaryEntry entry;

  const DiaryDetailPage({super.key, required this.entry});

  @override
  State<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends State<DiaryDetailPage> {
  final _playerService = AudioPlayerService();
  final _storageService = DiaryStorageService();
  String _summary = '';
  List<Utterance> _summaryUtterances = [];
  TranscriptData? _transcriptData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final summary =
        await _storageService.readSummary(widget.entry.folderPath);
    final transcriptData =
        await _storageService.readTranscriptJson(widget.entry.folderPath);

    List<Utterance> summaryUtterances = [];
    try {
      final summaryData = await _storageService
          .readSummaryUtterances(widget.entry.folderPath);
      summaryUtterances = summaryData.utterances;
    } catch (_) {
      // summary_utterances.json 可能不存在（旧数据 migration 已清除）
    }

    if (mounted) {
      setState(() {
        _summary = summary;
        _summaryUtterances = summaryUtterances;
        _transcriptData = transcriptData;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _playerService.dispose();
    super.dispose();
  }

  Future<void> _deleteDiary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除这篇日记吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storageService.deleteEntry(
          widget.entry.id, widget.entry.folderPath);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DiaryListPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioPath = p.join(widget.entry.folderPath, 'audio.wav');
    final audioExists = File(audioPath).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.displayTitle),
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
                  Text(
                    '${widget.entry.formattedDate}  ${widget.entry.durationDisplay}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (audioExists)
                    AudioPlayerBar(
                        playerService: _playerService,
                        audioFilePath: audioPath),
                  const SizedBox(height: 16),
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
                ],
              ),
            ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "feat: 详情页集成播放同步，显示带时间戳的润色文本"
```

---

### Task 9: 编译验证与清理

- [ ] **Step 1: 运行 flutter analyze 检查代码**

Run: `flutter analyze`
Expected: 无错误

- [ ] **Step 2: 修复 analyze 发现的问题（如有）**

- [ ] **Step 3: 最终提交**

```bash
git add -A
git commit -m "chore: 修复 analyze 问题"
```

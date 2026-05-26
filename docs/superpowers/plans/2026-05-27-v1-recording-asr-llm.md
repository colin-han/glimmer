# V1 录音→ASR→LLM 总结 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现语音日记 App 的第一个可用版本：录音→ASR 识别→LLM 单轮总结→持久化→三页 UI + 音频播放

**Architecture:** Flutter App，按层分包（models / services / pages / widgets）。五个 service 封装外部能力（录音、播放、ASR、LLM、存储），三个页面通过 service 层完成主流程。数据持久化采用 drift (SQLite) 存元数据 + 文件系统存正文/音频/识别文本。

**Tech Stack:** Flutter/Dart 3.x, record, just_audio, dio, drift, path_provider, flutter_dotenv, uuid, flutter_markdown, intl

**Design Spec:** `docs/superpowers/specs/2026-05-27-v1-recording-asr-llm-design.md`

---

## File Structure

```
lib/
  main.dart
  models/
    diary_entry.dart
  services/
    audio_recorder_service.dart
    audio_player_service.dart
    asr_service.dart
    llm_service.dart
    diary_storage_service.dart
    database/
      app_database.dart
      app_database.g.dart          (drift 生成)
      tables.dart
  pages/
    recording_page.dart
    diary_list_page.dart
    diary_detail_page.dart
  widgets/
    recording_button.dart
    audio_player_bar.dart
    step_progress_indicator.dart
.env.local.example
```

---

### Task 1: Flutter 项目初始化与依赖安装

**Files:**
- Create: `pubspec.yaml`, `lib/main.dart`, `.env.local.example`, `.gitignore` 更新

- [ ] **Step 1: 创建 Flutter 项目**

```bash
cd /Users/colinhan/projects/vibe-tools/glimmer/glimmer
flutter create --org com.personal --project-name voice_diary --platforms android .
```

- [ ] **Step 2: 更新 pubspec.yaml 添加依赖**

在 `pubspec.yaml` 的 `dependencies:` 下添加：

```yaml
dependencies:
  record: ^5.1.2
  just_audio: ^0.9.42
  dio: ^5.7.0
  drift: ^2.22.1
  sqlite3_flutter_libs: ^0.5.28
  path_provider: ^2.1.5
  flutter_dotenv: ^5.2.1
  uuid: ^4.5.1
  flutter_markdown: ^0.7.6+2
  intl: ^0.19.0

dev_dependencies:
  drift_dev: ^2.22.1
  build_runner: ^2.4.14
```

- [ ] **Step 3: 安装依赖**

```bash
flutter pub get
```

- [ ] **Step 4: 创建 .env.local.example**

```
VOLCENGINE_ACCESS_KEY=your_access_key_here
VOLCENGINE_SECRET_KEY=your_secret_key_here
VOLCENGINE_ARK_API_KEY=your_ark_api_key_here
VOLCENGINE_ARK_ENDPOINT_ID=your_endpoint_id_here
```

- [ ] **Step 5: 更新 .gitignore**

在 `.gitignore` 末尾追加：

```
.env.local
*.env
```

- [ ] **Step 6: 替换 lib/main.dart 为最小骨架**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');
  runApp(const VoiceDiaryApp());
}

class VoiceDiaryApp extends StatelessWidget {
  const VoiceDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '语音日记',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('语音日记 v1')),
      ),
    );
  }
}
```

- [ ] **Step 7: 验证项目可以编译运行**

```bash
flutter build apk --debug
```

Expected: BUILD SUCCESSFUL

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "初始化 Flutter 项目骨架与依赖"
```

---

### Task 2: 数据模型与数据库层

**Files:**
- Create: `lib/services/database/tables.dart`
- Create: `lib/services/database/app_database.dart`
- Create: `lib/models/diary_entry.dart`

- [ ] **Step 1: 创建 drift 表定义 `lib/services/database/tables.dart`**

```dart
import 'package:drift/drift.dart';

class DiaryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get folderPath => text()();
  IntColumn get durationSeconds => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: 创建数据库类 `lib/services/database/app_database.dart`**

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [DiaryEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<List<DiaryEntry>> getAllEntries() {
    return (select(diaryEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<DiaryEntry> getEntryById(String id) {
    return (select(diaryEntries)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> insertEntry(DiaryEntriesCompanion entry) {
    return into(diaryEntries).insert(entry);
  }

  Future<void> deleteEntry(String id) {
    return (delete(diaryEntries)..where((t) => t.id.equals(id))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'voice_diary.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

- [ ] **Step 3: 创建数据模型 `lib/models/diary_entry.dart`**

```dart
class DiaryEntry {
  final String id;
  final String title;
  final String folderPath;
  final int durationSeconds;
  final DateTime createdAt;

  const DiaryEntry({
    required this.id,
    required this.title,
    required this.folderPath,
    required this.durationSeconds,
    required this.createdAt,
  });

  String get displayTitle =>
      title.isNotEmpty ? title : '未命名日记';

  String get formattedDate {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get durationDisplay {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 4: 运行 drift 代码生成**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: 成功生成 `lib/services/database/app_database.g.dart`

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "添加数据模型与 drift 数据库层"
```

---

### Task 3: DiaryStorageService

**Files:**
- Create: `lib/services/diary_storage_service.dart`

- [ ] **Step 1: 创建 DiaryStorageService**

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
import 'database/app_database.dart';

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

  Future<String> _filePath(String folderPath, String fileName) =>
      Future.value(p.join(folderPath, fileName));

  Future<void> createEntry(DiaryEntry entry) async {
    await _db.insertEntry(DiaryEntriesCompanion.insert(
      id: entry.id,
      title: entry.title,
      folderPath: entry.folderPath,
      durationSeconds: entry.durationSeconds,
      createdAt: entry.createdAt.millisecondsSinceEpoch,
    ));
  }

  Future<void> writeTranscript(String folderPath, String text) async {
    final file = File(await _filePath(folderPath, 'transcript.txt'));
    await file.writeAsString(text);
  }

  Future<void> writeSummary(String folderPath, String content) async {
    final file = File(await _filePath(folderPath, 'summary.md'));
    await file.writeAsString(content);
  }

  Future<String> readTranscript(String folderPath) async {
    final file = File(await _filePath(folderPath, 'transcript.txt'));
    return file.readAsString();
  }

  Future<String> readSummary(String folderPath) async {
    final file = File(await _filePath(folderPath, 'summary.md'));
    return file.readAsString();
  }

  Future<List<DiaryEntry>> getAllEntries() async {
    final rows = await _db.getAllEntries();
    return rows
        .map((r) => DiaryEntry(
              id: r.id,
              title: r.title,
              folderPath: r.folderPath,
              durationSeconds: r.durationSeconds,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(r.createdAt),
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
git commit -m "添加 DiaryStorageService"
```

---

### Task 4: AudioRecorderService

**Files:**
- Create: `lib/services/audio_recorder_service.dart`
- Modify: `android/app/src/main/AndroidManifest.xml` — 添加录音权限

- [ ] **Step 1: 添加录音权限到 AndroidManifest.xml**

在 `android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 标签内添加：

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

- [ ] **Step 2: 创建 AudioRecorderService**

```dart
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordingStartTime;

  bool get isRecording => _isRecording;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> startRecording(String folderPath) async {
    if (_isRecording) return;

    final hasPerms = await hasPermission();
    if (!hasPerms) {
      throw Exception('没有麦克风权限');
    }

    final filePath = p.join(folderPath, 'audio.m4a');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );
    _isRecording = true;
    _recordingStartTime = DateTime.now();
  }

  Future<RecordingResult> stopRecording() async {
    if (!_isRecording) {
      throw Exception('没有正在进行的录音');
    }

    final filePath = await _recorder.stop();
    _isRecording = false;
    final duration =
        DateTime.now().difference(_recordingStartTime!).inSeconds;
    _recordingStartTime = null;

    return RecordingResult(
      filePath: filePath!,
      durationSeconds: duration,
    );
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

class RecordingResult {
  final String filePath;
  final int durationSeconds;

  RecordingResult({required this.filePath, required this.durationSeconds});
}
```

- [ ] **Step 3: 提交**

```bash
git add lib/services/audio_recorder_service.dart android/app/src/main/AndroidManifest.xml
git commit -m "添加 AudioRecorderService 与录音权限"
```

---

### Task 5: AudioPlayerService

**Files:**
- Create: `lib/services/audio_player_service.dart`

- [ ] **Step 1: 创建 AudioPlayerService**

```dart
import 'dart:async';

import 'package:just_audio/just_audio.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  double _speed = 1.0;

  bool get isPlaying => _player.playing;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  double get speed => _speed;
  Stream<bool> get playingStream => _player.playingStream;

  Future<void> play(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.setSpeed(_speed);
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setSpeed(double rate) async {
    _speed = rate;
    await _player.setSpeed(rate);
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/audio_player_service.dart
git commit -m "添加 AudioPlayerService"
```

---

### Task 6: AsrService（豆包录音文件识别）

**Files:**
- Create: `lib/services/asr_service.dart`

火山引擎录音文件识别 API 流程：
1. 调用 `POST https://openspeech.bytedance.com/api/v1/auc/submit` 提交任务
2. 轮询 `POST https://openspeech.bytedance.com/api/v1/auc/query` 获取结果
3. 认证使用火山引擎 V4 签名（Authorization header）

- [ ] **Step 1: 创建 ASR 签名工具 `lib/services/volcengine_auth.dart`**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class VolcengineAuth {
  static String get accessKey =>
      dotenv.get('VOLCENGINE_ACCESS_KEY');
  static String get secretKey =>
      dotenv.get('VOLCENGINE_SECRET_KEY');
}
```

- [ ] **Step 2: 创建 AsrService**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AsrService {
  final Dio _dio = Dio();
  static const String _baseUrl =
      'https://openspeech.bytedance.com/api/v1/auc';

  Future<String> transcribe(String audioFilePath) async {
    final audioBytes = await File(audioFilePath).readAsBytes();
    final audioBase64 = base64Encode(audioBytes);

    // 提交识别任务
    final submitResp = await _dio.post(
      '$_baseUrl/submit',
      data: {
        'header': {
          'appid': dotenv.get('VOLCENGINE_ACCESS_KEY'),
          'cluster': 'volcengine_streaming_common',
        },
        'setting': {
          'language': 'zh',
          'format': 'm4a',
        },
        'audio': {
          'format': 'm4a',
          'codec': 'raw',
          'data': audioBase64,
        },
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization':
            'Bearer;${dotenv.get('VOLCENGINE_ACCESS_KEY')}',
      }),
    );

    final taskId = submitResp.data['payload']['task_id'];
    if (taskId == null) {
      throw Exception('ASR 任务提交失败');
    }

    // 轮询等待结果
    String? transcript;
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 2));

      final queryResp = await _dio.post(
        '$_baseUrl/query',
        data: {
          'header': {
            'appid': dotenv.get('VOLCENGINE_ACCESS_KEY'),
          },
          'payload': {
            'task_id': taskId,
          },
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer;${dotenv.get('VOLCENGINE_ACCESS_KEY')}',
        }),
      );

      final status = queryResp.data['payload']['status'];
      if (status == 'completed') {
        final results =
            queryResp.data['payload']['result'] as List?;
        if (results != null && results.isNotEmpty) {
          transcript = results
              .map((r) => r['text'] as String? ?? '')
              .join();
        }
        break;
      } else if (status == 'failed') {
        throw Exception('ASR 识别失败');
      }
    }

    if (transcript == null || transcript.trim().isEmpty) {
      throw Exception('未能识别语音内容');
    }

    return transcript;
  }
}
```

> **注意**：以上 API 端点和请求体结构基于火山引擎语音服务通用模式。实际实施时需对照 https://www.volcengine.com/docs/6561/80816 确认精确的字段名。如果 API 格式有差异，以官方文档为准调整 `data` 结构。

- [ ] **Step 3: 提交**

```bash
git add lib/services/asr_service.dart lib/services/volcengine_auth.dart
git commit -m "添加 AsrService 与火山引擎认证工具"
```

---

### Task 7: LlmService（豆包 Doubao 单轮总结）

**Files:**
- Create: `lib/services/llm_service.dart`

火山方舟 LLM 使用 OpenAI 兼容格式，端点为 `https://ark.cn-beijing.volces.com/api/v3/chat/completions`。

- [ ] **Step 1: 创建 LlmService**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LlmService {
  final Dio _dio = Dio();

  static const String _baseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';

  Future<LlmResult> summarize(String transcript) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      '$_baseUrl/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记助手。用户会给你一段语音识别的口语文本，'
                '请将其整理为通顺的日记正文（使用 Markdown 格式）。'
                '同时生成一个简短的标题（不超过 20 个字）。'
                '请严格按以下 JSON 格式返回，不要包含任何其他内容：'
                '{"title": "标题", "content": "日记正文"}',
          },
          {
            'role': 'user',
            'content': transcript,
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

  LlmResult _parseResult(String content) {
    // 尝试解析 JSON
    try {
      // 去掉可能的 markdown 代码块标记
      final cleaned = content
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final json = _parseJson(cleaned);
      return LlmResult(
        title: json['title'] as String? ?? '未命名日记',
        content: json['content'] as String? ?? content,
      );
    } catch (_) {
      // JSON 解析失败，整个内容作为正文
      return LlmResult(
        title: _extractTitle(content),
        content: content,
      );
    }
  }

  dynamic _parseJson(String s) {
    return _JsonDecoder().convert(s);
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

class LlmResult {
  final String title;
  final String content;

  LlmResult({required this.title, required this.content});
}

class _JsonDecoder extends Converter<String, dynamic> {
  @override
  dynamic convert(String input) => const JsonDecoder().convert(input);

  @override
  Sink<String> startChunkedConversion(Sink<dynamic> sink) {
    return _StringSink(sink);
  }
}

class _StringSink implements Sink<String> {
  final Sink<dynamic> _sink;
  final StringBuffer _buffer = StringBuffer();

  _StringSink(this._sink);

  @override
  void add(String data) => _buffer.write(data);

  @override
  void close() {
    _sink.add(const JsonDecoder().convert(_buffer.toString()));
    _sink.close();
  }
}
```

> **注意**：`_JsonDecoder` 类用于避免直接 import `dart:convert` 的 `JsonDecoder`，实际代码可直接使用 `jsonDecode`。此处简化处理。

- [ ] **Step 2: 简化 LlmService 中的 JSON 解析**

将 `_parseJson` 和 `_JsonDecoder` 相关代码替换为直接使用：

```dart
import 'dart:convert';
```

然后 `_parseJson` 改为：

```dart
  dynamic _parseJson(String s) => jsonDecode(s);
```

并删除 `_JsonDecoder` 和 `_StringSink` 类。

- [ ] **Step 3: 提交**

```bash
git add lib/services/llm_service.dart
git commit -m "添加 LlmService"
```

---

### Task 8: 共享 UI 组件

**Files:**
- Create: `lib/widgets/recording_button.dart`
- Create: `lib/widgets/step_progress_indicator.dart`
- Create: `lib/widgets/audio_player_bar.dart`

- [ ] **Step 1: 创建录音按钮组件 `lib/widgets/recording_button.dart`**

```dart
import 'package:flutter/material.dart';

enum RecordingState {
  idle,
  recording,
  processing,
}

class RecordingButton extends StatelessWidget {
  final RecordingState state;
  final VoidCallback onTap;
  final int recordingSeconds;

  const RecordingButton({
    super.key,
    required this.state,
    required this.onTap,
    this.recordingSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCircle(context),
          const SizedBox(height: 16),
          _buildLabel(context),
        ],
      ),
    );
  }

  Widget _buildCircle(BuildContext context) {
    final color = switch (state) {
      RecordingState.idle => Theme.of(context).colorScheme.primary,
      RecordingState.recording => Colors.red,
      RecordingState.processing => Colors.grey,
    };

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 3),
      ),
      child: Center(
        child: switch (state) {
          RecordingState.idle => Icon(Icons.mic,
              size: 48, color: color),
          RecordingState.recording => _buildRecordingContent(color),
          RecordingState.processing => const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
        },
      ),
    );
  }

  Widget _buildRecordingContent(Color color) {
    final minutes = recordingSeconds ~/ 60;
    final seconds = recordingSeconds % 60;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.stop, size: 36, color: color),
        const SizedBox(height: 4),
        Text(
          '$minutes:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(BuildContext context) {
    return Text(
      switch (state) {
        RecordingState.idle => '点击开始录音',
        RecordingState.recording => '点击停止录音',
        RecordingState.processing => '处理中...',
      },
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
```

- [ ] **Step 2: 创建步骤进度指示器 `lib/widgets/step_progress_indicator.dart`**

```dart
import 'package:flutter/material.dart';

class StepProgressIndicator extends StatelessWidget {
  final int currentStep; // 0=ASR, 1=LLM, 2=保存
  final bool hasError;

  const StepProgressIndicator({
    super.key,
    required this.currentStep,
    this.hasError = false,
  });

  static const _steps = ['语音识别', 'AI 总结', '保存'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('→',
                style: TextStyle(
                  color: stepIndex < currentStep
                      ? Colors.green
                      : Colors.grey,
                )),
          );
        }
        final stepIndex = i ~/ 2;
        return _buildStep(context, stepIndex);
      }),
    );
  }

  Widget _buildStep(BuildContext context, int index) {
    final isCompleted = index < currentStep;
    final isCurrent = index == currentStep;
    final color = isCompleted
        ? Colors.green
        : isCurrent
            ? (hasError ? Colors.red : Theme.of(context).colorScheme.primary)
            : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withOpacity(0.2),
          child: isCompleted
              ? const Icon(Icons.check, size: 18, color: Colors.green)
              : Text('${index + 1}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Text(_steps[index],
            style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
```

- [ ] **Step 3: 创建音频播放条 `lib/widgets/audio_player_bar.dart`**

```dart
import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';

class AudioPlayerBar extends StatefulWidget {
  final AudioPlayerService playerService;
  final String audioFilePath;

  const AudioPlayerBar({
    super.key,
    required this.playerService,
    required this.audioFilePath,
  });

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _speed = 1.0;
  static const _speeds = [1.0, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    widget.playerService.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    widget.playerService.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    widget.playerService.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () async {
                    if (_isPlaying) {
                      await widget.playerService.pause();
                    } else {
                      await widget.playerService
                          .play(widget.audioFilePath);
                    }
                  },
                ),
                Expanded(
                  child: Column(
                    children: [
                      Slider(
                        value: _duration != null &&
                                _position.inMilliseconds <=
                                    _duration!.inMilliseconds
                            ? _position.inMilliseconds.toDouble()
                            : 0,
                        min: 0,
                        max: _duration?.inMilliseconds.toDouble() ?? 1,
                        onChanged: (val) async {
                          await widget.playerService
                              .seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(_position),
                              style: const TextStyle(fontSize: 12)),
                          Text(
                            _duration != null
                                ? _formatDuration(_duration!)
                                : '--:--',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final idx = _speeds.indexOf(_speed);
                    final next = _speeds[(idx + 1) % _speeds.length];
                    setState(() => _speed = next);
                    await widget.playerService.setSpeed(next);
                  },
                  child: Text('${_speed}x'),
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

- [ ] **Step 4: 提交**

```bash
git add lib/widgets/
git commit -m "添加共享 UI 组件：录音按钮、步骤进度、音频播放条"
```

---

### Task 9: 录音页 RecordingPage

**Files:**
- Create: `lib/pages/recording_page.dart`
- Modify: `lib/main.dart` — 更新路由

- [ ] **Step 1: 创建 RecordingPage**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../services/asr_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';
import '../widgets/recording_button.dart';
import '../widgets/step_progress_indicator.dart';
import 'diary_detail_page.dart';

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final _recorderService = AudioRecorderService();
  final _storageService = DiaryStorageService();
  final _asrService = AsrService();
  final _llmService = LlmService();
  final _uuid = const Uuid();

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  Timer? _timer;
  String? _currentFolderId;

  // 处理中状态
  int _processingStep = 0;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _timer?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  void _startTimer() {
    _recordingSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= 300) {
        _stopAndProcess();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _onTap() async {
    switch (_state) {
      case RecordingState.idle:
        await _startRecording();
        break;
      case RecordingState.recording:
        await _stopAndProcess();
        break;
      case RecordingState.processing:
        break;
    }
  }

  Future<void> _startRecording() async {
    try {
      _currentFolderId = _uuid.v4();
      final folderPath =
          await _storageService.createDiaryFolder(_currentFolderId!);
      await _recorderService.startRecording(folderPath);
      setState(() => _state = RecordingState.recording);
      _startTimer();
    } catch (e) {
      _showError('录音启动失败：$e');
    }
  }

  Future<void> _stopAndProcess() async {
    _stopTimer();
    setState(() {
      _state = RecordingState.processing;
      _processingStep = 0;
      _hasError = false;
      _errorMessage = '';
    });

    final duration = _recordingSeconds;

    try {
      // 步骤 1: ASR
      final recordingResult = await _recorderService.stopRecording();
      setState(() => _processingStep = 1);

      final transcript =
          await _asrService.transcribe(recordingResult.filePath);
      final folderPath =
          await _storageService.createDiaryFolder(_currentFolderId!);
      await _storageService.writeTranscript(folderPath, transcript);
      setState(() => _processingStep = 2);

      // 步骤 2: LLM
      final llmResult = await _llmService.summarize(transcript);
      await _storageService.writeSummary(
          folderPath, llmResult.content);
      setState(() => _processingStep = 3);

      // 步骤 3: 保存元数据
      final entry = DiaryEntry(
        id: _currentFolderId!,
        title: llmResult.title,
        folderPath: folderPath,
        durationSeconds: duration,
        createdAt: DateTime.now(),
      );
      await _storageService.createEntry(entry);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DiaryDetailPage(entry: entry),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语音日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiaryListPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_state == RecordingState.processing) ...[
                StepProgressIndicator(
                  currentStep: _processingStep,
                  hasError: _hasError,
                ),
                const SizedBox(height: 32),
                if (_hasError)
                  Text(_errorMessage,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center)
                else
                  const Text('正在处理中...'),
                const SizedBox(height: 24),
              ],
              RecordingButton(
                state: _state,
                onTap: _onTap,
                recordingSeconds: _recordingSeconds,
              ),
              if (_hasError) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _state = RecordingState.idle;
                      _hasError = false;
                      _processingStep = 0;
                    });
                  },
                  child: const Text('重新开始'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

> **注意**：RecordingPage 中引用了 `DiaryListPage` 和 `DiaryDetailPage`，这两个页面在后续 Task 中创建。在 Task 9 提交时如果编译报错，可以先注释掉导航代码，等 Task 10/11 完成后再启用。或者在 Task 9-11 全部完成后一起提交。

- [ ] **Step 2: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "添加录音页"
```

---

### Task 10: 日记列表页 DiaryListPage

**Files:**
- Create: `lib/pages/diary_list_page.dart`

- [ ] **Step 1: 创建 DiaryListPage**

```dart
import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../services/diary_storage_service.dart';
import 'diary_detail_page.dart';
import 'recording_page.dart';

class DiaryListPage extends StatefulWidget {
  const DiaryListPage({super.key});

  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  final _storageService = DiaryStorageService();
  List<DiaryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await _storageService.getAllEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的日记')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.book_outlined,
                          size: 64,
                          color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('还没有日记，点击 + 开始录音',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey[600])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadEntries,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(entry.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${entry.formattedDate}  ${entry.durationDisplay}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    DiaryDetailPage(entry: entry),
                              ),
                            ).then((_) => _loadEntries());
                          },
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const RecordingPage(),
            ),
          );
        },
        child: const Icon(Icons.mic),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/pages/diary_list_page.dart
git commit -m "添加日记列表页"
```

---

### Task 11: 日记详情页 DiaryDetailPage

**Files:**
- Create: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: 创建 DiaryDetailPage**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;

import '../models/diary_entry.dart';
import '../services/audio_player_service.dart';
import '../services/diary_storage_service.dart';
import '../widgets/audio_player_bar.dart';
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
  String _transcript = '';
  bool _showTranscript = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final summary =
        await _storageService.readSummary(widget.entry.folderPath);
    final transcript =
        await _storageService.readTranscript(widget.entry.folderPath);
    if (mounted) {
      setState(() {
        _summary = summary;
        _transcript = transcript;
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
              child: const Text('删除',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storageService.deleteEntry(
          widget.entry.id, widget.entry.folderPath);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const DiaryListPage(),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioPath = p.join(widget.entry.folderPath, 'audio.m4a');
    final audioExists = File(audioPath).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.displayTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteDiary,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 元数据
                  Text(
                    '${widget.entry.formattedDate}  '
                    '${widget.entry.durationDisplay}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),

                  // 音频播放条
                  if (audioExists)
                    AudioPlayerBar(
                      playerService: _playerService,
                      audioFilePath: audioPath,
                    ),
                  const SizedBox(height: 16),

                  // LLM 总结正文
                  MarkdownBody(data: _summary),
                  const SizedBox(height: 24),

                  // 原始识别文本（可展开）
                  ExpansionTile(
                    title: const Text('原始识别文本'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_transcript,
                            style: const TextStyle(fontSize: 14)),
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
git commit -m "添加日记详情页（含音频播放）"
```

---

### Task 12: 更新 main.dart 路由入口

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 更新 main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'pages/recording_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');
  runApp(const VoiceDiaryApp());
}

class VoiceDiaryApp extends StatelessWidget {
  const VoiceDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '语音日记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
      ),
      home: const RecordingPage(),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/main.dart
git commit -m "更新 main.dart 路由入口"
```

---

### Task 13: 编译验证与最终提交

- [ ] **Step 1: 运行 drift 代码生成确保最新**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 2: 运行 Flutter 分析**

```bash
flutter analyze
```

Expected: No issues found（允许 info 级别的提示）

- [ ] **Step 3: 编译 debug APK 验证**

```bash
flutter build apk --debug
```

Expected: BUILD SUCCESSFUL

- [ ] **Step 4: 修复所有编译错误（如有）**

根据 `flutter analyze` 和 `flutter build` 的输出修复所有问题。主要关注：
- import 路径是否正确
- 文件是否都存在
- 类型是否匹配

- [ ] **Step 5: 最终提交**

```bash
git add -A
git commit -m "v1 完成：录音→ASR→LLM 总结，三页 UI + 音频播放"
```

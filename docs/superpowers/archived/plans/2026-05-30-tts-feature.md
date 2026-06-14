# TTS 语音播报功能实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在录音结束和 AI 整理完成两个时机增加 TTS 语音播报，甜美女声应答 + 低沉男声播报总结。

**Architecture:** 新建 TtsService 封装火山引擎 TTS V1 HTTP API，合成 MP3 音频后用 just_audio 播放。改造 LlmService 增加 generateReply 和 oneLineSummary。RecordingPage 在两个触发点异步调用 TTS。

**Tech Stack:** Flutter, dio (HTTP), just_audio (播放), dart:convert (base64 解码)

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/services/tts_service.dart` | 新建 | 火山引擎 TTS V1 API 封装，合成 + 播放 |
| `lib/services/llm_service.dart` | 改造 | 新增 generateReply，summarize 增加 oneLineSummary |
| `lib/pages/recording_page.dart` | 改造 | 集成两个 TTS 触发点 |
| `.env.local.example` | 改造 | 更新环境变量说明 |

---

### Task 1: 新建 TtsService

**Files:**
- Create: `lib/services/tts_service.dart`

TtsService 封装火山引擎 TTS V1 HTTP API。请求端点 `https://openspeech.bytedone.com/api/v1/tts`，认证用 `Authorization: Bearer;{token}` header，请求体包含 app/token/voice_type 等参数。响应 JSON 中 `code: 3000` 表示成功，`data` 字段为 base64 编码的 MP3 音频。

播放流程：base64 解码 → 写入临时文件 → just_audio 播放。

音色枚举（基于控制台实际可用音色）：
- `VoiceType.femaleSweet` → `saturn_zh_female_keainvsheng_tob`（可爱女生，甜美女声）
- `VoiceType.maleDeep` → `zh_male_m191_uranus_bigtts`（云舟，低沉男声）

- [ ] **Step 1: 创建 TtsService**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum VoiceType { femaleSweet, maleDeep }

class TtsService {
  final Dio _dio = Dio();
  final AudioPlayer _player = AudioPlayer();
  final _uuid = const Uuid();

  static const _voiceTypes = {
    VoiceType.femaleSweet: 'saturn_zh_female_keainvsheng_tob',
    VoiceType.maleDeep: 'zh_male_m191_uranus_bigtts',
  };

  Future<void> speak(String text, VoiceType voiceType) async {
    final appid = dotenv.get('VOLCENGINE_SPEECH_APPID');
    final token = dotenv.get('VOLCENGINE_SPEECH_TOKEN');

    final response = await _dio.post(
      'https://openspeech.bytedance.com/api/v1/tts',
      data: {
        'app': {
          'appid': appid,
          'token': token,
          'cluster': 'volcano_tts',
        },
        'user': {'uid': appid},
        'audio': {
          'voice_type': _voiceTypes[voiceType],
          'encoding': 'mp3',
          'speed_ratio': 1.0,
        },
        'request': {
          'reqid': _uuid.v4(),
          'text': text,
          'text_type': 'plain',
          'operation': 'query',
        },
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer;$token',
      }),
    );

    final code = response.data['code'] as int?;
    if (code != 3000) {
      final message = response.data['message'] ?? 'TTS 合成失败';
      throw Exception('TTS 错误 ($code): $message');
    }

    final audioBase64 = response.data['data'] as String;
    final audioBytes = base64Decode(audioBase64);

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/tts_${_uuid.v4()}.mp3');
    await tempFile.writeAsBytes(audioBytes);

    await _player.setFilePath(tempFile.path);
    await _player.play();
    await _player.processingStateStream.firstWhere(
      (state) => state == ProcessingState.completed,
    );

    await tempFile.delete();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
```

- [ ] **Step 2: 运行代码分析**

Run: `flutter analyze lib/services/tts_service.dart`
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/services/tts_service.dart
git commit -m "新建 TtsService：火山引擎 TTS 语音合成"
```

---

### Task 2: 改造 LlmService

**Files:**
- Modify: `lib/services/llm_service.dart`

两个改动：
1. `LlmResult` 新增 `oneLineSummary` 字段
2. `summarize()` 的 prompt 增加 `oneLineSummary` 要求
3. 新增 `generateReply(String realtimeText)` 方法：基于实时识别文本生成一句应景回复

- [ ] **Step 1: 更新 LlmService**

将 `lib/services/llm_service.dart` 完整替换为：

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LlmResult {
  final String title;
  final String content;
  final String oneLineSummary;

  LlmResult({
    required this.title,
    required this.content,
    required this.oneLineSummary,
  });
}

class LlmService {
  final Dio _dio = Dio();

  Future<LlmResult> summarize(String transcript) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记助手。用户会给你一段语音识别的口语文本，'
                '请按以下规则整理为日记正文（Markdown 格式）：\n'
                '1. 最大程度保留原文的句子结构和用词，不添加、不删除实质内容\n'
                '2. 仅删除无意义的口语填充词（嗯、啊、那个、就是说、然后呢等）\n'
                '3. 消除重复、结巴、停顿导致的不通顺\n'
                '4. 按语义自然分段（话题转换、时间线变化处分段）\n'
                '5. 适当将口语化词汇替换为书面表达（如觉得→认为、挺→很），保持自然\n'
                '同时从内容中提炼一个简短标题（不超过 20 个字），'
                '以及一句话总结（不超过 30 个字）。'
                '严格按以下 JSON 格式返回，不要包含任何其他内容：'
                '{"title": "标题", "content": "日记正文", "oneLineSummary": "一句话总结"}',
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
      return LlmResult(
        title: json['title'] as String? ?? '未命名日记',
        content: json['content'] as String? ?? content,
        oneLineSummary: json['oneLineSummary'] as String? ?? '',
      );
    } catch (_) {
      return LlmResult(
        title: _extractTitle(content),
        content: content,
        oneLineSummary: '',
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

- [ ] **Step 2: 运行代码分析**

Run: `flutter analyze lib/services/llm_service.dart`
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/services/llm_service.dart
git commit -m "改造 LlmService：新增 generateReply 和 oneLineSummary"
```

---

### Task 3: 改造 RecordingPage 集成 TTS

**Files:**
- Modify: `lib/pages/recording_page.dart`

核心改动：
1. 引入 TtsService
2. 停止录音后，与 Flash ASR 并行调用 LLM.generateReply → TTS（甜美女声）
3. 保存完成后，调用 LLM.generateSummaryAnnouncement → TTS（低沉男声）
4. TTS 失败不阻塞主流程

- [ ] **Step 1: 更新 RecordingPage**

在文件顶部 imports 中添加（在 `import '../services/realtime_asr_service.dart';` 之后）：

```dart
import '../services/tts_service.dart';
```

在 `_RecordingPageState` 类中，在 `final _realtimeAsr = RealtimeAsrService();` 之后添加：

```dart
  final _ttsService = TtsService();
```

在 `dispose()` 方法中，在 `_realtimeAsr.disconnect();` 之后添加：

```dart
    _ttsService.dispose();
```

将 `_stopAndProcess()` 方法中的 `try` 块内容替换为（从 `try {` 到对应的 `}`）：

```dart
    try {
      final recordingResult = await _recorderService.stopRecording();

      // TTS 触发点 1：甜美女声应答（与 Flash ASR 并行，失败不阻塞）
      _speakReply(_realtimeText);

      // 步骤 1: Flash ASR 兜底识别
      setState(() => _processingStep = 1);
      final transcript =
          await _asrService.transcribe(recordingResult.filePath);
      await _storageService.writeTranscript(
          _currentFolderPath!, transcript);

      // 步骤 2: LLM 润色
      setState(() => _processingStep = 2);
      final llmResult = await _llmService.summarize(transcript);
      await _storageService.writeSummary(
          _currentFolderPath!, llmResult.content);

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

      // TTS 触发点 2：低沉男声播报总结（失败不阻塞）
      _speakSummary(llmResult.oneLineSummary);

      if (mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => DiaryDetailPage(entry: entry),
            ))
            .then((_) {
          setState(() {
            _state = RecordingState.idle;
            _hasError = false;
            _processingStep = 0;
            _recordingSeconds = 0;
            _realtimeText = '';
          });
        });
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
```

在 `_showError` 方法之前添加两个方法：

```dart
  void _speakReply(String realtimeText) {
    if (realtimeText.isEmpty) return;
    () async {
      try {
        final reply = await _llmService.generateReply(realtimeText);
        await _ttsService.speak(reply, VoiceType.femaleSweet);
      } catch (e) {
        debugPrint('TTS 应答失败: $e');
      }
    }();
  }

  void _speakSummary(String oneLineSummary) {
    if (oneLineSummary.isEmpty) return;
    () async {
      try {
        final announcement =
            await _llmService.generateSummaryAnnouncement(oneLineSummary);
        await _ttsService.speak(announcement, VoiceType.maleDeep);
      } catch (e) {
        debugPrint('TTS 总结播报失败: $e');
      }
    }();
  }
```

- [ ] **Step 2: 运行全量分析**

Run: `flutter analyze`
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "改造 RecordingPage 集成 TTS 语音播报"
```

---

### Task 4: 更新 .env.local.example

**Files:**
- Modify: `.env.local.example`

TTS 复用 `VOLCENGINE_SPEECH_APPID` 和 `VOLCENGINE_SPEECH_TOKEN`，无需新增变量。更新注释说明即可。

- [ ] **Step 1: 更新环境变量示例**

将 `.env.local.example` 内容替换为：

```
# ASR 语音识别 + TTS 语音合成（共用）
VOLCENGINE_SPEECH_APPID=your_appid_here
VOLCENGINE_SPEECH_TOKEN=your_token_here

# LLM（豆包 Doubao）
VOLCENGINE_ARK_API_KEY=your_ark_api_key_here
VOLCENGINE_ARK_ENDPOINT_ID=your_endpoint_id_here
```

- [ ] **Step 2: 提交**

```bash
git add .env.local.example
git commit -m "更新 .env.local.example：TTS 复用 ASR 变量"
```

---

### Task 5: 验证

**Files:**
- 无新文件

- [ ] **Step 1: 运行全量代码分析**

Run: `flutter analyze`
Expected: 无错误、无警告

- [ ] **Step 2: 构建验证**

Run: `flutter build apk --debug`
Expected: 构建成功

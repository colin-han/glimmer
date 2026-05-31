# FGS 前台服务实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用 `flutter_foreground_task` 实现前台服务，确保锁屏时录音（PCM → Opus 编码）和后处理（TOS 上传、ASR、LLM）不断开。

**Architecture:** 将录音和处理逻辑从 `RecordingPage`（UI isolate）迁移到 `RecordingTaskHandler`（独立 isolate）。RecordingPage 变为纯 UI 壳，通过 `FlutterForegroundTask` 的消息通道接收状态更新。TaskHandler 管理 AudioRecorder、AudioEncoderService、RealtimeAsrService 的完整生命周期，录音停止后依次执行 TOS 上传 → Flash ASR → LLM → 打标签 → 保存。

**Tech Stack:** flutter_foreground_task ^9.2.2, record ^7.0.0, flutter_opus ^1.0.4, dio ^5.7.0, web_socket_channel ^3.0.1

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| Create | `lib/services/recording_task_handler.dart` | FGS TaskHandler，管理录音→处理全流程 |
| Modify | `lib/pages/recording_page.dart` | 重构为 UI 壳，启动/停止 FGS，监听状态消息 |
| Modify | `android/app/src/main/AndroidManifest.xml` | 添加 FGS 权限和 Service 声明 |
| Modify | `pubspec.yaml` | 添加 flutter_foreground_task 依赖 |

---

### Task 1: 添加依赖和 Android 配置

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: 添加 flutter_foreground_task 依赖**

在 `pubspec.yaml` 的 `dependencies` 中添加：

```yaml
  flutter_foreground_task: ^9.2.2
```

放在 `crypto: ^3.0.7` 之后。

- [ ] **Step 2: 运行 flutter pub get**

Run: `flutter pub get`
Expected: 依赖安装成功，无冲突

- [ ] **Step 3: 添加 Android FGS 权限**

在 `android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 标签下、`<application>` 标签之前添加：

```xml
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
```

- [ ] **Step 4: 添加 Service 声明**

在 `android/app/src/main/AndroidManifest.xml` 的 `<application>` 标签内、`</activity>` 之后添加：

```xml
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="microphone"
            android:exported="false"
            android:stopWithTask="true" />
```

- [ ] **Step 5: 提交**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml
git commit -m "feat: 添加 flutter_foreground_task 依赖和 Android FGS 配置"
```

---

### Task 2: 创建 RecordingTaskHandler

**Files:**
- Create: `lib/services/recording_task_handler.dart`

这个文件是核心。TaskHandler 运行在独立 isolate 中，管理完整的录音→处理流程。

关键约束：
- `flutter_foreground_task` 的 TaskHandler 必须通过顶层函数 `startCallback` 注册，且标记 `@pragma('vm:entry-point')`
- TaskHandler 中的所有服务实例必须在 `onStart` 中创建（不能从 UI isolate 传入）
- 使用 `FlutterForegroundTask.sendDataToMain()` 发送状态给 UI
- 使用 `FlutterForegroundTask.saveData()` / `getData()` 在 isolate 间共享关键数据（如 folderId）

- [ ] **Step 1: 创建 recording_task_handler.dart 骨架**

创建 `lib/services/recording_task_handler.dart`：

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import 'asr_service.dart';
import 'audio_encoder_service.dart';
import 'audio_recorder_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'realtime_asr_service.dart';
import 'tos_upload_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

class RecordingTaskHandler extends TaskHandler {
  AudioRecorderService? _recorderService;
  RealtimeAsrService? _realtimeAsr;
  final _storageService = DiaryStorageService();
  final _asrService = AsrService();
  final _llmService = LlmService();
  final _tosService = TosUploadService();
  final _uuid = const Uuid();

  String? _folderId;
  String? _folderPath;
  int _recordingSeconds = 0;
  Timer? _timer;
  bool _stopped = false;

  StreamSubscription<Uint8List>? _audioStreamSubscription;
  StreamSubscription<String>? _partialResultSubscription;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _folderId = await FlutterForegroundTask.getData(key: 'folderId');
    _folderPath = await FlutterForegroundTask.getData(key: 'folderPath');

    if (_folderId == null || _folderPath == null) {
      FlutterForegroundTask.sendDataToMain({
        'event': 'error',
        'message': '缺少录音文件夹信息',
      });
      return;
    }

    _startRecording();
  }

  Future<void> _startRecording() async {
    try {
      _recorderService = AudioRecorderService();
      await _recorderService!.startRecording(_folderPath!);

      _connectRealtimeAsr();

      _audioStreamSubscription =
          _recorderService!.audioStream.listen((pcmData) {
        if (_realtimeAsr?.isConnected == true) {
          _realtimeAsr!.sendAudio(pcmData);
        }
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _recordingSeconds++;
        FlutterForegroundTask.sendDataToMain({
          'event': 'recording',
          'duration': _recordingSeconds,
        });
        if (_recordingSeconds >= 300) {
          _stopAndProcess();
        }
      });

      FlutterForegroundTask.updateService(
        notificationTitle: 'Glimmer',
        notificationText: '正在录音...',
      );
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'event': 'error',
        'message': '录音启动失败：$e',
      });
    }
  }

  void _connectRealtimeAsr() {
    _realtimeAsr = RealtimeAsrService();
    _realtimeAsr!.connect().catchError((e) {
      debugPrint('实时 ASR 连接失败: $e');
    });

    _partialResultSubscription =
        _realtimeAsr!.onPartialResult.listen((text) {
      FlutterForegroundTask.sendDataToMain({
        'event': 'partial',
        'text': text,
      });
    });
  }

  Future<void> _stopAndProcess() async {
    if (_stopped) return;
    _stopped = true;

    _timer?.cancel();
    _timer = null;

    _realtimeAsr?.sendLastFrame();
    _realtimeAsr?.disconnect();
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _partialResultSubscription?.cancel();
    _partialResultSubscription = null;

    final duration = _recordingSeconds;

    FlutterForegroundTask.updateService(
      notificationTitle: 'Glimmer',
      notificationText: '正在处理日记...',
    );

    String? tosKey;

    try {
      final recordingResult = await _recorderService!.stopRecording();
      debugPrint('[FGS] stopRecording 完成: ${recordingResult.filePath}');

      // 步骤 1: 上传 OGG 到 TOS + Flash ASR
      FlutterForegroundTask.sendDataToMain({
        'event': 'processing',
        'step': 1,
      });
      AsrResult? asrResult;
      try {
        tosKey = await _tosService.uploadAudio(
          recordingResult.filePath,
          _folderId!,
        );
        debugPrint('[FGS] TOS 上传完成: $tosKey');

        final presignedUrl = await _tosService.getPresignedUrl(tosKey);
        debugPrint('[FGS] 预签名 URL 生成完成');

        asrResult = await _asrService.transcribeFromUrl(presignedUrl);
        await _storageService.writeTranscriptJson(
          _folderPath!,
          TranscriptData(version: 1, utterances: asrResult.utterances),
        );
        debugPrint('[FGS] Flash ASR 完成');
      } catch (e) {
        debugPrint('[FGS] TOS 上传或 ASR 失败: $e');
        await _saveEntry('未命名日记', duration);
        FlutterForegroundTask.sendDataToMain({
          'event': 'failed',
          'entryId': _folderId,
          'step': 1,
          'error': e.toString(),
        });
        return;
      }

      // 步骤 2: LLM 润色
      FlutterForegroundTask.sendDataToMain({
        'event': 'processing',
        'step': 2,
      });
      LlmResult? llmResult;
      try {
        llmResult = await _llmService.summarize(asrResult.utterances);
        await _storageService.writeLlmResult(
          _folderPath!,
          LlmResultData(
            version: 1,
            title: llmResult.title,
            content: llmResult.content,
            summary: llmResult.summary,
            outline: llmResult.outline,
            utterances: llmResult.utterances,
          ),
        );
        debugPrint('[FGS] LLM 完成');
      } catch (e) {
        debugPrint('[FGS] LLM 失败: $e');
        await _saveEntry('未命名日记', duration);
        FlutterForegroundTask.sendDataToMain({
          'event': 'failed',
          'entryId': _folderId,
          'step': 2,
          'error': e.toString(),
        });
        return;
      }

      // 步骤 3: 保存元数据
      FlutterForegroundTask.sendDataToMain({
        'event': 'processing',
        'step': 3,
      });
      final entry = DiaryEntry(
        id: _folderId!,
        title: llmResult.title,
        folderPath: _folderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
        tosKey: tosKey,
        audioFormat: 'ogg',
        uploadedAt: DateTime.now(),
      );
      await _storageService.createEntry(entry);
      debugPrint('[FGS] 元数据保存完成');

      // 步骤 4: 自动归类（失败不阻塞）
      FlutterForegroundTask.sendDataToMain({
        'event': 'processing',
        'step': 4,
      });
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
            await _storageService.autoTagDiary(_folderId!, matchedTagIds);
          }
        }
      } catch (e) {
        debugPrint('[FGS] 自动归类失败（不阻塞）: $e');
      }

      FlutterForegroundTask.sendDataToMain({
        'event': 'completed',
        'entryId': _folderId,
      });
    } catch (e) {
      debugPrint('[FGS] 处理异常: $e');
      FlutterForegroundTask.sendDataToMain({
        'event': 'error',
        'message': e.toString(),
      });
    }
  }

  Future<void> _saveEntry(String title, int duration) async {
    final entry = DiaryEntry(
      id: _folderId!,
      title: title,
      folderPath: _folderPath!,
      durationSeconds: duration,
      createdAt: DateTime.now(),
      audioFormat: 'ogg',
    );
    await _storageService.createEntry(entry);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 不使用 repeatEvent，所有逻辑在 onStart 和 onReceiveData 中
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic>) {
      final action = data['action'] as String?;
      if (action == 'stop') {
        _stopAndProcess();
      } else if (action == 'cancel') {
        _stopped = true;
        _timer?.cancel();
        _realtimeAsr?.disconnect();
        _recorderService?.dispose();
        FlutterForegroundTask.stopService();
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
    await _audioStreamSubscription?.cancel();
    await _partialResultSubscription?.cancel();
    _realtimeAsr?.disconnect();
    await _recorderService?.dispose();
    if (!_stopped) {
      FlutterForegroundTask.sendDataToMain({
        'event': 'error',
        'message': '录音服务被系统终止',
      });
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/recording_task_handler.dart
git commit -m "feat: 创建 RecordingTaskHandler，管理 FGS 隔离中的录音与处理流程"
```

---

### Task 3: 重构 RecordingPage 为 UI 壳

**Files:**
- Modify: `lib/pages/recording_page.dart`

将 RecordingPage 从"录音+处理"页面重构为纯 UI 壳。所有录音和后处理逻辑已在 TaskHandler 中。

关键变化：
- 移除 `_recorderService`、`_asrService`、`_llmService`、`_realtimeAsr`、`_tosService` 实例
- 添加 FGS 启动/停止逻辑
- 通过 `FlutterForegroundTask.addTaskDataCallback` 监听 TaskHandler 状态
- 保留 TTS 播报（在 UI isolate 中执行）
- 保留所有 UI 组件（AudioWaveform、RecordingButton、StepProgressIndicator、实时转写文本）

- [ ] **Step 1: 重写 RecordingPage**

用以下内容替换 `lib/pages/recording_page.dart` 的全部内容：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../services/diary_storage_service.dart';
import '../services/recording_task_handler.dart';
import '../services/tts_service.dart';
import '../widgets/app_title.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/recording_button.dart';
import '../widgets/step_progress_indicator.dart';
import 'diary_detail_page.dart';
import 'diary_list_page.dart';
import 'settings_page.dart';

enum RecordingState { idle, recording, processing }

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final _storageService = DiaryStorageService();
  final _ttsService = TtsService();
  final _uuid = const Uuid();

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  int _processingStep = 0;
  bool _hasError = false;
  String _errorMessage = '';

  String _realtimeText = '';
  final _realtimeScrollController = ScrollController();
  Stream<Amplitude>? _amplitudeStream;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'recording_channel',
        channelName: '录音服务',
        channelDescription: '录音和日记处理服务',
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _realtimeScrollController.dispose();
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    if (!mounted) return;

    final event = data['event'] as String?;
    switch (event) {
      case 'recording':
        setState(() {
          _recordingSeconds = data['duration'] as int? ?? _recordingSeconds;
        });
      case 'partial':
        setState(() {
          _realtimeText = data['text'] as String? ?? _realtimeText;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_realtimeScrollController.hasClients) {
            _realtimeScrollController.animateTo(
              _realtimeScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      case 'processing':
        setState(() {
          _processingStep = data['step'] as int? ?? _processingStep;
          _hasError = false;
        });
      case 'completed':
        _onCompleted(data['entryId'] as String);
      case 'failed':
        _onFailed(
          data['entryId'] as String?,
          data['step'] as int?,
          data['error'] as String?,
        );
      case 'error':
        setState(() {
          _hasError = true;
          _errorMessage = data['message'] as String? ?? '未知错误';
        });
        _stopForegroundTask();
    }
  }

  Future<void> _onCompleted(String? entryId) async {
    await _stopForegroundTask();
    if (entryId == null || !mounted) return;

    try {
      final entry = await _storageService.getEntryById(entryId);
      _speakSummary(entry);

      if (mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => DiaryDetailPage(entry: entry),
            ))
            .then((_) {
          _resetState();
        });
      }
    } catch (e) {
      debugPrint('导航到详情页失败: $e');
      _resetState();
    }
  }

  Future<void> _onFailed(
      String? entryId, int? step, String? error) async {
    await _stopForegroundTask();
    if (entryId == null || !mounted) return;

    try {
      final entry = await _storageService.getEntryById(entryId);
      if (mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => DiaryDetailPage(entry: entry),
            ))
            .then((_) {
          _resetState();
        });
      }
    } catch (e) {
      debugPrint('导航到详情页失败: $e');
      _resetState();
    }
  }

  void _resetState() {
    if (mounted) {
      setState(() {
        _state = RecordingState.idle;
        _hasError = false;
        _processingStep = 0;
        _recordingSeconds = 0;
        _realtimeText = '';
      });
    }
  }

  Future<void> _onTap() async {
    switch (_state) {
      case RecordingState.idle:
        await _startRecording();
      case RecordingState.recording:
        await _stopRecording();
      case RecordingState.processing:
        break;
    }
  }

  Future<void> _startRecording() async {
    final folderId = _uuid.v4();
    final folderPath =
        await _storageService.createDiaryFolder(folderId);

    // 通过 saveData 传递给 TaskHandler isolate
    await FlutterForegroundTask.saveData(key: 'folderId', value: folderId);
    await FlutterForegroundTask.saveData(
        key: 'folderPath', value: folderPath);

    // 启动 FGS
    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Glimmer',
      notificationText: '正在录音...',
      callback: startCallback,
      serviceTypes: [ForegroundServiceTypes.microphone],
    );

    if (result is ServiceRequestFailure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动前台服务失败: ${result.error}')),
        );
      }
      return;
    }

    setState(() {
      _state = RecordingState.recording;
      _recordingSeconds = 0;
      _realtimeText = '';
    });
  }

  Future<void> _stopRecording() async {
    setState(() => _state = RecordingState.processing);
    FlutterForegroundTask.sendDataToTask({'action': 'stop'});

    // TTS 应答
    _speakReply();
  }

  Future<void> _stopForegroundTask() async {
    await FlutterForegroundTask.stopService();
  }

  static const _replyTemplates = [
    '录音完成，我来帮你整理日记',
    '录音完成，日记整理马上就好',
    '录音完成，稍等我帮你整理一下',
    '录音完成，今天说了好多呢，我慢慢整理',
    '录音完成，放心交给我吧',
    '录音完成，内容收到，马上帮你整理成日记',
    '录音完成，让我想想怎么帮你写这篇日记',
    '录音完成，今天记录了不少呢，我来整理',
  ];

  void _speakReply() {
    () async {
      try {
        if (!await SettingsPage.isTtsEnabled()) return;
        final text = _replyTemplates[
            DateTime.now().millisecond % _replyTemplates.length];
        await _ttsService.speak(text, VoiceType.femaleSweet);
      } catch (e) {
        debugPrint('TTS 应答失败: $e');
      }
    }();
  }

  void _speakSummary(DiaryEntry entry) {
    () async {
      try {
        if (!await SettingsPage.isTtsEnabled()) return;
        if (!await _storageService.hasLlmResult(entry.folderPath)) return;
        final llmData =
            await _storageService.readLlmResult(entry.folderPath);
        if (llmData.outline.isEmpty) return;
        await _ttsService.speak(llmData.outline, VoiceType.maleDeep);
      } catch (e) {
        debugPrint('TTS 总结播报失败: $e');
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: const AppTitle(title: '语音日记'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DiaryListPage()),
                );
              },
            ),
          ],
        ),
        body: WillPopScope(
          onWillPop: () async {
            if (_state == RecordingState.recording) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('确认退出'),
                  content: const Text('录音进行中，退出将丢弃录音。确定退出吗？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('退出',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirmed == true) {
                FlutterForegroundTask.sendDataToTask({'action': 'cancel'});
                await _stopForegroundTask();
                return true;
              }
              return false;
            }
            return true;
          },
          child: Center(
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
                  AudioWaveform(
                    amplitudeStream: _amplitudeStream,
                    color: _state == RecordingState.recording
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                  ),
                  if (_realtimeText.isNotEmpty &&
                      _state == RecordingState.recording) ...[
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        controller: _realtimeScrollController,
                        child: Text(
                          _realtimeText,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  RecordingButton(
                    state: _state,
                    onTap: _onTap,
                    recordingSeconds: _recordingSeconds,
                  ),
                  if (_hasError) ...[
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        _resetState();
                      },
                      child: const Text('重新开始'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证编译**

Run: `flutter analyze`
Expected: 无编译错误。注意 `RecordingPage` 不再直接引用 `record`、`web_socket_channel` 等包。

- [ ] **Step 3: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "refactor: 重构 RecordingPage 为 FGS UI 壳，录音和处理逻辑移至 TaskHandler"
```

---

### Task 4: 处理 AmplitudeStream 适配

**Files:**
- Modify: `lib/services/recording_task_handler.dart`

当前 `AudioRecorderService.onAmplitudeChanged()` 依赖 `AudioRecorder` 实例。在 TaskHandler isolate 中获取 amplitude 需要通过消息发送给 UI。需要在 TaskHandler 的每秒定时器中获取 amplitude 并发送。

- [ ] **Step 1: 在 TaskHandler 中添加 amplitude 获取**

在 `recording_task_handler.dart` 的 `_startRecording` 方法中，修改定时器逻辑，添加 amplitude 监听。

在 `_startRecording` 方法中，`_timer` 创建前添加 amplitude 流监听：

```dart
      Stream<Amplitude>? amplitudeStream;
      try {
        amplitudeStream = _recorderService!
            .onAmplitudeChanged(const Duration(milliseconds: 80));
      } catch (_) {}

      final amplitudeSub = amplitudeStream?.listen((amp) {
        FlutterForegroundTask.sendDataToMain({
          'event': 'amplitude',
          'value': amp.current,
        });
      });
```

并在 `_stopAndProcess` 方法开头添加 `amplitudeSub?.cancel();`。

- [ ] **Step 2: 在 RecordingPage 中接收 amplitude**

在 `_onReceiveTaskData` 的 switch 中添加 `amplitude` 事件处理。

在 `_RecordingPageState` 中添加字段：

```dart
  double? _currentAmplitude;
```

在 `_onReceiveTaskData` 的 switch 中添加：

```dart
      case 'amplitude':
        _currentAmplitude = (data['value'] as num?)?.toDouble();
```

并将 `AudioWaveform` 的 `amplitudeStream` 替换为基于 `_currentAmplitude` 的方式。

由于 `AudioWaveform` 接受 `Stream<Amplitude>`，需要创建一个 `StreamController` 转发：

在 `_RecordingPageState` 中添加：

```dart
  final _amplitudeController = StreamController<Amplitude>.broadcast();
```

在 `amplitude` 事件中：

```dart
      case 'amplitude':
        final value = (data['value'] as num?)?.toDouble() ?? 0.0;
        _amplitudeController.add(Amplitude(current: value, max: 0.0));
```

在 `dispose` 中：

```dart
    _amplitudeController.close();
```

将 `AudioWaveform` 的 `amplitudeStream` 改为 `_amplitudeController.stream`。

- [ ] **Step 3: 验证编译**

Run: `flutter analyze`
Expected: 无编译错误

- [ ] **Step 4: 提交**

```bash
git add lib/services/recording_task_handler.dart lib/pages/recording_page.dart
git commit -m "feat: 通过 FGS 消息通道传递录音 amplitude 到 UI"
```

---

### Task 5: 真机测试与修复

**Files:**
- 可能修改: `lib/services/recording_task_handler.dart`
- 可能修改: `lib/pages/recording_page.dart`

这个任务需要在 Android 真机上验证。关键测试场景：

- [ ] **Step 1: 运行 dev flavor 构建并安装**

Run: `flutter run --flavor dev --dart-define=dev=true`

- [ ] **Step 2: 测试基础录音流程**

在 app 中点击录音按钮 → 录制几秒 → 点击停止 → 确认处理完成并跳转到详情页。验证：
- 通知栏显示"Glimmer — 正在录音..."
- 停止后通知变为"Glimmer — 正在处理日记..."
- 详情页显示正确的日记内容

- [ ] **Step 3: 测试锁屏场景**

开始录音 → 锁屏 → 等待 10+ 秒 → 解锁 → 停止录音 → 确认处理完成。

- [ ] **Step 4: 测试长录音**

录制 1 分钟以上，确认 Opus 编码和 OGG 文件正常。

- [ ] **Step 5: 修复发现的问题**

根据测试结果修复编译错误或运行时问题。常见问题：
- `flutter_dotenv` 在 TaskHandler isolate 中未初始化 → 需要在 `onStart` 中调用 `dotenv.load()`
- `path_provider` 在 isolate 中的路径问题
- `drift` 数据库在 isolate 中的初始化

- [ ] **Step 6: 提交修复**

```bash
git add -A
git commit -m "fix: 修复 FGS 真机测试中发现的问题"
```

---

## 自审

**1. Spec 覆盖检查：**
- 录音阶段（PCM 双路分发、Opus 编码、WebSocket ASR）→ Task 2 TaskHandler
- 处理阶段（TOS 上传、Flash ASR、LLM、保存、打标签）→ Task 2 TaskHandler
- 通信协议（6 种 event + 2 种 action）→ Task 2 + Task 3
- Android 权限和 Service 声明 → Task 1
- 通知（录音中/处理中）→ Task 2 TaskHandler
- RecordingPage UI 变更 → Task 3
- TTS 播报在 UI isolate → Task 3
- 返回键弹窗确认 → Task 3 WillPopScope
- 新增依赖 → Task 1

**2. Placeholder 扫描：** 无 TBD/TODO/待定内容。所有步骤包含完整代码。

**3. 类型一致性检查：**
- `RecordingState` 枚举在 Task 3 中定义为 `idle, recording, processing`，与 `recording_button.dart` 预期一致
- 通信消息使用 `Map<String, dynamic>`，event/action 字符串在 TaskHandler 和 RecordingPage 之间一致
- `DiaryEntry` 构造参数与 `diary_entry.dart` 定义匹配
- `FlutterForegroundTask.sendDataToMain` 和 `sendDataToTask` 签名与文档一致

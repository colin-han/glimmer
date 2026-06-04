import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart' show Amplitude;

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import 'asr_service.dart';
import 'audio_recorder_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'realtime_asr_service.dart';
import 'tos_upload_service.dart';

/// 前台服务入口函数，必须为顶层函数并标注 @pragma('vm:entry-point')
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// 录音 + 处理的 TaskHandler，运行在独立 Dart isolate 中。
///
/// 所有 service 实例必须在此内部创建，不能从 UI 传入。
/// 通过 [FlutterForegroundTask.saveData] 向 UI 传递状态（轮询方式），
/// 通过 [onReceiveData] 接收 UI 的 stop 指令。
class RecordingTaskHandler extends TaskHandler {
  // --- 内部创建的 service 实例 ---
  AudioRecorderService? _recorderService;
  RealtimeAsrService? _realtimeAsr;
  final _asrService = AsrService();
  final _tosService = TosUploadService();
  final _llmService = LlmService();
  final _storageService = DiaryStorageService();

  // --- 状态 ---
  String? _folderId;
  String? _folderPath;
  bool _stopRequested = false;
  Timer? _durationTimer;
  int _recordingSeconds = 0;
  StreamSubscription<Uint8List>? _audioStreamSub;
  StreamSubscription<String>? _partialResultSub;
  StreamSubscription<Amplitude>? _amplitudeSub;

  /// 保存事件状态供 UI 轮询读取
  Future<void> _emit(String event, {int? duration, int? step, String? entryId, String? error}) async {
    await FlutterForegroundTask.saveData(key: 'taskEvent', value: event);
    if (duration != null) {
      await FlutterForegroundTask.saveData(key: 'taskDuration', value: duration);
    }
    if (step != null) {
      await FlutterForegroundTask.saveData(key: 'taskStep', value: step);
    }
    if (entryId != null) {
      await FlutterForegroundTask.saveData(key: 'taskEntryId', value: entryId);
    }
    if (error != null) {
      await FlutterForegroundTask.saveData(key: 'taskError', value: error);
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] onStart, starter=${starter.name}');

    // flutter_dotenv 在 TaskHandler isolate 中未初始化，需手动加载
    try {
      await dotenv.load(fileName: '.env.local');
    } catch (e) {
      debugPrint('[TaskHandler] dotenv.load 失败: $e');
    }

    // 从 UI 保存的数据中读取 folderId 和 folderPath
    _folderId = await FlutterForegroundTask.getData(key: 'folderId') as String?;
    _folderPath = await FlutterForegroundTask.getData(key: 'folderPath') as String?;

    if (_folderId == null || _folderPath == null) {
      debugPrint('[TaskHandler] 缺少 folderId 或 folderPath，无法启动');
      await _emit('failed', entryId: _folderId ?? '', step: 0, error: '缺少 folderId 或 folderPath');
      return;
    }

    // 更新通知
    FlutterForegroundTask.updateService(
      notificationTitle: '正在录音',
      notificationText: '语音日记 - 录音中...',
    );

    try {
      // 创建并启动录音服务
      _recorderService = AudioRecorderService();
      await _recorderService!.startRecording(_folderPath!);

      // 连接实时 ASR（失败不阻塞录音）
      _connectRealtimeAsr();

      // 监听 PCM 流，发送给实时 ASR
      _audioStreamSub = _recorderService!.audioStream.listen((pcmData) {
        if (_realtimeAsr?.isConnected == true) {
          _realtimeAsr!.sendAudio(pcmData);
        }
      });

      // 监听振幅，保存供 UI 读取
      _amplitudeSub = _recorderService!
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        FlutterForegroundTask.saveData(key: 'taskAmplitude', value: amp.current);
      });

      // 启动计时器
      _recordingSeconds = 0;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _recordingSeconds++;

        // 保存录音时长供 UI 轮询
        _emit('recording', duration: _recordingSeconds);

        // 更新通知文字
        final minutes = _recordingSeconds ~/ 60;
        final seconds = _recordingSeconds % 60;
        FlutterForegroundTask.updateService(
          notificationTitle: '正在录音',
          notificationText:
              '语音日记 - $minutes:${seconds.toString().padLeft(2, '0')}',
        );

        // 最长 5 分钟自动停止
        if (_recordingSeconds >= 300 && !_stopRequested) {
          _requestStop();
        }
      });

      await _emit('recording', duration: 0);
      debugPrint('[TaskHandler] 录音启动成功');
    } catch (e) {
      debugPrint('[TaskHandler] 录音启动失败: $e');
      await _emit('failed', entryId: _folderId ?? '', step: 0, error: '录音启动失败: $e');
    }
  }

  void _connectRealtimeAsr() {
    _realtimeAsr = RealtimeAsrService();
    _realtimeAsr!.connect().catchError((e) {
      debugPrint('[TaskHandler] 实时 ASR 连接失败（不阻塞录音）: $e');
    });

    _partialResultSub = _realtimeAsr!.onPartialResult.listen((text) {
      FlutterForegroundTask.saveData(key: 'taskPartial', value: text);
    });
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['action'] == 'stop') {
      _requestStop();
    }
  }

  // eventAction 设为 nothing()，此回调不会被触发，但需实现
  @override
  void onRepeatEvent(DateTime timestamp) {}

  /// 收到 stop 指令后停止录音并开始处理
  void _requestStop() {
    if (_stopRequested) return;
    _stopRequested = true;
    _processRecording();
  }

  /// 停止录音后执行完整处理流程
  Future<void> _processRecording() async {
    debugPrint('[TaskHandler] 开始处理流程');

    // 停止计时和振幅监听
    _durationTimer?.cancel();
    _durationTimer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    // 停止实时 ASR
    _realtimeAsr?.sendLastFrame();
    _realtimeAsr?.disconnect();
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _partialResultSub?.cancel();
    _partialResultSub = null;

    final duration = _recordingSeconds;

    // 通知 UI 进入 processing 状态
    await _emit('processing', step: 0);

    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 处理中...',
    );

    String? tosKey;
    String? audioFilePath;

    // --- 停止录音 ---
    try {
      final recordingResult = await _recorderService!.stopRecording();
      audioFilePath = recordingResult.filePath;
      debugPrint(
          '[TaskHandler] stopRecording 完成: ${recordingResult.durationSeconds}s');
    } catch (e) {
      debugPrint('[TaskHandler] stopRecording 失败: $e');
    }

    // --- 步骤 1: 上传 TOS + Flash ASR ---
    await _emit('processing', step: 1);
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 语音识别...',
    );

    AsrResult? asrResult;
    try {
      if (audioFilePath != null) {
        tosKey = await _tosService.uploadAudio(audioFilePath, _folderId!);
        debugPrint('[TaskHandler] TOS 上传完成: $tosKey');

        final presignedUrl = await _tosService.getPresignedUrl(tosKey);
        debugPrint('[TaskHandler] 预签名 URL 生成完成');

        asrResult = await _asrService.transcribeFromUrl(presignedUrl);
        await _storageService.writeTranscriptJson(
          _folderPath!,
          TranscriptData(version: 1, utterances: asrResult.utterances),
        );
        debugPrint('[TaskHandler] Flash ASR 完成');
      }
    } catch (e) {
      debugPrint('[TaskHandler] TOS 上传或 ASR 失败: $e');
      // ASR 失败，保存为未命名日记
      await _saveMinimalEntry('未命名日记', duration);
      await _emit('failed', entryId: _folderId!, step: 1, error: '语音识别失败: $e');
      return;
    }

    if (asrResult == null) {
      debugPrint('[TaskHandler] ASR 结果为空');
      await _saveMinimalEntry('未命名日记', duration);
      await _emit('failed', entryId: _folderId!, step: 1, error: '语音识别结果为空');
      return;
    }

    // --- 步骤 2: LLM 润色 ---
    await _emit('processing', step: 2);
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - AI 总结...',
    );

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
      debugPrint('[TaskHandler] LLM summarize 完成');
    } catch (e) {
      debugPrint('[TaskHandler] LLM 失败: $e');
      // LLM 失败，保存为未命名日记
      await _saveMinimalEntry('未命名日记', duration);
      await _emit('failed', entryId: _folderId!, step: 2, error: 'AI 总结失败: $e');
      return;
    }

    // --- 步骤 3: 保存元数据 ---
    await _emit('processing', step: 3);
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 保存数据...',
    );

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
    debugPrint('[TaskHandler] 保存元数据完成');

    // --- 步骤 4: 自动归类（非阻塞） ---
    await _emit('processing', step: 4);
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 自动归类...',
    );

    try {
      final allTags = await _storageService.getAllTags();
      final tagsWithPrompt =
          allTags.where((t) => t.matchPrompt.isNotEmpty).toList();
      if (tagsWithPrompt.isNotEmpty) {
        final tagInfos = tagsWithPrompt
            .map((t) =>
                TagInfo(id: t.id, name: t.name, matchPrompt: t.matchPrompt))
            .toList();
        final matchedTagIds =
            await _llmService.matchTags(llmResult.content, tagInfos);
        if (matchedTagIds.isNotEmpty) {
          await _storageService.autoTagDiary(_folderId!, matchedTagIds);
        }
        debugPrint(
            '[TaskHandler] 自动归类完成: 匹配 ${matchedTagIds.length} 个标签');
      }
    } catch (e) {
      debugPrint('[TaskHandler] 自动归类失败（不阻塞）: $e');
    }

    // --- 完成 ---
    FlutterForegroundTask.updateService(
      notificationTitle: '处理完成',
      notificationText: '语音日记 - ${llmResult.title}',
    );

    debugPrint('[TaskHandler] 发送 completed 事件');
    await _emit('completed', entryId: _folderId!);
  }

  /// 保存最小元数据条目（用于失败场景）
  Future<void> _saveMinimalEntry(String title, int duration) async {
    try {
      final entry = DiaryEntry(
        id: _folderId!,
        title: title,
        folderPath: _folderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
        audioFormat: 'ogg',
      );
      await _storageService.createEntry(entry);
      debugPrint('[TaskHandler] 已保存最小元数据条目');
    } catch (e) {
      debugPrint('[TaskHandler] 保存最小元数据失败: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[TaskHandler] onDestroy, isTimeout=$isTimeout');

    _durationTimer?.cancel();
    await _amplitudeSub?.cancel();
    await _audioStreamSub?.cancel();
    await _partialResultSub?.cancel();

    _realtimeAsr?.disconnect();
    await _recorderService?.dispose();
  }
}

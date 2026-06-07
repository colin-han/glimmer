import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart' show Amplitude;
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import 'asr_service.dart';
import 'audio_recorder_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'location_service.dart';
import 'realtime_asr_service.dart';
import 'tos_upload_service.dart';
import 'tts_service.dart';
import 'weather_service.dart';

/// 前台服务入口函数，必须为顶层函数并标注 @pragma('vm:entry-point')
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// 录音 + 处理的 TaskHandler，运行在独立 Dart isolate 中（老张）。
///
/// 承担所有职责：建文件夹、天气获取、录音、ASR、LLM、保存、TTS、通知管理。
/// 通过 [FlutterForegroundTask.sendDataToMain] 向 UI（小丽）传递实时状态。
class RecordingTaskHandler extends TaskHandler {
  // --- 内部创建的 service 实例 ---
  AudioRecorderService? _recorderService;
  RealtimeAsrService? _realtimeAsr;
  final _asrService = AsrService();
  final _tosService = TosUploadService();
  final _llmService = LlmService();
  final _storageService = DiaryStorageService();
  final _locationService = LocationService();
  final _weatherService = WeatherService();
  final _ttsService = TtsService();
  final _uuid = const Uuid();

  // --- 状态 ---
  String? _folderId;
  String? _folderPath;
  bool _stopRequested = false;
  Timer? _durationTimer;
  int _recordingSeconds = 0;
  StreamSubscription? _audioStreamSub;
  StreamSubscription? _partialResultSub;
  StreamSubscription<Amplitude>? _amplitudeSub;

  // 当前阶段（用于通知点击时告诉 UI 该跳哪个页面）
  String _currentState = 'recording'; // recording | processing | completed | failed

  // 天气/位置（异步获取，处理阶段使用）
  WeatherLocation? _weatherLocation;
  ({double lat, double lon})? _location;

  /// 向 UI 发送消息
  void _sendToMain(Map<String, dynamic> data) {
    FlutterForegroundTask.sendDataToMain(data);
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
    _folderPath =
        await FlutterForegroundTask.getData(key: 'folderPath') as String?;

    if (_folderId == null) {
      // UI 没有传 folderId，自己生成
      _folderId = _uuid.v4();
      _folderPath = await _storageService.createDiaryFolder(_folderId!);
      debugPrint('[TaskHandler] 自动创建文件夹: $_folderId');
    } else if (_folderPath == null) {
      _folderPath = await _storageService.createDiaryFolder(_folderId!);
    }

    _currentState = 'recording';

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

      // 监听振幅，发送给 UI
      _amplitudeSub = _recorderService!
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        _sendToMain({'type': 'amplitude', 'value': amp.current});
      });

      // 启动计时器
      _recordingSeconds = 0;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _recordingSeconds++;

        // 发送录音时长给 UI
        _sendToMain({'type': 'recording', 'duration': _recordingSeconds});

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

      _sendToMain({'type': 'recording', 'duration': 0});
      debugPrint('[TaskHandler] 录音启动成功');

      // 异步获取天气和位置（不阻塞录音）
      _fetchWeatherInBackground();
    } catch (e) {
      debugPrint('[TaskHandler] 录音启动失败: $e');
      _currentState = 'failed';
      _sendToMain({
        'type': 'failed',
        'entryId': _folderId ?? '',
        'step': 0,
        'error': '录音启动失败: $e',
      });
      FlutterForegroundTask.updateService(
        notificationTitle: '处理失败',
        notificationText: '语音日记 - 录音启动失败',
      );
    }
  }

  void _connectRealtimeAsr() {
    _realtimeAsr = RealtimeAsrService();
    _realtimeAsr!.connect().catchError((e) {
      debugPrint('[TaskHandler] 实时 ASR 连接失败（不阻塞录音）: $e');
    });

    _partialResultSub = _realtimeAsr!.onPartialResult.listen((text) {
      _sendToMain({'type': 'partialText', 'text': text});
    });
  }

  void _fetchWeatherInBackground() {
    () async {
      try {
        final loc = await _locationService.getCurrentLocation();
        if (loc == null) return;
        _location = loc;
        _weatherLocation =
            await _weatherService.fetchWeatherAndLocation(loc.lat, loc.lon);
        if (_weatherLocation != null) {
          _sendToMain({
            'type': 'weather',
            'icon': _weatherLocation!.icon,
            'text': _weatherLocation!.text,
            'temp': _weatherLocation!.temp,
            'locationName': _weatherLocation!.locationName,
          });
        }
      } catch (e) {
        debugPrint('[TaskHandler] 天气获取失败（不阻塞）: $e');
      }
    }();
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
    _currentState = 'processing';

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

    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 处理中...',
    );

    // 先创建 processing 状态的数据库记录，日记列表立即可见
    try {
      final processingEntry = DiaryEntry(
        id: _folderId!,
        title: '正在处理中...',
        folderPath: _folderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
        audioFormat: 'ogg',
        status: EntryStatus.processing,
        weatherIcon: _weatherLocation?.icon,
        weatherText: _weatherLocation?.text,
        temperature: _weatherLocation?.temp,
        locationName: _weatherLocation?.locationName,
        locationLat: _location?.lat,
        locationLon: _location?.lon,
      );
      await _storageService.createEntry(processingEntry);
      debugPrint('[TaskHandler] processing 条目已创建');
    } catch (e) {
      debugPrint('[TaskHandler] 创建 processing 条目失败: $e');
    }

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
    _sendToMain({'type': 'processing', 'step': 1});
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
      await _saveMinimalEntry('未命名日记', duration);
      _currentState = 'failed';
      _sendToMain({
        'type': 'failed',
        'entryId': _folderId!,
        'step': 1,
        'error': '语音识别失败: $e',
      });
      FlutterForegroundTask.updateService(
        notificationTitle: '处理失败',
        notificationText: '语音日记 - 语音识别失败',
      );
      await _stopService();
      return;
    }

    if (asrResult == null) {
      debugPrint('[TaskHandler] ASR 结果为空');
      await _saveMinimalEntry('未命名日记', duration);
      _currentState = 'failed';
      _sendToMain({
        'type': 'failed',
        'entryId': _folderId!,
        'step': 1,
        'error': '语音识别结果为空',
      });
      FlutterForegroundTask.updateService(
        notificationTitle: '处理失败',
        notificationText: '语音日记 - 语音识别结果为空',
      );
      await _stopService();
      return;
    }

    // --- 步骤 2: LLM 润色 ---
    _sendToMain({'type': 'processing', 'step': 2});
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
      await _saveMinimalEntry('未命名日记', duration);
      _currentState = 'failed';
      _sendToMain({
        'type': 'failed',
        'entryId': _folderId!,
        'step': 2,
        'error': 'AI 总结失败: $e',
      });
      FlutterForegroundTask.updateService(
        notificationTitle: '处理失败',
        notificationText: '语音日记 - AI 总结失败',
      );
      await _stopService();
      return;
    }

    // --- 步骤 3: 保存元数据 ---
    _sendToMain({'type': 'processing', 'step': 3});
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
      weatherIcon: _weatherLocation?.icon,
      weatherText: _weatherLocation?.text,
      temperature: _weatherLocation?.temp,
      locationName: _weatherLocation?.locationName,
      locationLat: _location?.lat,
      locationLon: _location?.lon,
    );
    await _storageService.createEntry(entry);
    debugPrint('[TaskHandler] 保存元数据完成');

    // --- 步骤 4: 自动归类（非阻塞） ---
    _sendToMain({'type': 'processing', 'step': 4});
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
    _currentState = 'completed';
    FlutterForegroundTask.updateService(
      notificationTitle: '处理完成',
      notificationText: '语音日记 - ${llmResult.title}',
    );

    debugPrint('[TaskHandler] 发送 completed 事件');
    _sendToMain({'type': 'completed', 'entryId': _folderId!});

    // TTS 播报
    await _speakReply();

    await _stopService();
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

  Future<void> _speakReply() async {
    try {
      final text = _replyTemplates[DateTime.now().millisecond % _replyTemplates.length];
      debugPrint('[TaskHandler] TTS 播报: "$text"');
      await _ttsService.speak(text, VoiceType.femaleSweet);
    } catch (e) {
      debugPrint('[TaskHandler] TTS 播报失败（不阻塞）: $e');
    }
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
        weatherIcon: _weatherLocation?.icon,
        weatherText: _weatherLocation?.text,
        temperature: _weatherLocation?.temp,
        locationName: _weatherLocation?.locationName,
        locationLat: _location?.lat,
        locationLon: _location?.lon,
      );
      await _storageService.createEntry(entry);
      debugPrint('[TaskHandler] 已保存最小元数据条目');
    } catch (e) {
      debugPrint('[TaskHandler] 保存最小元数据失败: $e');
    }
  }

  /// 延迟后停止服务
  Future<void> _stopService() async {
    await Future.delayed(const Duration(seconds: 2));
    FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationPressed() {
    debugPrint('[TaskHandler] 通知被点击, state=$_currentState');
    FlutterForegroundTask.launchApp('/');
    _sendToMain({
      'type': 'notificationPressed',
      'state': _currentState,
      'entryId': _folderId ?? '',
    });
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

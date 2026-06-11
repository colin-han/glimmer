import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart' show Amplitude;
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
import 'audio_recorder_service.dart';
import 'diary_storage_service.dart';
import 'location_service.dart';
import 'realtime_asr_service.dart';
import 'weather_service.dart';

/// 前台服务入口函数，必须为顶层函数并标注 @pragma('vm:entry-point')
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// 录音 TaskHandler，运行在独立 Dart isolate 中。
///
/// 只负责录音阶段：建文件夹、天气获取、录音。
/// 录音结束后保存音频文件、INSERT DB 条目、通知主 isolate、停止 FGS。
/// ASR/LLM/TOS 等处理由 ProcessingTaskHandler 负责。
class RecordingTaskHandler extends TaskHandler {
  // --- 内部创建的 service 实例 ---
  AudioRecorderService? _recorderService;
  RealtimeAsrService? _realtimeAsr;
  final _storageService = DiaryStorageService();
  final _locationService = LocationService();
  final _weatherService = WeatherService();
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

  // 天气/位置（异步获取，创建条目时使用）
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

  /// 收到 stop 指令后停止录音，创建 DB 条目，通知主 isolate
  void _requestStop() {
    if (_stopRequested) return;
    _stopRequested = true;

    () async {
      try {
        // 停止计时和监听
        _durationTimer?.cancel();
        _durationTimer = null;
        await _amplitudeSub?.cancel();
        _amplitudeSub = null;
        _realtimeAsr?.sendLastFrame();
        _realtimeAsr?.disconnect();
        await _audioStreamSub?.cancel();
        _audioStreamSub = null;
        await _partialResultSub?.cancel();
        _partialResultSub = null;

        // 停止录音
        int duration = _recordingSeconds;
        try {
          final result = await _recorderService!.stopRecording();
          duration = result.durationSeconds;
        } catch (e) {
          debugPrint('[TaskHandler] stopRecording 失败: $e');
        }

        // 创建 DB 条目
        await _storageService.createEntry(DiaryEntry(
          id: _folderId!,
          title: '正在处理中...',
          folderPath: _folderPath!,
          durationSeconds: duration,
          createdAt: DateTime.now(),
          audioFormat: 'ogg',
          status: EntryStatus.processing,
          processingStage: ProcessingStage.uploading,
          weatherIcon: _weatherLocation?.icon,
          weatherText: _weatherLocation?.text,
          temperature: _weatherLocation?.temp,
          locationName: _weatherLocation?.locationName,
          locationLat: _location?.lat,
          locationLon: _location?.lon,
        ));

        debugPrint('[TaskHandler] 录音完成，已创建 DB 条目');

        // 通知主 isolate
        _sendToMain({'type': 'recordingComplete', 'entryId': _folderId!});
      } catch (e) {
        debugPrint('[TaskHandler] 停止录音异常: $e');
        _sendToMain({
          'type': 'failed',
          'entryId': _folderId ?? '',
          'step': 0,
          'error': '停止录音失败: $e',
        });
      } finally {
        await _stopService();
      }
    }();
  }

  /// 延迟后停止服务
  Future<void> _stopService() async {
    await Future.delayed(const Duration(seconds: 2));
    FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationPressed() {
    debugPrint('[TaskHandler] 通知被点击');
    FlutterForegroundTask.launchApp('/');
    _sendToMain({
      'type': 'notificationPressed',
      'state': 'recording',
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

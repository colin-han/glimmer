import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart' show Amplitude, AudioRecorder;

import '../models/diary_entry.dart';
import '../services/diary_storage_service.dart';
import '../services/recording_processor.dart' show processingCallback;
import '../services/recording_task_handler.dart';
import '../services/weather_service.dart';
import '../widgets/app_title.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/recording_button.dart';
import 'diary_detail_page.dart';
import 'diary_list_page.dart';
import 'settings_page.dart';

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final _storageService = DiaryStorageService();

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  String _realtimeText = '';
  int _processingCount = 0;
  final _realtimeScrollController = ScrollController();
  WeatherLocation? _currentWeatherLocation;

  // 振幅流（从 FGS 接收振幅数据，转为 Stream<Amplitude> 给波形组件）
  final _amplitudeController = StreamController<Amplitude>.broadcast();

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _refreshProcessingCount();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _amplitudeController.close();
    _realtimeScrollController.dispose();
    super.dispose();
  }

  /// 接收老张（FGS）发来的消息
  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    if (!mounted) return;

    final type = data['type'] as String;
    switch (type) {
      case 'recording':
        setState(() => _recordingSeconds = data['duration'] as int);
      case 'amplitude':
        final value = data['value'] as double;
        _amplitudeController.add(Amplitude(current: value, max: value));
      case 'partialText':
        setState(() {
          _realtimeText = data['text'] as String;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_realtimeScrollController.hasClients) {
              _realtimeScrollController.animateTo(
                _realtimeScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          });
        });
      case 'weather':
        setState(() {
          _currentWeatherLocation = WeatherLocation(
            icon: data['icon'] as String,
            text: data['text'] as String,
            temp: data['temp'] as String,
            locationName: data['locationName'] as String,
          );
        });
      case 'recordingComplete':
        // 录音完成，启动 Processing FGS
        _startProcessingFgs();
      case 'completed':
      case 'failed':
        // 处理完成或失败时刷新 Badge 数量
        _refreshProcessingCount();
      case 'notificationPressed':
        _handleNotificationPressed(data);
    }
  }

  /// 通知点击：根据状态跳转到对应页面
  Future<void> _handleNotificationPressed(Map<String, dynamic> data) async {
    final state = data['state'] as String;
    final entryId = data['entryId'] as String;

    if (!mounted) return;

    switch (state) {
      case 'recording':
        // 已在录音页面，不需要跳转
        break;
      case 'processing':
        // 跳转到日记列表页面
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DiaryListPage()),
        );
      case 'completed':
        // 跳转到日记详情页，自动播放 summary
        await _navigateToDetailAndPlay(entryId);
      case 'failed':
        // 跳转到日记详情页
        await _navigateToDetail(entryId);
    }
  }

  Future<void> _navigateToDetail(String entryId) async {
    try {
      final entry = await _storageService.getEntryById(entryId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: entry)),
      );
    } catch (e) {
      debugPrint('[RecordingPage] 跳转详情页失败: $e');
    }
  }

  Future<void> _navigateToDetailAndPlay(String entryId) async {
    try {
      final entry = await _storageService.getEntryById(entryId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DiaryDetailPage(entry: entry, autoPlaySummary: true),
        ),
      );
    } catch (e) {
      debugPrint('[RecordingPage] 跳转详情页失败: $e');
    }
  }

  void _onTap() {
    switch (_state) {
      case RecordingState.idle:
        _startRecording();
      case RecordingState.recording:
        _stopRecording();
      default:
        break;
    }
  }

  Future<void> _startRecording() async {
    try {
      // 检查麦克风权限（Android 15+ 启动 microphone FGS 前必须已授权）
      if (!await AudioRecorder().hasPermission()) {
        _showError('需要麦克风权限才能录音');
        return;
      }

      // 先停止可能正在运行的 Processing FGS
      FlutterForegroundTask.stopService();

      // 设置通信端口
      FlutterForegroundTask.initCommunicationPort();

      // 启动 FGS（老张负责建文件夹、录音、天气等所有事情）
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: '正在录音',
        notificationText: '语音日记 - 录音中...',
        callback: startCallback,
      );

      if (result is ServiceRequestFailure) {
        throw Exception(result.error);
      }

      setState(() => _state = RecordingState.recording);
    } catch (e) {
      _showError('录音启动失败：$e');
    }
  }

  void _stopRecording() {
    FlutterForegroundTask.sendDataToTask({'action': 'stop'});
    // 立刻回到 idle，老张在后台处理
    setState(() {
      _state = RecordingState.idle;
      _recordingSeconds = 0;
      _realtimeText = '';
      _currentWeatherLocation = null;
    });
    // 停止录音后刷新处理中数量
    _refreshProcessingCount();
  }

  Future<void> _startProcessingFgs() async {
    try {
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '正在处理',
        notificationText: '语音日记 - 处理中...',
        callback: processingCallback,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[RecordingPage] 启动 Processing FGS 失败: ${result.error}');
      }
      _refreshProcessingCount();
    } catch (e) {
      debugPrint('[RecordingPage] 启动 Processing FGS 异常: $e');
    }
  }

  /// 刷新处理中的日记数量
  Future<void> _refreshProcessingCount() async {
    try {
      final count = await _storageService.getProcessingEntryCount();
      if (mounted) {
        setState(() => _processingCount = count);
      }
    } catch (_) {}
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
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
            Badge(
              label: Text('$_processingCount'),
              isLabelVisible: _processingCount > 0,
              child: IconButton(
                icon: const Icon(Icons.history),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DiaryListPage()),
                  );
                  // 从列表页返回后刷新处理中数量
                  _refreshProcessingCount();
                },
              ),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AudioWaveform(
                  amplitudeStream: _state == RecordingState.recording
                      ? _amplitudeController.stream
                      : null,
                  color: _state == RecordingState.recording
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
                ),
                if (_currentWeatherLocation != null &&
                    _state == RecordingState.recording) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_currentWeatherLocation!.locationName}  ${DiaryEntry.weatherEmoji(_currentWeatherLocation!.icon) ?? _currentWeatherLocation!.text} ${_currentWeatherLocation!.temp}°',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart' show Amplitude, AudioRecorder;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../design_tokens.dart';
import '../exceptions.dart';
import '../models/audio_input_device.dart';
import '../models/diary_entry.dart';
import '../models/processing_task.dart' as task_model;
import '../services/audio_device_service.dart';
import '../services/diary_storage_service.dart';
import '../services/fgs_runtime.dart';
import '../services/processing_fgs_controller.dart';
import '../services/recording_task_handler.dart';
import '../services/weather_service.dart';
import '../main.dart';
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
  final _realtimeScrollController = ScrollController();
  WeatherLocation? _currentWeatherLocation;
  AudioInputDevice? _currentInputDevice;

  // 振幅流（从 FGS 接收振幅数据，转为 Stream<Amplitude> 给波形组件）
  final _amplitudeController = StreamController<Amplitude>.broadcast();

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    // 订阅 store：active task 数量变化时刷新 badge
    processingTaskStore.activeRefIds.addListener(_onStoreChange);
    ProcessingFgsController.schedule(isStartup: true);
  }

  @override
  void dispose() {
    processingTaskStore.activeRefIds.removeListener(_onStoreChange);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _amplitudeController.close();
    _realtimeScrollController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  /// 接收老张（FGS）发来的消息
  Future<void> _onTaskData(Object data) async {
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
        // 录音完成，重置 recording mode，入队 diary task
        FgsRuntime.setNone();
        final entryId = data['entryId'] as String?;
        if (entryId != null) {
          await processingTaskStore.enqueueTask(
            taskType: task_model.TaskType.diary,
            refId: entryId,
            stage: 'uploading',
          );
        }
      case 'processingDone':
        // Processing FGS 结束（无论是否有条目被处理）
        ProcessingFgsController.onStopped();
      case 'completed':
      case 'failed':
        // 处理完成或失败：store 已移除 active task，listener 自动刷新 badge
        ProcessingFgsController.onStopped();
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
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DiaryListPage()));
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
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: entry)));
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
      case RecordingState.processing:
        // processing 状态下不响应点击（等待自动恢复录音）
        break;
    }
  }

  Future<void> _startRecording() async {
    // 有 processing 活动（在跑 or 待延时启动）→ 停掉并等它停稳
    final ha = ProcessingFgsController.hasActivity;
    debugPrint('[Rec] _startRecording: hasActivity=$ha');
    if (ha) {
      setState(() => _state = RecordingState.processing);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已暂停后台处理，录音结束后自动继续')));
      await ProcessingFgsController.stop(); // 内部取消 timer + 停 FGS + 等停（含超时兜底）
      debugPrint('[Rec] _startRecording: controller.stop() 已返回');
    }
    await _doStartRecording();
  }

  /// 实际启动录音（权限检查 + FGS 启动）
  Future<void> _doStartRecording() async {
    try {
      // 检查麦克风权限（Android 15+ 启动 microphone FGS 前必须已授权）
      if (!await AudioRecorder().hasPermission()) {
        _showError('需要麦克风权限才能录音');
        setState(() => _state = RecordingState.idle);
        return;
      }

      // 设置通信端口
      FlutterForegroundTask.initCommunicationPort();
      debugPrint('[Rec] _doStartRecording: 准备 startService(microphone)');

      // 启动 Recording FGS
      var result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: '正在录音',
        notificationText: '语音日记 - 录音中...',
        callback: startCallback,
      );
      debugPrint('[Rec] startService(microphone) result=$result');

      // 竞态兜底：可能 processing FGS 刚启动（controller.start delay 期间 FGS 槽被占），
      // 导致 microphone startService 报 ServiceAlreadyStartedException。
      // 强制 stopService + 等 500ms + 重试一次。
      if (result is ServiceRequestFailure) {
        debugPrint(
          '[Rec] startService 失败（${result.error}），强制 stopService + 重试',
        );
        FlutterForegroundTask.stopService();
        await Future.delayed(const Duration(milliseconds: 500));
        result = await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.microphone],
          notificationTitle: '正在录音',
          notificationText: '语音日记 - 录音中...',
          callback: startCallback,
        );
        debugPrint('[Rec] 重试 startService(microphone) result=$result');
      }

      if (result is ServiceRequestFailure) {
        throw RecordingException(result.error.toString());
      }

      setState(() => _state = RecordingState.recording);
      FgsRuntime.setRecording();
      WakelockPlus.enable();

      // 查询当前录音输入设备（失败/为 null 则不显示 pill）
      final device = await AudioDeviceService().getCurrentInputDevice();
      if (mounted && device != null && _state == RecordingState.recording) {
        setState(() => _currentInputDevice = device);
      }
    } catch (e) {
      debugPrint('[Rec] _doStartRecording 失败: $e');
      _showError('录音启动失败：$e');
      setState(() => _state = RecordingState.idle);
    }
  }

  void _stopRecording() {
    FlutterForegroundTask.sendDataToTask({'action': 'stop'});
    WakelockPlus.disable();
    // 立刻回到 idle，老张在后台处理
    setState(() {
      _state = RecordingState.idle;
      _recordingSeconds = 0;
      _realtimeText = '';
      _currentWeatherLocation = null;
      _currentInputDevice = null;
    });
    // 注意：不在此处启动 Processing FGS，等收到 recordingComplete 后延迟调度
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Badge(
                offset: const Offset(-8, 4),
                label: Text('${processingTaskStore.activeCount}'),
                isLabelVisible: processingTaskStore.activeCount > 0,
                child: IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DiaryListPage()),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 波形
                AudioWaveform(
                  amplitudeStream: _state == RecordingState.recording
                      ? _amplitudeController.stream
                      : null,
                  color: _state == RecordingState.recording
                      ? Colors.red
                      : WarmTokens.warmAmber,
                ),

                // 天气信息 pill
                if (_currentWeatherLocation != null &&
                    _state == RecordingState.recording) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: WarmTokens.warmSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: WarmTokens.warmDivider.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      '${_currentWeatherLocation!.locationName}  ${DiaryEntry.weatherEmoji(_currentWeatherLocation!.icon) ?? _currentWeatherLocation!.text} ${_currentWeatherLocation!.temp}°',
                      style: TextStyle(
                        fontSize: 12,
                        color: WarmTokens.warmMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],

                // 实时识别文本
                if (_realtimeText.isNotEmpty &&
                    _state == RecordingState.recording) ...[
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: WarmTokens.warmSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: WarmTokens.warmDivider.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: SingleChildScrollView(
                      controller: _realtimeScrollController,
                      child: Text(
                        _realtimeText,
                        style: TextStyle(
                          fontSize: 15,
                          color: WarmTokens.warmBrown,
                          height: 1.7,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 36),
                // 录音按钮
                RecordingButton(
                  state: _state,
                  onTap: _onTap,
                  recordingSeconds: _recordingSeconds,
                ),

                // 当前录音输入设备 pill（录音按钮下方）
                if (_state == RecordingState.recording &&
                    _currentInputDevice != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: WarmTokens.warmSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: WarmTokens.warmDivider.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      '${_currentInputDevice!.emoji} ${_currentInputDevice!.label}',
                      style: TextStyle(
                        fontSize: 12,
                        color: WarmTokens.warmMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

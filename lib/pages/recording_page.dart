import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart' show Amplitude, AudioRecorder;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../design_tokens.dart';
import '../exceptions.dart';
import '../models/audio_input_device.dart';
import '../models/processing_task.dart' as task_model;
import '../services/audio_device_service.dart';
import '../services/diary_storage_service.dart';
import '../services/fgs_runtime.dart';
import '../services/location_service.dart';
import '../services/processing_fgs_controller.dart';
import '../services/recording_task_handler.dart';
import '../models/weather_condition.dart';
import '../main.dart';
import '../widgets/app_title.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/recording_button.dart';
import '../widgets/streak_badge.dart';
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
  ({int currentStreak, int totalDays})? _stats;
  bool _hasRecordedThisSession = false;

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  String _realtimeText = '';
  final _realtimeScrollController = ScrollController();
  WeatherCondition? _currentCondition;
  String? _currentTemperature;
  String? _currentLocationName;
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
    _loadStats();
  }

  Future<void> _loadStats() async {
    final s = await _storageService.getRecordingDayStats();
    if (mounted) setState(() => _stats = s);
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
          _currentCondition = WeatherCondition.values.byName(
            data['condition'] as String,
          );
          _currentTemperature = data['temperature'] as String?;
        });
      case 'location':
        setState(() {
          _currentLocationName = (data['locationName'] as String?) ?? '';
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
        await _loadStats();
      case 'processingDone':
        // Processing FGS 结束（无论是否有条目被处理）
        ProcessingFgsController.onStopped();
      case 'completed':
      case 'failed':
      // 单个 task 完成/失败：不调 onStopped（那是 processingDone 的事）。
      // store 已移除 active task，listener 自动刷新 badge。
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

      // 预请求定位权限（必须在主 isolate；后台 FGS isolate 无 Activity 无法请求）。
      // 定位可选，失败不阻塞录音（仅无位置信息）。
      await LocationService().ensurePermission();

      // 设置通信端口
      FlutterForegroundTask.initCommunicationPort();
      debugPrint('[Rec] _doStartRecording: 准备 startService(microphone)');

      // 启动 Recording FGS
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: '正在录音',
        notificationText: '语音日记 - 录音中...',
        callback: startCallback,
      );
      debugPrint('[Rec] startService(microphone) result=$result');

      if (result is ServiceRequestFailure) {
        throw RecordingException(result.error.toString());
      }

      setState(() => _state = RecordingState.recording);
      if (!_hasRecordedThisSession) {
        _hasRecordedThisSession = true;
      }
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
      _currentCondition = null;
      _currentTemperature = null;
      _currentLocationName = null;
      _currentInputDevice = null;
    });
    // 注意：不在此处启动 Processing FGS，等收到 recordingComplete 后延迟调度
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 天气 pill 文本：emoji标签 +（有温度时）温度°。
  String _weatherPillText() {
    final base = _currentCondition!.displayPart;
    final temp = _currentTemperature;
    if (temp == null || temp.isEmpty) return base;
    return '$base $temp°';
  }

  Widget _infoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: WarmTokens.warmSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: WarmTokens.warmDivider.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: WarmTokens.warmMuted,
          letterSpacing: 0.2,
        ),
      ),
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
        body: Stack(
          children: [
            Center(
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

                    // 位置 + 天气 pill（任一就绪即显示，各自独立）
                    if (_state == RecordingState.recording &&
                        ((_currentLocationName != null &&
                                _currentLocationName!.isNotEmpty) ||
                            _currentCondition != null)) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (_currentLocationName != null &&
                              _currentLocationName!.isNotEmpty)
                            _infoPill(_currentLocationName!),
                          if (_currentCondition != null &&
                              _currentCondition!.displayPart.isNotEmpty)
                            _infoPill(_weatherPillText()),
                        ],
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
                            color: WarmTokens.warmDivider.withValues(
                              alpha: 0.5,
                            ),
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
                            color: WarmTokens.warmDivider.withValues(
                              alpha: 0.5,
                            ),
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
            if (_stats != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: StreakBadge(
                    streak: _stats!.currentStreak,
                    total: _stats!.totalDays,
                    compact: _hasRecordedThisSession,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../services/audio_recorder_service.dart';
import '../services/diary_storage_service.dart';
import '../services/realtime_asr_service.dart';
import '../services/recording_processor.dart';
import '../services/tts_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../widgets/app_title.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/recording_button.dart';
import 'diary_list_page.dart';
import 'settings_page.dart';

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final _recorderService = AudioRecorderService();
  final _storageService = DiaryStorageService();
  final _realtimeAsr = RealtimeAsrService();
  final _ttsService = TtsService();
  final _uuid = const Uuid();
  final _locationService = LocationService();
  final _weatherService = WeatherService();

  /// 录音期间异步获取的天气+位置信息，保存时注入 DiaryEntry
  WeatherLocation? _currentWeatherLocation;
  ({double lat, double lon})? _currentLocation;

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  Timer? _timer;
  String? _currentFolderId;
  String? _currentFolderPath;
  Stream<Amplitude>? _amplitudeStream;
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  StreamSubscription<String>? _partialResultSubscription;

  String _realtimeText = '';
  final _realtimeScrollController = ScrollController();

  int _pendingCount = 0;
  StreamSubscription<int>? _pendingCountSubscription;

  @override
  void dispose() {
    _timer?.cancel();
    _realtimeScrollController.dispose();
    _audioStreamSubscription?.cancel();
    _partialResultSubscription?.cancel();
    _pendingCountSubscription?.cancel();
    _recorderService.dispose();
    _realtimeAsr.disconnect();
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
      case RecordingState.recording:
        await _stopAndProcess();
      case RecordingState.processing:
        break;
    }
  }

  Future<void> _startRecording() async {
    try {
      _currentFolderId = _uuid.v4();
      _currentFolderPath =
          await _storageService.createDiaryFolder(_currentFolderId!);

      await _recorderService.startRecording(_currentFolderPath!);
      _amplitudeStream =
          _recorderService.onAmplitudeChanged(const Duration(milliseconds: 80));

      // 连接实时 ASR（失败不阻塞录音）
      _connectRealtimeAsr();

      // 监听 PCM 流，发送给实时 ASR
      _audioStreamSubscription =
          _recorderService.audioStream.listen((pcmData) {
        if (_realtimeAsr.isConnected) {
          _realtimeAsr.sendAudio(pcmData);
        }
      });

      // 异步获取位置和天气（不阻塞录音）
      _fetchWeatherInBackground();

      setState(() => _state = RecordingState.recording);
      _startTimer();
    } catch (e) {
      _showError('录音启动失败：$e');
    }
  }

  void _connectRealtimeAsr() {
    _realtimeAsr.connect().catchError((e) {
      // WebSocket 连接失败，不阻塞录音
      debugPrint('实时 ASR 连接失败: $e');
    });

    _partialResultSubscription =
        _realtimeAsr.onPartialResult.listen((text) {
      if (mounted) {
        setState(() => _realtimeText = text);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_realtimeScrollController.hasClients) {
            _realtimeScrollController.animateTo(
              _realtimeScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  void _fetchWeatherInBackground() {
    () async {
      try {
        debugPrint('[天气] 开始获取位置...');
        final loc = await _locationService.getCurrentLocation();
        if (loc == null) {
          debugPrint('[天气] 定位失败，跳过天气获取');
          return;
        }
        debugPrint('[天气] 定位成功: lat=${loc.lat}, lon=${loc.lon}');
        _currentLocation = loc;
        _currentWeatherLocation =
            await _weatherService.fetchWeatherAndLocation(loc.lat, loc.lon);
        if (_currentWeatherLocation != null) {
          debugPrint('[天气] 获取成功: icon=${_currentWeatherLocation!.icon} ${_currentWeatherLocation!.locationName} ${_currentWeatherLocation!.text} ${_currentWeatherLocation!.temp}°');
          if (mounted) setState(() {});
        } else {
          debugPrint('[天气] 天气 API 返回 null');
        }
      } catch (e) {
        debugPrint('[天气] 获取失败（不阻塞）: $e');
      }
    }();
  }

  Future<void> _stopAndProcess() async {
    _stopTimer();
    _amplitudeStream = null;

    // 停止实时 ASR
    _realtimeAsr.sendLastFrame();
    _realtimeAsr.disconnect();
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _partialResultSubscription?.cancel();
    _partialResultSubscription = null;

    // 捕获当前状态
    final folderId = _currentFolderId!;
    final folderPath = _currentFolderPath!;
    final duration = _recordingSeconds;
    final weather = _currentWeatherLocation;
    final location = _currentLocation;
    final createdAt = DateTime.now();

    // 停止录音，获取文件路径
    final recordingResult = await _recorderService.stopRecording();

    // TTS 应答
    _speakReply();

    // 提交后台处理
    RecordingProcessor.instance.enqueue(ProcessingTask(
      folderId: folderId,
      folderPath: folderPath,
      audioFilePath: recordingResult.filePath,
      durationSeconds: duration,
      createdAt: createdAt,
      weatherLocation: weather,
      location: location,
    ));

    // 立即回到 idle
    if (mounted) {
      setState(() {
        _state = RecordingState.idle;
        _recordingSeconds = 0;
        _realtimeText = '';
        _currentWeatherLocation = null;
        _currentLocation = null;
        _currentFolderId = null;
        _currentFolderPath = null;
      });
    }
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
        final text = _replyTemplates[DateTime.now().millisecond % _replyTemplates.length];
        debugPrint('[播报] 触发点1 开始: text="$text"');
        await _ttsService.speak(text, VoiceType.femaleSweet);
        debugPrint('[播报] 触发点1 完成');
      } catch (e) {
        debugPrint('TTS 应答失败: $e');
      }
    }();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  void initState() {
    super.initState();
    _pendingCountSubscription =
        RecordingProcessor.instance.pendingCountStream.listen((count) {
      if (mounted) setState(() => _pendingCount = count);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              child: const Icon(Icons.history),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DiaryListPage()),
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
              AudioWaveform(
                amplitudeStream: _amplitudeStream,
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
    );
  }
}

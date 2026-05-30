import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import '../services/asr_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';
import '../services/realtime_asr_service.dart';
import '../services/tts_service.dart';
import '../widgets/app_title.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/recording_button.dart';
import '../widgets/step_progress_indicator.dart';
import 'diary_detail_page.dart';
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
  final _asrService = AsrService();
  final _llmService = LlmService();
  final _realtimeAsr = RealtimeAsrService();
  final _ttsService = TtsService();
  final _uuid = const Uuid();

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  Timer? _timer;
  String? _currentFolderId;
  String? _currentFolderPath;
  Stream<Amplitude>? _amplitudeStream;
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  StreamSubscription<String>? _partialResultSubscription;

  int _processingStep = 0;
  bool _hasError = false;
  String _errorMessage = '';

  String _realtimeText = '';
  final _realtimeScrollController = ScrollController();

  @override
  void dispose() {
    _timer?.cancel();
    _realtimeScrollController.dispose();
    _audioStreamSubscription?.cancel();
    _partialResultSubscription?.cancel();
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

    final duration = _recordingSeconds;

    setState(() {
      _state = RecordingState.processing;
      _processingStep = 0;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final sw = Stopwatch()..start();
      final recordingResult = await _recorderService.stopRecording();
      debugPrint('[流程] stopRecording 完成: ${sw.elapsedMilliseconds}ms');

      // TTS 触发点 1：甜美女声应答（固定模板，无需等 LLM）
      _speakReply();

      // 步骤 1: Flash ASR 识别（带时间戳）
      setState(() => _processingStep = 1);
      AsrResult? asrResult;
      try {
        asrResult = await _asrService.transcribe(recordingResult.filePath);
        await _storageService.writeTranscriptJson(
            _currentFolderPath!,
            TranscriptData(
                version: 1, utterances: asrResult.utterances));
        debugPrint('[流程] Flash ASR 完成: ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[流程] Flash ASR 失败: $e');
        await _saveEntryAndNavigate('未命名日记', duration);
        return;
      }

      // 步骤 2: LLM 润色（保留时间戳）
      setState(() => _processingStep = 2);
      LlmResult? llmResult;
      try {
        llmResult = await _llmService.summarize(asrResult.utterances);
        await _storageService.writeLlmResult(
            _currentFolderPath!,
            LlmResultData(
              version: 1,
              title: llmResult.title,
              content: llmResult.content,
              summary: llmResult.summary,
              outline: llmResult.outline,
              utterances: llmResult.utterances,
            ));
        debugPrint('[流程] LLM summarize 完成: ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[流程] LLM 失败: $e');
        await _saveEntryAndNavigate('未命名日记', duration);
        return;
      }

      // 步骤 3: 保存元数据（防御性保存：LLM 成功后立即入库）
      setState(() => _processingStep = 3);
      final entry = DiaryEntry(
        id: _currentFolderId!,
        title: llmResult.title,
        folderPath: _currentFolderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
      );
      await _storageService.createEntry(entry);
      debugPrint('[流程] 保存元数据完成: ${sw.elapsedMilliseconds}ms');

      // TTS 触发点 2：低沉男声播报总结（失败不阻塞）
      _speakSummary(llmResult.outline);

      // 步骤 4: 自动归类（失败不阻塞）
      setState(() => _processingStep = 4);
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
            await _storageService.autoTagDiary(
                _currentFolderId!, matchedTagIds);
          }
          debugPrint('[流程] 自动归类完成: 匹配 ${matchedTagIds.length} 个标签');
        }
      } catch (e) {
        debugPrint('[流程] 自动归类失败（不阻塞）: $e');
      }

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

  void _speakSummary(String outline) {
    if (outline.isEmpty) return;
    () async {
      try {
        if (!await SettingsPage.isTtsEnabled()) return;
        debugPrint('[播报] 触发点2 开始: text="$outline"');
        await _ttsService.speak(outline, VoiceType.maleDeep);
        debugPrint('[播报] 触发点2 完成');
      } catch (e) {
        debugPrint('TTS 总结播报失败: $e');
      }
    }();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _saveEntryAndNavigate(String title, int duration) async {
    final entry = DiaryEntry(
      id: _currentFolderId!,
      title: title,
      folderPath: _currentFolderPath!,
      durationSeconds: duration,
      createdAt: DateTime.now(),
    );
    await _storageService.createEntry(entry);
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
                    setState(() {
                      _state = RecordingState.idle;
                      _hasError = false;
                      _processingStep = 0;
                      _realtimeText = '';
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

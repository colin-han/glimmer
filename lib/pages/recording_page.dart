import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../services/asr_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/recording_button.dart';
import '../widgets/step_progress_indicator.dart';
import 'diary_detail_page.dart';
import 'diary_list_page.dart';

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
  final _uuid = const Uuid();

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  Timer? _timer;
  String? _currentFolderId;
  String? _currentFolderPath;
  Stream<Amplitude>? _amplitudeStream;

  int _processingStep = 0;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _timer?.cancel();
    _recorderService.dispose();
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
      _currentFolderPath = await _storageService.createDiaryFolder(_currentFolderId!);
      await _recorderService.startRecording(_currentFolderPath!);
      _amplitudeStream = _recorderService.onAmplitudeChanged(const Duration(milliseconds: 80));
      setState(() => _state = RecordingState.recording);
      _startTimer();
    } catch (e) {
      _showError('录音启动失败：$e');
    }
  }

  Future<void> _stopAndProcess() async {
    _stopTimer();
    _amplitudeStream = null;
    final duration = _recordingSeconds;

    setState(() {
      _state = RecordingState.processing;
      _processingStep = 0;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final recordingResult = await _recorderService.stopRecording();
      setState(() => _processingStep = 1);
      final transcript = await _asrService.transcribe(recordingResult.filePath);
      await _storageService.writeTranscript(_currentFolderPath!, transcript);
      setState(() => _processingStep = 2);

      final llmResult = await _llmService.summarize(transcript);
      await _storageService.writeSummary(_currentFolderPath!, llmResult.content);
      setState(() => _processingStep = 3);

      final entry = DiaryEntry(
        id: _currentFolderId!,
        title: llmResult.title,
        folderPath: _currentFolderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
      );
      await _storageService.createEntry(entry);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: entry)),
        ).then((_) {
          setState(() {
            _state = RecordingState.idle;
            _hasError = false;
            _processingStep = 0;
            _recordingSeconds = 0;
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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语音日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiaryListPage()),
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
                StepProgressIndicator(currentStep: _processingStep, hasError: _hasError),
                const SizedBox(height: 32),
                if (_hasError)
                  Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)
                else
                  const Text('正在处理中...'),
                const SizedBox(height: 24),
              ],
              AudioWaveform(
                amplitudeStream: _amplitudeStream,
                color: _state == RecordingState.recording ? Colors.red : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 32),
              RecordingButton(state: _state, onTap: _onTap, recordingSeconds: _recordingSeconds),
              if (_hasError) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _state = RecordingState.idle;
                      _hasError = false;
                      _processingStep = 0;
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

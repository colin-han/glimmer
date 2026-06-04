import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import 'asr_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'tos_upload_service.dart';
import 'weather_service.dart';

class ProcessingTask {
  final String folderId;
  final String folderPath;
  final String audioFilePath;
  final int durationSeconds;
  final DateTime createdAt;
  final WeatherLocation? weatherLocation;
  final ({double lat, double lon})? location;

  const ProcessingTask({
    required this.folderId,
    required this.folderPath,
    required this.audioFilePath,
    required this.durationSeconds,
    required this.createdAt,
    this.weatherLocation,
    this.location,
  });
}

class RecordingProcessor {
  RecordingProcessor._();
  static final instance = RecordingProcessor._();

  final _tosService = TosUploadService();
  final _asrService = AsrService();
  final _llmService = LlmService();
  final _storageService = DiaryStorageService();

  final _queue = <ProcessingTask>[];
  bool _processing = false;
  ProcessingTask? _currentTask;

  final _pendingCountController = StreamController<int>.broadcast();
  final _tasksController = StreamController<List<ProcessingTask>>.broadcast();

  /// 当前待处理数量（含正在处理的）
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  /// 当前所有处理中的任务（正在处理 + 队列中等待）
  Stream<List<ProcessingTask>> get tasksStream => _tasksController.stream;

  int get pendingCount => _queue.length + (_processing ? 1 : 0);

  List<ProcessingTask> get _allTasks {
    final tasks = <ProcessingTask>[];
    if (_currentTask != null) tasks.add(_currentTask!);
    tasks.addAll(_queue);
    return tasks;
  }

  void _notify() {
    _pendingCountController.add(pendingCount);
    _tasksController.add(_allTasks);
  }

  void enqueue(ProcessingTask task) {
    _queue.add(task);
    _notify();

    // 立即在 DB 创建 processing 状态的条目
    _createProcessingEntry(task);

    _processNext();
  }

  Future<void> _createProcessingEntry(ProcessingTask task) async {
    try {
      await _storageService.createEntry(DiaryEntry(
        id: task.folderId,
        title: '正在处理中...',
        folderPath: task.folderPath,
        durationSeconds: task.durationSeconds,
        createdAt: task.createdAt,
        audioFormat: 'ogg',
        status: EntryStatus.processing,
        weatherIcon: task.weatherLocation?.icon,
        weatherText: task.weatherLocation?.text,
        temperature: task.weatherLocation?.temp,
        locationName: task.weatherLocation?.locationName,
        locationLat: task.location?.lat,
        locationLon: task.location?.lon,
      ));
    } catch (e) {
      debugPrint('[后台处理] 创建 processing 条目失败: $e');
    }
  }

  Future<void> _processNext() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;

    _currentTask = _queue.removeAt(0);
    _notify();

    try {
      await _processTask(_currentTask!);
    } catch (e) {
      debugPrint('[后台处理] 任务失败: $e');
    }

    _currentTask = null;
    _processing = false;
    _notify();

    if (_queue.isNotEmpty) {
      _processNext();
    }
  }

  Future<void> _processTask(ProcessingTask task) async {
    debugPrint('[后台处理] 开始处理: ${task.folderId}');

    String? tosKey;

    // 步骤 1: TOS 上传 + ASR
    AsrResult? asrResult;
    try {
      tosKey = await _tosService.uploadAudio(
        task.audioFilePath,
        task.folderId,
      );
      debugPrint('[后台处理] TOS 上传完成: $tosKey');

      final presignedUrl = await _tosService.getPresignedUrl(tosKey);
      asrResult = await _asrService.transcribeFromUrl(presignedUrl);

      await _storageService.writeTranscriptJson(
        task.folderPath,
        TranscriptData(version: 1, utterances: asrResult.utterances),
      );
      debugPrint('[后台处理] ASR 完成');
    } catch (e) {
      debugPrint('[后台处理] TOS/ASR 失败: $e');
      await _saveFallbackEntry(task);
      return;
    }

    // 步骤 2: LLM 润色
    LlmResult? llmResult;
    try {
      llmResult = await _llmService.summarize(asrResult.utterances);
      await _storageService.writeLlmResult(
        task.folderPath,
        LlmResultData(
          version: 1,
          title: llmResult.title,
          content: llmResult.content,
          summary: llmResult.summary,
          outline: llmResult.outline,
          utterances: llmResult.utterances,
        ),
      );
      debugPrint('[后台处理] LLM 完成');
    } catch (e) {
      debugPrint('[后台处理] LLM 失败: $e');
      await _saveFallbackEntry(task, tosKey: tosKey);
      return;
    }

    // 步骤 3: 更新元数据为完成状态
    final entry = DiaryEntry(
      id: task.folderId,
      title: llmResult.title,
      folderPath: task.folderPath,
      durationSeconds: task.durationSeconds,
      createdAt: task.createdAt,
      tosKey: tosKey,
      audioFormat: 'ogg',
      uploadedAt: DateTime.now(),
      weatherIcon: task.weatherLocation?.icon,
      weatherText: task.weatherLocation?.text,
      temperature: task.weatherLocation?.temp,
      locationName: task.weatherLocation?.locationName,
      locationLat: task.location?.lat,
      locationLon: task.location?.lon,
      status: EntryStatus.completed,
    );
    await _storageService.updateEntry(entry);
    debugPrint('[后台处理] 元数据更新完成');

    // 步骤 4: 自动归类（失败不阻塞）
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
          await _storageService.autoTagDiary(task.folderId, matchedTagIds);
        }
        debugPrint('[后台处理] 自动归类完成: ${matchedTagIds.length} 个标签');
      }
    } catch (e) {
      debugPrint('[后台处理] 自动归类失败（不阻塞）: $e');
    }

    debugPrint('[后台处理] 任务完成: ${task.folderId}');
  }

  Future<void> _saveFallbackEntry(ProcessingTask task, {String? tosKey}) async {
    try {
      await _storageService.updateEntry(DiaryEntry(
        id: task.folderId,
        title: '未命名日记',
        folderPath: task.folderPath,
        durationSeconds: task.durationSeconds,
        createdAt: task.createdAt,
        tosKey: tosKey,
        audioFormat: 'ogg',
        weatherIcon: task.weatherLocation?.icon,
        weatherText: task.weatherLocation?.text,
        temperature: task.weatherLocation?.temp,
        locationName: task.weatherLocation?.locationName,
        locationLat: task.location?.lat,
        locationLon: task.location?.lon,
        status: EntryStatus.completed,
      ));
    } catch (e) {
      debugPrint('[后台处理] 更新兜底条目失败: $e');
    }
    debugPrint('[后台处理] 保存兜底条目: ${task.folderId}');
  }

  Future<void> dispose() async {
    await _pendingCountController.close();
    await _tasksController.close();
  }
}

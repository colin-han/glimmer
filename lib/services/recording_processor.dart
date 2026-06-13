import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
import '../models/utterance.dart';
import 'asr_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'tos_upload_service.dart';
import 'api_log_service.dart';

/// Processing FGS 入口函数
@pragma('vm:entry-point')
void processingCallback() {
  FlutterForegroundTask.setTaskHandler(ProcessingTaskHandler());
}

/// 处理阶段 TaskHandler，运行在 FGS isolate 中。
/// 从 DB 查询所有 status=processing 的条目，按 processingStage 恢复处理。
class ProcessingTaskHandler extends TaskHandler {
  final _tosService = TosUploadService();
  final _asrService = AsrService();
  final _llmService = LlmService();
  final _storageService = DiaryStorageService();
  final _apiLogService = ApiLogService();

  void _sendToMain(Map<String, dynamic> data) {
    FlutterForegroundTask.sendDataToMain(data);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ProcessingHandler] onStart');

    // 加载 dotenv
    try {
      await dotenv.load(fileName: '.env.local');
    } catch (e) {
      debugPrint('[ProcessingHandler] dotenv.load 失败: $e');
    }

    // 从 DB 查询所有待处理条目
    final entries = await _storageService.getPendingEntries();
    if (entries.isEmpty) {
      debugPrint('[ProcessingHandler] 无待处理任务，停止');
      _sendToMain({'type': 'processingDone'});
      await _stopService();
      return;
    }

    debugPrint('[ProcessingHandler] 待处理任务: ${entries.length} 个');

    for (final entry in entries) {
      await _apiLogService.logStep(
        diaryId: entry.id,
        step: 'processing',
        status: 'started',
        message: '从 ${entry.processingStage.value} 阶段恢复',
      );
      try {
        await _processEntry(entry);
        await _apiLogService.logStep(
          diaryId: entry.id,
          step: 'processing',
          status: 'success',
        );
      } catch (e) {
        debugPrint('[ProcessingHandler] 处理异常 (${entry.id}): $e');
        await _apiLogService.logStep(
          diaryId: entry.id,
          step: 'processing',
          status: 'error',
          message: e.toString(),
        );
        await _markFailed(entry.id, '处理失败');
      }
    }

    debugPrint('[ProcessingHandler] 全部处理完成');
    _sendToMain({'type': 'processingDone'});
    await _stopService();
  }

  Future<void> _processEntry(DiaryEntry entry) async {
    debugPrint('[ProcessingHandler] 开始处理: ${entry.id}, stage=${entry.processingStage.value}');

    switch (entry.processingStage) {
      case ProcessingStage.uploading:
        await _doUpload(entry);
        await _doAsr(entry);
        await _doLlm(entry);
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.asr:
        // TOS 已上传（tosKey 存在），直接 ASR
        await _doAsr(entry);
        await _doLlm(entry);
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.llm:
        // ASR 已完成，transcript.json 已存在
        await _doLlm(entry);
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.tagging:
        // LLM 已完成，llm_result.json 已存在
        await _doTagging(entry);
        await _doComplete(entry);

      case ProcessingStage.completed:
        // 已完成，跳过
        await _doComplete(entry);
    }
  }

  /// 阶段: 上传音频到 TOS
  Future<void> _doUpload(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 上传音频...',
    );

    // 查找音频文件
    String? audioFilePath;
    for (final name in ['audio.ogg', 'audio.wav']) {
      final f = File('${entry.folderPath}/$name');
      if (await f.exists()) {
        audioFilePath = f.path;
        break;
      }
    }
    if (audioFilePath == null) {
      throw Exception('音频文件不存在: ${entry.folderPath}');
    }

    final tosKey = await _tosService.uploadAudio(audioFilePath, entry.id);
    await _storageService.updateTosKeyAndStage(entry.id, tosKey, ProcessingStage.asr);
    debugPrint('[ProcessingHandler] 上传完成: $tosKey');
  }

  /// 阶段: ASR 识别（异步 submit + query）
  Future<void> _doAsr(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 语音识别...',
    );

    await _apiLogService.logStep(
      diaryId: entry.id,
      step: 'asr',
      status: 'started',
    );

    final sw = Stopwatch()..start();
    try {
      final tosKey = await _storageService.getTosKey(entry.id);
      if (tosKey == null) {
        throw Exception('tosKey 为空，无法进行 ASR');
      }

      final presignedUrl = await _tosService.getPresignedUrl(tosKey);

      AsrResult asrResult;
      if (entry.asrTaskId != null) {
        debugPrint('[ProcessingHandler] 恢复 ASR 查询: ${entry.asrTaskId}');
        try {
          asrResult = await _asrService.pollAsyncResult(entry.asrTaskId!);
        } catch (e) {
          debugPrint('[ProcessingHandler] ASR 查询失败，重新提交: $e');
          final newTaskId = await _asrService.submitAsync(presignedUrl);
          await _storageService.updateAsrTaskIdAndStage(
              entry.id, newTaskId, ProcessingStage.asr);
          asrResult = await _asrService.pollAsyncResult(newTaskId);
        }
      } else {
        final asrTaskId = await _asrService.submitAsync(presignedUrl);
        await _storageService.updateAsrTaskIdAndStage(
            entry.id, asrTaskId, ProcessingStage.asr);
        asrResult = await _asrService.pollAsyncResult(asrTaskId);
      }

      await _storageService.writeTranscriptJson(
        entry.folderPath,
        TranscriptData(version: 1, utterances: asrResult.utterances),
      );
      await _storageService.updateProcessingStage(
          entry.id, ProcessingStage.llm);

      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'asr_async',
        step: 'asr',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        audioDurationSeconds: entry.durationSeconds,
      );
      debugPrint('[ProcessingHandler] ASR 完成');
    } catch (e) {
      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'asr_async',
        step: 'asr',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
        audioDurationSeconds: entry.durationSeconds,
      );
      rethrow;
    }
  }

  /// 阶段: LLM 润色汇总
  Future<void> _doLlm(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - AI 总结...',
    );

    await _apiLogService.logStep(
      diaryId: entry.id,
      step: 'llm',
      status: 'started',
    );

    final sw = Stopwatch()..start();
    try {
      final transcript =
          await _storageService.readTranscriptJson(entry.folderPath);
      final llmResult = await _llmService.summarize(transcript.utterances);

      await _storageService.writeLlmResult(
        entry.folderPath,
        LlmResultData(
          version: 1,
          title: llmResult.title,
          content: llmResult.content,
          summary: llmResult.summary,
          outline: llmResult.outline,
          utterances: llmResult.utterances,
        ),
      );
      await _storageService.updateProcessingStage(
          entry.id, ProcessingStage.tagging);

      sw.stop();
      final usage = llmResult.usage;
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_summarize',
        step: 'llm',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        promptTokens: usage?.promptTokens,
        completionTokens: usage?.completionTokens,
        totalTokens: usage?.totalTokens,
        cachedTokens: usage?.cachedTokens,
        reasoningTokens: usage?.reasoningTokens,
      );
      debugPrint('[ProcessingHandler] LLM 完成');
    } catch (e) {
      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_summarize',
        step: 'llm',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// 阶段: 标签归类（失败不阻塞）
  Future<void> _doTagging(DiaryEntry entry) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 自动归类...',
    );

    final sw = Stopwatch()..start();
    try {
      final llmResult = await _storageService.readLlmResult(entry.folderPath);
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
          await _storageService.autoTagDiary(entry.id, matchedTagIds);
        }
      }

      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
      );
      debugPrint('[ProcessingHandler] 标签归类完成');
    } catch (e) {
      sw.stop();
      await _apiLogService.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      // 标签归类失败不阻塞，不 rethrow
      debugPrint('[ProcessingHandler] 自动归类失败（不阻塞）: $e');
    }
  }

  /// 阶段: 完成
  Future<void> _doComplete(DiaryEntry entry) async {
    // 读取 LLM 结果获取标题
    String title = entry.displayTitle;
    try {
      final llmResult = await _storageService.readLlmResult(entry.folderPath);
      title = llmResult.title;
    } catch (_) {}

    await _storageService.updateEntry(DiaryEntry(
      id: entry.id,
      title: title,
      folderPath: entry.folderPath,
      durationSeconds: entry.durationSeconds,
      createdAt: entry.createdAt,
      tosKey: entry.tosKey,
      audioFormat: entry.audioFormat,
      uploadedAt: DateTime.now(),
      weatherIcon: entry.weatherIcon,
      weatherText: entry.weatherText,
      temperature: entry.temperature,
      locationName: entry.locationName,
      locationLat: entry.locationLat,
      locationLon: entry.locationLon,
      status: EntryStatus.completed,
      processingStage: ProcessingStage.completed,
    ));

    FlutterForegroundTask.updateService(
      notificationTitle: '处理完成',
      notificationText: '语音日记 - $title',
    );

    _sendToMain({'type': 'completed', 'entryId': entry.id});
    debugPrint('[ProcessingHandler] 处理完成: ${entry.id}');
  }

  Future<void> _markFailed(String id, String title) async {
    try {
      await _storageService.updateEntryTitleAndStatus(id, title, EntryStatus.failed);
    } catch (e) {
      debugPrint('[ProcessingHandler] 标记 failed 失败: $e');
    }
    _sendToMain({'type': 'failed', 'entryId': id, 'step': 0, 'error': ''});
  }

  Future<void> _stopService() async {
    await Future.delayed(const Duration(seconds: 2));
    FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
    _sendToMain({
      'type': 'notificationPressed',
      'state': 'processing',
      'entryId': '',
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ProcessingHandler] onDestroy, isTimeout=$isTimeout');
    // 通知主 isolate 服务已停止，避免用户等待录音时 UI 卡住
    _sendToMain({'type': 'processingDone'});
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../exceptions.dart';
import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
import '../models/processing_task.dart' as task_model;
import '../models/utterance.dart';
import 'asr_service.dart';
import 'llm_service.dart';
import 'processing_task.dart';

/// 录音处理任务：把单篇录音走完 上传→ASR→LLM→标签→完成 流程。
///
/// 从原 ProcessingTaskHandler 的 _processEntry / _doUpload / _doAsr / _doLlm /
/// _doTagging / _doComplete / _handleEmptyAsr / _markFailed 提取，行为完全不变，
/// 仅改为通过 ProcessingContext 访问依赖。失败时自行标记 entry failed + 通知，
/// 不向上抛。
class DiaryProcessingTask implements ProcessingTask {
  final DiaryEntry entry;
  final task_model.ProcessingTask task;

  DiaryProcessingTask(this.entry, this.task);

  @override
  String get id => task.id;

  @override
  String get taskType => 'diary';

  @override
  String get notificationText => '语音日记 - ${entry.displayTitle}';

  @override
  Future<void> execute(ProcessingContext ctx) async {
    debugPrint(
      '[DiaryTask] 开始处理: ${entry.id}, stage=${entry.processingStage.value}',
    );
    await ctx.apiLog.logStep(
      diaryId: entry.id,
      step: 'processing',
      status: 'started',
      message: '从 ${entry.processingStage.value} 阶段恢复',
    );
    await ctx.storage.updateProcessingTaskStatus(
      task.id,
      task_model.TaskStatus.running,
    );
    ctx.sendToMain({
      'type': 'taskStarted',
      'taskId': task.id,
      'refId': entry.id,
      'taskType': 'diary',
    });
    try {
      await _processEntry(ctx);
      await ctx.apiLog.logStep(
        diaryId: entry.id,
        step: 'processing',
        status: 'success',
      );
    } catch (e) {
      debugPrint('[DiaryTask] 处理异常 (${entry.id}): $e');
      await ctx.apiLog.logStep(
        diaryId: entry.id,
        step: 'processing',
        status: 'error',
        message: e.toString(),
      );
      await _markFailed(ctx, '处理失败');
    }
  }

  Future<void> _processEntry(ProcessingContext ctx) async {
    final stage = task.stage != null
        ? ProcessingStage.fromString(task.stage!)
        : ProcessingStage.uploading;
    switch (stage) {
      case ProcessingStage.uploading:
        await _doUpload(ctx);
        // ASR 结果为空则直接完成，跳过 LLM/tagging
        if (await _doAsr(ctx)) break;
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.asr:
        // TOS 已上传（tosKey 存在），直接 ASR
        if (await _doAsr(ctx)) break;
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.llm:
        // ASR 已完成，transcript.json 已存在
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.tagging:
        // LLM 已完成，llm_result.json 已存在
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.completed:
        // 已完成，跳过
        await _doComplete(ctx);
    }
  }

  /// 阶段: 上传音频到 TOS
  Future<void> _doUpload(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 上传音频...',
    );

    String? audioFilePath;
    for (final name in ['audio.ogg', 'audio.wav']) {
      final f = File('${entry.folderPath}/$name');
      if (await f.exists()) {
        audioFilePath = f.path;
        break;
      }
    }
    if (audioFilePath == null) {
      throw ProcessingException('音频文件不存在: ${entry.folderPath}');
    }

    final tosKey = await ctx.tos.uploadAudio(audioFilePath, entry.id);
    await ctx.storage.updateTosKey(entry.id, tosKey);
    await ctx.storage.updateProcessingTaskStage(task.id, 'asr');
    ctx.sendToMain({
      'type': 'stageUpdate',
      'entryId': entry.id,
      'stage': 'asr',
    });
    debugPrint('[DiaryTask] 上传完成: $tosKey');
  }

  /// 阶段: ASR 识别。返回 true 表示识别结果为空（已标记完成，跳过后续 LLM）。
  Future<bool> _doAsr(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 语音识别...',
    );

    await ctx.apiLog.logStep(diaryId: entry.id, step: 'asr', status: 'started');

    final sw = Stopwatch()..start();
    try {
      final tosKey = await ctx.storage.getTosKey(entry.id);
      if (tosKey == null) {
        throw const ProcessingException('tosKey 为空，无法进行 ASR');
      }

      final presignedUrl = await ctx.tos.getPresignedUrl(tosKey);

      AsrResult asrResult;
      final existingAsrTaskId = task.meta['asrTaskId'] as String?;
      if (existingAsrTaskId != null) {
        debugPrint('[DiaryTask] 恢复 ASR 查询: $existingAsrTaskId');
        try {
          asrResult = await ctx.asr.pollAsyncResult(existingAsrTaskId);
        } catch (e) {
          debugPrint('[DiaryTask] ASR 查询失败，重新提交: $e');
          final newTaskId = await ctx.asr.submitAsync(presignedUrl);
          await ctx.storage.updateProcessingTaskMeta(task.id, {
            'asrTaskId': newTaskId,
          });
          asrResult = await ctx.asr.pollAsyncResult(newTaskId);
        }
      } else {
        final asrTaskId = await ctx.asr.submitAsync(presignedUrl);
        await ctx.storage.updateProcessingTaskMeta(task.id, {
          'asrTaskId': asrTaskId,
        });
        asrResult = await ctx.asr.pollAsyncResult(asrTaskId);
      }

      await ctx.storage.writeTranscriptJson(
        entry.folderPath,
        TranscriptData(version: 1, utterances: asrResult.utterances),
      );

      if (asrResult.utterances.isEmpty) {
        sw.stop();
        return _handleEmptyAsr(ctx, sw.elapsedMilliseconds);
      }

      await ctx.storage.updateProcessingTaskStage(task.id, 'llm');

      sw.stop();
      ctx.sendToMain({
        'type': 'stageUpdate',
        'entryId': entry.id,
        'stage': 'llm',
      });
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'asr_async',
        step: 'asr',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        audioDurationSeconds: entry.durationSeconds,
      );
      debugPrint('[DiaryTask] ASR 完成');
      return false;
    } catch (e) {
      sw.stop();
      await ctx.apiLog.logApiCall(
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

  /// ASR 识别结果为空时的统一处理。返回 true 表示已完成。
  Future<bool> _handleEmptyAsr(ProcessingContext ctx, int durationMs) async {
    debugPrint('[DiaryTask] ASR 识别结果为空，标记完成');
    await ctx.storage.writeTranscriptJson(
      entry.folderPath,
      TranscriptData(version: 1, utterances: []),
    );
    await ctx.storage.writeLlmResult(
      entry.folderPath,
      LlmResultData(
        version: 1,
        title: '未识别到语音内容',
        summary: '本次录音未识别到语音内容，可能录音过短或无声。',
        outline: '',
        utterances: [],
      ),
    );
    await ctx.apiLog.logApiCall(
      diaryId: entry.id,
      apiType: 'asr_async',
      step: 'asr',
      status: 'success',
      durationMs: durationMs,
      audioDurationSeconds: entry.durationSeconds,
      responseSummary: '识别结果为空，跳过 LLM 直接完成',
    );
    await _doComplete(ctx);
    return true;
  }

  /// 阶段: LLM 润色汇总
  Future<void> _doLlm(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - AI 总结...',
    );

    await ctx.apiLog.logStep(diaryId: entry.id, step: 'llm', status: 'started');

    final sw = Stopwatch()..start();
    try {
      final transcript = await ctx.storage.readTranscriptJson(entry.folderPath);
      final llmResult = await ctx.llm.summarize(transcript.utterances);

      await ctx.storage.writeLlmResult(
        entry.folderPath,
        LlmResultData(
          version: 1,
          title: llmResult.title,
          summary: llmResult.summary,
          outline: llmResult.outline,
          utterances: llmResult.utterances,
        ),
      );
      await ctx.storage.updateProcessingTaskStage(task.id, 'tagging');

      sw.stop();
      ctx.sendToMain({
        'type': 'stageUpdate',
        'entryId': entry.id,
        'stage': 'tagging',
        'title': llmResult.title,
      });
      final usage = llmResult.usage;
      await ctx.apiLog.logApiCall(
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
      debugPrint('[DiaryTask] LLM 完成');
    } catch (e) {
      sw.stop();
      await ctx.apiLog.logApiCall(
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
  Future<void> _doTagging(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 自动归类...',
    );

    final sw = Stopwatch()..start();
    try {
      final llmResult = await ctx.storage.readLlmResult(entry.folderPath);
      final allTags = await ctx.storage.getAllTags();
      final tagsWithPrompt = allTags
          .where((t) => t.matchPrompt.isNotEmpty)
          .toList();
      if (tagsWithPrompt.isNotEmpty) {
        final tagInfos = tagsWithPrompt
            .map(
              (t) =>
                  TagInfo(id: t.id, name: t.name, matchPrompt: t.matchPrompt),
            )
            .toList();
        final matchedTagIds = await ctx.llm.matchTags(
          llmResult.summary,
          tagInfos,
        );
        if (matchedTagIds.isNotEmpty) {
          await ctx.storage.autoTagDiary(entry.id, matchedTagIds);
        }
      }

      sw.stop();
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
      );
      debugPrint('[DiaryTask] 标签归类完成');
    } catch (e) {
      sw.stop();
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      // 标签归类失败不阻塞，不 rethrow
      debugPrint('[DiaryTask] 自动归类失败（不阻塞）: $e');
    }
  }

  /// 阶段: 完成
  Future<void> _doComplete(ProcessingContext ctx) async {
    String title = entry.displayTitle;
    try {
      final llmResult = await ctx.storage.readLlmResult(entry.folderPath);
      title = llmResult.title;
    } catch (_) {}

    await ctx.storage.updateEntryTitleAndUploadedAt(entry.id, title);
    await ctx.storage.updateProcessingTaskStatus(
      task.id,
      task_model.TaskStatus.completed,
    );

    FlutterForegroundTask.updateService(
      notificationTitle: '处理完成',
      notificationText: '语音日记 - $title',
    );

    ctx.sendToMain({
      'type': 'completed',
      'entryId': entry.id,
      'taskId': task.id,
    });
    debugPrint('[DiaryTask] 处理完成: ${entry.id}');
  }

  Future<void> _markFailed(ProcessingContext ctx, String error) async {
    await ctx.storage.updateProcessingTaskStatus(
      task.id,
      task_model.TaskStatus.failed,
      failedMessage: error,
    );
    ctx.sendToMain({
      'type': 'failed',
      'entryId': entry.id,
      'taskId': task.id,
      'error': error,
    });
  }
}

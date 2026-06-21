import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;

import '../design_tokens.dart';
import '../main.dart';
import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
import '../models/processing_task.dart' as task_model;
import '../models/tag.dart';
import '../models/utterance.dart';
import '../services/audio_player_service.dart';
import '../services/diary_storage_service.dart';
import '../services/processing_fgs_controller.dart';
import '../widgets/app_title.dart';
import '../widgets/detail/detail_content_section.dart';
import '../widgets/detail/detail_info_bar.dart';
import '../widgets/detail/detail_player_section.dart';
import '../widgets/tag_editor_sheet.dart';
import '../widgets/tag_selector_sheet.dart';
import 'diary_list_page.dart';

class DiaryDetailPage extends StatefulWidget {
  final DiaryEntry entry;
  final bool autoPlaySummary;

  const DiaryDetailPage({
    super.key,
    required this.entry,
    this.autoPlaySummary = false,
  });

  @override
  State<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends State<DiaryDetailPage> {
  final _playerService = AudioPlayerService();
  final _storageService = DiaryStorageService();

  bool _loading = true;
  bool _audioExists = false;
  bool _hasLlm = false;
  String _summary = '';
  List<Utterance> _activeUtterances = [];
  bool _hasTranscript = false;
  List<Tag> _tags = [];
  bool _retrying = false;

  /// DB 最新 task（含 failed，用于失败横幅）。store 内存只含 active，故 failed 需查 DB。
  task_model.ProcessingTask? _latestTask;

  /// 可变的 entry 副本，用于在处理过程中刷新元数据
  late DiaryEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _loadContent();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    processingTaskStore.activeRefIds.addListener(_onStoreChange);
  }

  @override
  void dispose() {
    processingTaskStore.activeRefIds.removeListener(_onStoreChange);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _playerService.dispose();
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    final entryId = data['entryId'] as String?;
    // 只处理与当前日记相关的消息
    if (entryId != null && entryId != _entry.id) return;

    if (type == 'stageUpdate' && mounted) {
      // stageUpdate 实时更新 title（store 同步刷新 active task 的 stage，
      // 这里仅更新 entry.title，避免 DB 跨 isolate 读取延迟）。
      final stageStr = data['stage'] as String?;
      final title = data['title'] as String?;
      setState(() {
        _entry = _entry.copyWith(
          processingStage: stageStr != null
              ? ProcessingStage.fromString(stageStr)
              : null,
          title: title,
        );
      });
      // ASR 完成（进入 llm 阶段），加载字幕数据供播放器显示
      if (stageStr == 'llm') {
        _loadTranscript();
      }
    } else if (type == 'completed' && mounted) {
      // 处理完成，加载最终内容（store 已移除 active task，listener 会刷新横幅）
      ProcessingFgsController.onStopped();
      _loadContent();
    } else if (type == 'processingDone' && mounted) {
      // FGS 停止，重新加载内容（刷新 _latestTask，可能含 failed）
      ProcessingFgsController.onStopped();
      _loadContent();
    } else if (type == 'failed' && mounted) {
      // 处理失败：重新加载内容（_latestTask 会含 failed，显示失败横幅）
      ProcessingFgsController.onStopped();
      _loadContent();
    }
  }

  /// 仅加载 transcript 字幕数据（ASR 完成后立即显示）
  Future<void> _loadTranscript() async {
    try {
      final transcriptData = await _storageService.readTranscriptJson(
        _entry.folderPath,
      );
      if (mounted && !_hasLlm) {
        setState(() {
          _activeUtterances = transcriptData.utterances;
          _hasTranscript = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadContent() async {
    // 从数据库重新加载 entry 元数据（获取最新的 processingStage、title、status）
    try {
      final updated = await _storageService.getEntryById(_entry.id);
      if (mounted) _entry = updated;
    } catch (_) {}

    // 查最新 task（含 failed，用于失败横幅；store 内存只含 active）
    try {
      _latestTask = await _storageService.getLatestProcessingTask(_entry.id);
    } catch (_) {}

    final audioPath = _storageService.getAudioPath(
      _entry.folderPath,
      _entry.audioFormat,
    );
    final audioExists = File(audioPath).existsSync();
    final transcriptExists = await File(
      p.join(_entry.folderPath, 'transcript.json'),
    ).exists();
    final hasLlm = await _storageService.hasLlmResult(_entry.folderPath);

    TranscriptData? transcriptData;
    if (transcriptExists) {
      try {
        transcriptData = await _storageService.readTranscriptJson(
          _entry.folderPath,
        );
      } catch (_) {}
    }

    String summary = '';
    List<Utterance> summaryUtterances = [];

    if (hasLlm) {
      final llmData = await _storageService.readLlmResult(_entry.folderPath);
      summary = llmData.summary;
      summaryUtterances = llmData.utterances;
    }

    // utterances 优先级：LLM > Transcript
    List<Utterance> activeUtterances = [];
    final hasTranscript = transcriptExists || hasLlm;

    if (hasLlm && summaryUtterances.isNotEmpty) {
      activeUtterances = summaryUtterances;
    } else if (transcriptData != null) {
      activeUtterances = transcriptData.utterances;
    }

    if (mounted) {
      setState(() {
        _audioExists = audioExists;
        _hasLlm = hasLlm;
        _summary = summary;
        _activeUtterances = activeUtterances;
        _hasTranscript = hasTranscript;
        _loading = false;
      });
    }
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _storageService.getFullTagsForDiary(_entry.id);
    if (mounted) {
      setState(() => _tags = tags);
    }
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);

    try {
      // 继承旧失败 task 的 stage/meta（断点续跑）。
      final oldTask = await _storageService.getLatestProcessingTask(_entry.id);
      await processingTaskStore.enqueueTask(
        taskType: task_model.TaskType.diary,
        refId: _entry.id,
        stage: oldTask?.stage ?? 'asr', // 继承失败处 stage
        meta: oldTask?.meta ?? const {}, // 继承 asrTaskId
      );
      if (!mounted) return;
      // 入队后 store 通知 activeRefIds listener 自动刷新横幅（无需本地乐观更新）
      setState(() => _retrying = false);
    } catch (e) {
      if (mounted) {
        setState(() => _retrying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重试失败: $e')));
      }
    }
  }

  Future<void> _reanalyze() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新分析'),
        content: const Text('将重新识别语音并重新生成总结，当前的识别结果和总结会被覆盖。标签会保留，并追加新匹配的标签。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重新分析'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // 入队全量重跑 task（stage=asr + 清 asrTaskId）。
      // enqueueTask 新建 task 行，store 通知 listener 自动刷新横幅。
      await processingTaskStore.enqueueTask(
        taskType: task_model.TaskType.diary,
        refId: _entry.id,
        stage: 'asr',
        meta: const {}, // 清 asrTaskId，全量重跑
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重新分析失败: $e')));
      }
    }
  }

  Future<void> _deleteDiary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除这篇日记吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storageService.deleteEntry(_entry.id, _entry.folderPath);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DiaryListPage()),
        );
      }
    }
  }

  Widget _buildStatusBanner() {
    // 优先看 store 内存（active: queued/running），回退 _latestTask（含 failed）
    final activeTask = processingTaskStore.getTask(_entry.id);
    final task = activeTask ?? _latestTask;
    if (task == null) return const SizedBox.shrink();

    if (task.status == task_model.TaskStatus.running ||
        task.status == task_model.TaskStatus.queued) {
      final stageText = switch (task.stage) {
        'uploading' => '上传',
        'asr' => '语音识别',
        'llm' => 'AI 总结',
        'tagging' => '自动归类',
        _ => '处理中',
      };

      // queued（待延时启动）显示暂停样式；running 显示转圈进度
      if (task.status == task_model.TaskStatus.queued) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WarmTokens.warmProcessBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.pause_circle_outline,
                color: WarmTokens.warmMuted,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '处理暂停 · $stageText 待处理',
                  style: const TextStyle(
                    color: WarmTokens.warmBrown,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      // 活跃处理中：显示转圈动画和进度条
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WarmTokens.warmProcessBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: WarmTokens.warmMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$stageText中...',
                  style: const TextStyle(
                    color: WarmTokens.warmBrown,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(color: WarmTokens.warmAmber),
          ],
        ),
      );
    }

    if (task.status == task_model.TaskStatus.failed) {
      final failedStage = switch (task.stage) {
        'uploading' => '上传失败',
        'asr' => '语音识别失败',
        'llm' => 'AI 总结失败',
        'tagging' => '归类失败',
        _ => '处理失败',
      };
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WarmTokens.failedBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: WarmTokens.failedAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failedStage,
                style: const TextStyle(
                  color: WarmTokens.failedText,
                  fontSize: 13,
                ),
              ),
            ),
            if (_retrying)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重新处理', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: WarmTokens.failedAccent,
                ),
              ),
          ],
        ),
      );
    }

    // completed：不显示横幅
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final audioPath = _storageService.getAudioPath(
      _entry.folderPath,
      _entry.audioFormat,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                _entry.displayTitle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (AppTitle.isDev) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'dev',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // 仅在未处理中且未失败时显示「重新分析」（store 内存无 active task + DB 最新 task 非 failed）
          if (!processingTaskStore.isProcessing(_entry.id) &&
              _latestTask?.status != task_model.TaskStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新分析',
              onPressed: _reanalyze,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteDiary,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 信息栏
                  DetailInfoBar(entry: _entry),
                  // 标签行
                  if (!_hasLlm)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        processingTaskStore.getTask(_entry.id)?.status ==
                                task_model.TaskStatus.running
                            ? '⏳ 处理中...'
                            : '⏸ 处理暂停',
                        style: const TextStyle(
                          fontSize: 12,
                          color: WarmTokens.warmMuted,
                        ),
                      ),
                    )
                  else if (_tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ..._tags.map(
                            (tag) => Chip(
                              label: Text(
                                tag.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: WarmTokens.warmBrown,
                                ),
                              ),
                              onDeleted: () async {
                                await _storageService.removeDiaryTag(
                                  _entry.id,
                                  tag.id,
                                );
                                final updatedTag = await _storageService
                                    .getTagById(tag.id);
                                if (!mounted) return;
                                await showTagEditorSheet(
                                  // ignore: use_build_context_synchronously
                                  context,
                                  tag: updatedTag,
                                  isRemoval: true,
                                );
                                _loadTags();
                              },
                              deleteIconColor: WarmTokens.warmMuted,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              side: const BorderSide(
                                color: WarmTokens.warmDivider,
                              ),
                              backgroundColor: WarmTokens.warmCardBg,
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.add,
                              size: 16,
                              color: WarmTokens.warmMuted,
                            ),
                            label: const Text(
                              '标签',
                              style: TextStyle(
                                fontSize: 12,
                                color: WarmTokens.warmMuted,
                              ),
                            ),
                            onPressed: () async {
                              final selectedIds = await showTagSelectorSheet(
                                context,
                                selectedTagIds: _tags.map((t) => t.id).toList(),
                              );
                              if (selectedIds != null && mounted) {
                                final currentIds = _tags
                                    .map((t) => t.id)
                                    .toSet();
                                final newIds = selectedIds.toSet();
                                for (final id in newIds.difference(
                                  currentIds,
                                )) {
                                  await _storageService.addDiaryTag(
                                    _entry.id,
                                    id,
                                  );
                                  final tag = await _storageService.getTagById(
                                    id,
                                  );
                                  if (!mounted) continue;
                                  await showTagEditorSheet(
                                    // ignore: use_build_context_synchronously
                                    context,
                                    tag: tag,
                                    isRemoval: false,
                                  );
                                }
                                for (final id in currentIds.difference(
                                  newIds,
                                )) {
                                  await _storageService.removeDiaryTag(
                                    _entry.id,
                                    id,
                                  );
                                  final tag = await _storageService.getTagById(
                                    id,
                                  );
                                  if (!mounted) continue;
                                  await showTagEditorSheet(
                                    // ignore: use_build_context_synchronously
                                    context,
                                    tag: tag,
                                    isRemoval: true,
                                  );
                                }
                                _loadTags();
                              }
                            },
                            visualDensity: VisualDensity.compact,
                            side: const BorderSide(
                              color: WarmTokens.warmDivider,
                            ),
                            backgroundColor: WarmTokens.warmCardBg,
                          ),
                        ],
                      ),
                    ),
                  // 分隔线
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1, color: WarmTokens.warmDivider),
                  ),
                  // 播放器区域
                  if (_audioExists)
                    DetailPlayerSection(
                      playerService: _playerService,
                      audioFilePath: audioPath,
                      utterances: _activeUtterances,
                      hasTranscript: _hasTranscript,
                    ),
                  // 处理状态横幅
                  _buildStatusBanner(),
                  // 分隔线
                  if (_hasLlm && _summary.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1, color: WarmTokens.warmDivider),
                    ),
                  // 日记
                  if (_hasLlm && _summary.isNotEmpty)
                    DetailContentSection(summary: _summary),
                  // 底部安全区
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;

import '../design_tokens.dart';
import '../main.dart';
import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
import '../models/processing_task.dart';
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

  /// FGS 是否正在活跃处理当前日记（收到 stageUpdate 即为 true）
  bool _isActivelyProcessing = false;

  /// 可变的 entry 副本，用于在处理过程中刷新元数据
  late DiaryEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _loadContent();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _playerService.dispose();
    super.dispose();
  }

  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    final entryId = data['entryId'] as String?;
    // 只处理与当前日记相关的消息
    if (entryId != null && entryId != _entry.id) return;

    if (type == 'stageUpdate' && mounted) {
      // 直接从消息中提取阶段信息，避免 DB 跨 isolate 读取延迟
      final stageStr = data['stage'] as String?;
      final title = data['title'] as String?;
      setState(() {
        _isActivelyProcessing = true;
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
      // 处理完成，加载最终内容
      ProcessingFgsController.onStopped();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
    } else if (type == 'processingDone' && mounted) {
      // FGS 停止，标记为非活跃
      ProcessingFgsController.onStopped();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
    } else if (type == 'failed' && mounted) {
      // 处理失败：重置 mode + 显示失败横幅
      ProcessingFgsController.onStopped();
      setState(() => _isActivelyProcessing = false);
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
        taskType: TaskType.diary,
        refId: _entry.id,
        stage: oldTask?.stage ?? 'asr', // 继承失败处 stage
        meta: oldTask?.meta ?? const {}, // 继承 asrTaskId
      );
      if (!mounted) return;
      // 本地乐观更新：切到处理中横幅
      setState(() {
        _retrying = false;
        _entry = _entry.copyWith(
          status: EntryStatus.processing,
          processingStage: ProcessingStage.fromString(oldTask?.stage ?? 'asr'),
        );
        _isActivelyProcessing = true;
      });
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
      // enqueueTask 新建 task 行，不碰 entry.status（UI 暂时 stale，Task 6 改订阅 store）。
      await processingTaskStore.enqueueTask(
        taskType: TaskType.diary,
        refId: _entry.id,
        stage: 'asr',
        meta: const {}, // 清 asrTaskId，全量重跑
      );
      if (!mounted) return;
      // 本地乐观更新：立即切到处理中横幅
      setState(() {
        _entry = _entry.copyWith(
          status: EntryStatus.processing,
          processingStage: ProcessingStage.asr,
        );
        _isActivelyProcessing = true;
      });
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
    final isProcessing = _entry.status == EntryStatus.processing;
    final isFailed = _entry.status == EntryStatus.failed;
    if (!isProcessing && !isFailed) return const SizedBox.shrink();

    if (isProcessing) {
      final stageText = switch (_entry.processingStage) {
        ProcessingStage.uploading => '上传',
        ProcessingStage.asr => '语音识别',
        ProcessingStage.llm => 'AI 总结',
        ProcessingStage.tagging => '自动归类',
        ProcessingStage.completed => '即将完成',
      };

      // 暂停状态：FGS 未运行，不显示转圈动画
      if (!_isActivelyProcessing) {
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

    // failed
    final failedStage = switch (_entry.processingStage) {
      ProcessingStage.uploading => '上传失败',
      ProcessingStage.asr => '语音识别失败',
      ProcessingStage.llm => 'AI 总结失败',
      ProcessingStage.tagging => '归类失败',
      ProcessingStage.completed => '处理失败',
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
          if (_entry.status == EntryStatus.completed)
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
                        _isActivelyProcessing ? '⏳ 处理中...' : '⏸ 处理暂停',
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

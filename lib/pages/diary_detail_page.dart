import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;

import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
import '../models/tag.dart';
import '../models/utterance.dart';
import '../services/asr_service.dart';
import '../services/audio_player_service.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';
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
  final _asrService = AsrService();
  final _llmService = LlmService();

  bool _loading = true;
  bool _audioExists = false;
  bool _hasLlm = false;
  String _content = '';
  List<Utterance> _activeUtterances = [];
  bool _hasTranscript = false;
  List<Tag> _tags = [];
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
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
    if ((type == 'completed' || type == 'processingDone') && mounted) {
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    final audioPath = _storageService.getAudioPath(
        widget.entry.folderPath, widget.entry.audioFormat);
    final audioExists = File(audioPath).existsSync();
    final transcriptExists =
        await File(p.join(widget.entry.folderPath, 'transcript.json'))
            .exists();
    final hasLlm = await _storageService.hasLlmResult(widget.entry.folderPath);

    TranscriptData? transcriptData;
    if (transcriptExists) {
      try {
        transcriptData =
            await _storageService.readTranscriptJson(widget.entry.folderPath);
      } catch (_) {}
    }

    String content = '';
    List<Utterance> summaryUtterances = [];

    if (hasLlm) {
      final llmData =
          await _storageService.readLlmResult(widget.entry.folderPath);
      content = llmData.content;
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
        _content = content;
        _activeUtterances = activeUtterances;
        _hasTranscript = hasTranscript;
        _loading = false;
      });
    }
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _storageService.getFullTagsForDiary(widget.entry.id);
    if (mounted) {
      setState(() => _tags = tags);
    }
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);

    try {
      final audioPath = _storageService.getAudioPath(
          widget.entry.folderPath, widget.entry.audioFormat);
      final transcriptPath =
          p.join(widget.entry.folderPath, 'transcript.json');
      final transcriptExists = File(transcriptPath).existsSync();

      List<Utterance> utterances;

      if (!transcriptExists) {
        final asrResult = await _asrService.transcribe(audioPath);
        await _storageService.writeTranscriptJson(widget.entry.folderPath,
            TranscriptData(version: 1, utterances: asrResult.utterances));
        utterances = asrResult.utterances;
      } else {
        final transcriptData =
            await _storageService.readTranscriptJson(widget.entry.folderPath);
        utterances = transcriptData.utterances;
      }

      final llmResult = await _llmService.summarize(utterances);
      await _storageService.writeLlmResult(
          widget.entry.folderPath,
          LlmResultData(
            version: 1,
            title: llmResult.title,
            content: llmResult.content,
            summary: llmResult.summary,
            outline: llmResult.outline,
            utterances: llmResult.utterances,
          ));

      await _storageService.updateTitle(widget.entry.id, llmResult.title);

      // 自动打 tag
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
                widget.entry.id, matchedTagIds);
          }
        }
      } catch (e) {
        debugPrint('[重试] 自动归类失败（不阻塞）: $e');
      }

      setState(() {
        _retrying = false;
        _loading = true;
      });
      await _loadContent();
    } catch (e) {
      if (mounted) {
        setState(() => _retrying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重试失败: $e')),
        );
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
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storageService.deleteEntry(
          widget.entry.id, widget.entry.folderPath);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DiaryListPage()),
        );
      }
    }
  }

  Widget _buildStatusBanner() {
    final isProcessing = widget.entry.status == EntryStatus.processing;
    final isFailed = widget.entry.status == EntryStatus.failed;
    if (!isProcessing && !isFailed) return const SizedBox.shrink();

    if (isProcessing) {
      final stageText = switch (widget.entry.processingStage) {
        ProcessingStage.uploading => '上传中...',
        ProcessingStage.asr => '语音识别中...',
        ProcessingStage.llm => 'AI 总结中...',
        ProcessingStage.tagging => '自动归类中...',
        ProcessingStage.completed => '即将完成...',
      };
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.blue[50],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.blue[700]),
                  ),
                  const SizedBox(width: 8),
                  Text('🔄 正在处理: $stageText',
                      style: TextStyle(color: Colors.blue[900])),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(color: Colors.blue[300]),
            ],
          ),
        ),
      );
    }

    // failed
    final failedStage = switch (widget.entry.processingStage) {
      ProcessingStage.uploading => '上传失败',
      ProcessingStage.asr => '语音识别失败',
      ProcessingStage.llm => 'AI 总结失败',
      ProcessingStage.tagging => '归类失败',
      ProcessingStage.completed => '处理失败',
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('❌ $failedStage',
                  style: TextStyle(color: Colors.red[900])),
            ),
            if (_retrying)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新处理'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioPath = _storageService.getAudioPath(
        widget.entry.folderPath, widget.entry.audioFormat);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.entry.displayTitle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (AppTitle.isDev) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'dev',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteDiary),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 信息栏
                  DetailInfoBar(entry: widget.entry),
                  // 标签行
                  if (!_hasLlm)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('⏳ 处理中...',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    )
                  else if (_tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ..._tags.map((tag) => Chip(
                                label: Text(tag.name,
                                    style: const TextStyle(fontSize: 12)),
                                onDeleted: () async {
                                  await _storageService.removeDiaryTag(
                                      widget.entry.id, tag.id);
                                  final updatedTag =
                                      await _storageService.getTagById(tag.id);
                                  if (mounted) {
                                    await showTagEditorSheet(context,
                                        tag: updatedTag, isRemoval: true);
                                    _loadTags();
                                  }
                                },
                                deleteIconColor: Colors.grey,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              )),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: const Text('标签',
                                style: TextStyle(fontSize: 12)),
                            onPressed: () async {
                              final selectedIds = await showTagSelectorSheet(
                                context,
                                selectedTagIds:
                                    _tags.map((t) => t.id).toList(),
                              );
                              if (selectedIds != null && mounted) {
                                final currentIds =
                                    _tags.map((t) => t.id).toSet();
                                final newIds = selectedIds.toSet();
                                for (final id
                                    in newIds.difference(currentIds)) {
                                  await _storageService.addDiaryTag(
                                      widget.entry.id, id);
                                  final tag =
                                      await _storageService.getTagById(id);
                                  if (mounted) {
                                    await showTagEditorSheet(context,
                                        tag: tag, isRemoval: false);
                                  }
                                }
                                for (final id
                                    in currentIds.difference(newIds)) {
                                  await _storageService.removeDiaryTag(
                                      widget.entry.id, id);
                                  final tag =
                                      await _storageService.getTagById(id);
                                  if (mounted) {
                                    await showTagEditorSheet(context,
                                        tag: tag, isRemoval: true);
                                  }
                                }
                                _loadTags();
                              }
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  // 播放器区域
                  if (_audioExists)
                    DetailPlayerSection(
                      playerService: _playerService,
                      audioFilePath: audioPath,
                      utterances: _activeUtterances,
                      hasTranscript: _hasTranscript,
                    ),
                  const SizedBox(height: 16),
                  // 处理状态横幅
                  _buildStatusBanner(),
                  const SizedBox(height: 16),
                  // 润色正文
                  if (_hasLlm && _content.isNotEmpty)
                    DetailContentSection(content: _content),
                ],
              ),
            ),
    );
  }
}

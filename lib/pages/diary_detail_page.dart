import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;

import '../models/diary_entry.dart';
import '../models/tag.dart';
import '../models/utterance.dart';
import '../services/asr_service.dart';
import '../services/audio_player_service.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';
import '../widgets/app_title.dart';
import '../widgets/audio_player_bar.dart';
import '../widgets/tag_editor_sheet.dart';
import '../widgets/tag_selector_sheet.dart';
import '../widgets/timestamped_text_view.dart';
import 'diary_list_page.dart';

class DiaryDetailPage extends StatefulWidget {
  final DiaryEntry entry;

  const DiaryDetailPage({super.key, required this.entry});

  @override
  State<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends State<DiaryDetailPage> {
  final _playerService = AudioPlayerService();
  final _storageService = DiaryStorageService();
  final _asrService = AsrService();
  final _llmService = LlmService();
  String _summary = '';
  String _content = '';
  List<Utterance> _summaryUtterances = [];
  TranscriptData? _transcriptData;
  bool _loading = true;
  bool _needsRetry = false;
  bool _retrying = false;
  String _retryError = '';
  List<Tag> _tags = [];

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final audioPath = _storageService.getAudioPath(
        widget.entry.folderPath, widget.entry.audioFormat);
    final audioExists = File(audioPath).existsSync();
    final transcriptExists =
        await File(p.join(widget.entry.folderPath, 'transcript.json'))
            .exists();
    final hasLlm = await _storageService.hasLlmResult(widget.entry.folderPath);

    if (audioExists && (!transcriptExists || !hasLlm)) {
      if (mounted) {
        setState(() {
          _needsRetry = true;
          _loading = false;
        });
      }
      _loadTags();
      return;
    }

    TranscriptData? transcriptData;
    try {
      transcriptData =
          await _storageService.readTranscriptJson(widget.entry.folderPath);
    } catch (_) {}

    String summary = '';
    String content = '';
    List<Utterance> summaryUtterances = [];

    if (hasLlm) {
      final llmData =
          await _storageService.readLlmResult(widget.entry.folderPath);
      summary = llmData.summary.isNotEmpty ? llmData.summary : llmData.content;
      content = llmData.content;
      summaryUtterances = llmData.utterances;
    } else {
      try {
        summary = await _storageService.readSummary(widget.entry.folderPath);
      } catch (_) {
        summary = '';
      }
      content = summary;
      try {
        final summaryData = await _storageService
            .readSummaryUtterances(widget.entry.folderPath);
        summaryUtterances = summaryData.utterances;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _summary = summary;
        _content = content;
        _summaryUtterances = summaryUtterances;
        _transcriptData = transcriptData;
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

  @override
  void dispose() {
    _playerService.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _retryError = '';
    });

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
        _needsRetry = false;
        _retrying = false;
        _loading = true;
      });
      await _loadContent();
    } catch (e) {
      setState(() {
        _retrying = false;
        _retryError = e.toString();
      });
    }
  }

  Widget _buildRetryView(String audioPath) {
    final audioExists = File(audioPath).existsSync();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('处理未完成', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text('网络请求失败，音频已保存。',
                style: TextStyle(color: Colors.grey)),
            if (_retryError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_retryError,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            if (_retrying)
              const CircularProgressIndicator()
            else ...[
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              if (audioExists) ...[
                const SizedBox(height: 16),
                AudioPlayerBar(
                    playerService: _playerService,
                    audioFilePath: audioPath),
              ],
            ],
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final audioPath = _storageService.getAudioPath(
        widget.entry.folderPath, widget.entry.audioFormat);
    final audioExists = File(audioPath).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: AppTitle.wrap(Text(widget.entry.displayTitle)),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteDiary),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _needsRetry
              ? _buildRetryView(audioPath)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.entry.formattedDate}  ${widget.entry.durationDisplay}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_tags.isNotEmpty ||
                          !_needsRetry) ...[
                        const SizedBox(height: 8),
                        Wrap(
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
                                        await _storageService.getTagById(
                                            tag.id);
                                    if (mounted) {
                                      await showTagEditorSheet(context,
                                          tag: updatedTag, isRemoval: true);
                                      _loadTags();
                                    }
                                  },
                                  deleteIconColor: Colors.grey,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                )),
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: const Text('标签',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: () async {
                                final selectedIds =
                                    await showTagSelectorSheet(
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
                                    final tag = await _storageService
                                        .getTagById(id);
                                    if (mounted) {
                                      await showTagEditorSheet(context,
                                          tag: tag, isRemoval: false);
                                    }
                                  }
                                  for (final id
                                      in currentIds.difference(newIds)) {
                                    await _storageService.removeDiaryTag(
                                        widget.entry.id, id);
                                    final tag = await _storageService
                                        .getTagById(id);
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
                      ],
                      const SizedBox(height: 16),
                      if (audioExists)
                        AudioPlayerBar(
                            playerService: _playerService,
                            audioFilePath: audioPath),
                      const SizedBox(height: 16),
                      if (audioExists && _summaryUtterances.isNotEmpty)
                        TimestampedTextView(
                          utterances: _summaryUtterances,
                          playerService: _playerService,
                        )
                      else
                        MarkdownBody(data: _summary),
                      const SizedBox(height: 24),
                      ExpansionTile(
                        title: const Text('润色正文'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: MarkdownBody(data: _content),
                          ),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text('原始识别文本'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _transcriptData?.fullText ?? '',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}

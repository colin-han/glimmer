import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import '../services/audio_player_service.dart';
import '../services/diary_storage_service.dart';
import '../widgets/audio_player_bar.dart';
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
  String _summary = '';
  List<Utterance> _summaryUtterances = [];
  TranscriptData? _transcriptData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final summary =
        await _storageService.readSummary(widget.entry.folderPath);
    final transcriptData =
        await _storageService.readTranscriptJson(widget.entry.folderPath);

    List<Utterance> summaryUtterances = [];
    try {
      final summaryData = await _storageService
          .readSummaryUtterances(widget.entry.folderPath);
      summaryUtterances = summaryData.utterances;
    } catch (_) {
      // summary_utterances.json 可能不存在（旧数据 migration 已清除）
    }

    if (mounted) {
      setState(() {
        _summary = summary;
        _summaryUtterances = summaryUtterances;
        _transcriptData = transcriptData;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _playerService.dispose();
    super.dispose();
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
              child: const Text('删除', style: TextStyle(color: Colors.red))),
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
    final audioPath = p.join(widget.entry.folderPath, 'audio.wav');
    final audioExists = File(audioPath).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.displayTitle),
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
                  Text(
                    '${widget.entry.formattedDate}  ${widget.entry.durationDisplay}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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

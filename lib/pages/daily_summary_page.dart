import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../design_tokens.dart';
import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import '../services/diary_storage_service.dart';
import '../services/recording_processor.dart';
import '../services/tts_service.dart';
import '../widgets/detail/detail_content_section.dart';
import 'diary_detail_page.dart';

class DailySummaryPage extends StatefulWidget {
  /// 日期 'yyyy-MM-dd'。
  final String date;

  const DailySummaryPage({super.key, required this.date});

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  final _storageService = DiaryStorageService();
  final _ttsService = TtsService();

  bool _loading = true;
  DailySummary? _summary;
  DailySummaryData? _data;
  List<DiaryEntry> _entries = const [];
  bool _isActivelyProcessing = false;
  bool _isPlayingTts = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  Future<void> _loadData() async {
    final summary = await _storageService.getDailySummary(widget.date);
    final entries = await _storageService.getEntriesByDate(widget.date);
    DailySummaryData? data;
    if (await _storageService.hasDailySummary(widget.date)) {
      try {
        data = await _storageService.readDailySummaryJson(widget.date);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _summary = summary;
        _entries = entries;
        _data = data;
        _loading = false;
      });
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    final date = data['date'] as String?;
    if (date != null && date != widget.date) return;

    if (type == 'dailySummaryStage' && mounted) {
      setState(() => _isActivelyProcessing = true);
    } else if ((type == 'dailySummaryCompleted' ||
            type == 'dailySummaryFailed') &&
        mounted) {
      setState(() => _isActivelyProcessing = false);
      _loadData();
    }
  }

  String get _dateDisplay {
    final d = DateTime.parse(widget.date);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}';
  }

  DayWeatherSummary get _weather => aggregateDayWeather(_entries);

  Future<void> _playOutline() async {
    if (_data == null || _data!.outline.isEmpty) return;
    setState(() => _isPlayingTts = true);
    try {
      await _ttsService.speak(_data!.outline, VoiceType.femaleSweet);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('播报失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPlayingTts = false);
    }
  }

  Future<void> _regenerate() async {
    final now = DateTime.now();
    final existing = await _storageService.getDailySummary(widget.date);
    await _storageService.saveDailySummary(
      DailySummary(
        date: widget.date,
        title: '正在生成…',
        status: EntryStatus.processing,
        sourceEntryIds: existing?.sourceEntryIds ?? const [],
        entryCount: existing?.entryCount ?? 0,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    await ensureProcessingFgsRunning(notificationText: '生成每日总结...');
    if (mounted) setState(() => _isActivelyProcessing = true);
    _loadData();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除每日总结'),
        content: const Text('删除总结不影响当天的录音，确定删除吗？'),
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
      await _storageService.deleteDailySummary(widget.date);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weatherDisplay = _weather.display;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dateDisplay, style: const TextStyle(fontSize: 16)),
            if (weatherDisplay.isNotEmpty)
              Text(
                weatherDisplay,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: WarmTokens.warmMuted,
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'regen') {
                _regenerate();
              } else if (v == 'delete') {
                _delete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'regen', child: Text('重新生成')),
              PopupMenuItem(value: 'delete', child: Text('删除总结')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusBanner(),
                    if (_data?.degraded == true)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: WarmTokens.warmMuted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '当天内容较长，基于各篇摘要生成',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: WarmTokens.warmMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_data != null && _data!.summary.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DetailContentSection(summary: _data!.summary),
                    ],
                    if (_data != null && _data!.outline.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildOutlineSection(),
                    ],
                    const SizedBox(height: 24),
                    _buildEntryList(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _summary?.status;
    if (status == EntryStatus.processing) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WarmTokens.warmProcessBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
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
              _isActivelyProcessing ? '正在生成每日总结...' : '生成暂停',
              style: const TextStyle(color: WarmTokens.warmBrown, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (status == EntryStatus.failed) {
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
            const Expanded(
              child: Text(
                '生成失败',
                style: TextStyle(color: WarmTokens.failedText, fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('重试', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: WarmTokens.failedAccent,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildOutlineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: WarmTokens.warmAmber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '概览播报',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WarmTokens.warmBrown,
              ),
            ),
            const Spacer(),
            if (_isPlayingTts)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.volume_up),
                onPressed: _playOutline,
                tooltip: '播报',
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _data!.outline,
          style: TextStyle(
            fontSize: 14,
            height: 1.8,
            color: WarmTokens.warmBrown,
          ),
        ),
      ],
    );
  }

  Widget _buildEntryList() {
    if (_entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: WarmTokens.warmAmber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '当天录音 ${_entries.length} 篇',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WarmTokens.warmBrown,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._entries.map(_buildEntryItem),
      ],
    );
  }

  Widget _buildEntryItem(DiaryEntry e) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: e)))
            .then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WarmTokens.warmCardBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: WarmTokens.warmBrown),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${e.formattedDate} · ${e.durationDisplay}',
                    style: TextStyle(fontSize: 12, color: WarmTokens.warmMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: WarmTokens.warmMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

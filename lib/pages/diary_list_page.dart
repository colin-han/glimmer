import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../design_tokens.dart';
import '../models/diary_entry.dart';
import '../models/tag.dart';
import '../services/diary_storage_service.dart';
import '../widgets/app_title.dart';
import '../widgets/tag_chip_bar.dart';
import 'diary_detail_page.dart';
import 'recording_page.dart';
import 'tag_management_page.dart';

class DiaryListPage extends StatefulWidget {
  const DiaryListPage({super.key});

  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  final _storageService = DiaryStorageService();
  List<DiaryEntry> _entries = [];
  List<Tag> _tags = [];
  Map<String, List<Tag>> _entryTags = {};
  bool _loading = true;

  String? _selectedTagId;
  GroupMode _groupMode = GroupMode.date;
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    // 监听 FGS 消息，处理完成/失败时刷新列表
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  Future<void> _loadData() async {
    final entries = await _storageService.getAllEntries();
    final tags = await _storageService.getAllTags();
    final entryTags = <String, List<Tag>>{};
    for (final entry in entries) {
      entryTags[entry.id] =
          await _storageService.getFullTagsForDiary(entry.id);
    }
    if (mounted) {
      setState(() {
        _entries = entries;
        _tags = tags;
        _entryTags = entryTags;
        _loading = false;
      });
    }
  }

  List<DiaryEntry> get _filteredEntries {
    var result = _entries;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((e) {
        if (e.title.toLowerCase().contains(q)) return true;
        if ((_entryTags[e.id] ?? [])
            .any((t) => t.name.toLowerCase().contains(q))) return true;
        return false;
      }).toList();
    }

    if (_selectedTagId != null) {
      result = result.where((e) {
        return (_entryTags[e.id] ?? [])
            .any((t) => t.id == _selectedTagId);
      }).toList();
    }

    return result;
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _searchController.dispose();
    super.dispose();
  }

  /// 接收 FGS 消息，重试完成/失败时刷新列表
  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    if (type == 'completed' || type == 'failed') {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索日记...',
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const AppTitle(title: '我的日记'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.label),
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (_) => const TagManagementPage()))
                  .then((_) => _loadData());
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: TagChipBar(
                          tags: _tags,
                          selectedTagId: _selectedTagId,
                          groupMode: _groupMode,
                          onTagSelected: (id) =>
                              setState(() => _selectedTagId = id),
                          onGroupModeChanged: (mode) =>
                              setState(() => _groupMode = mode),
                        ),
                      ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('没有匹配的日记',
                              style: TextStyle(color: WarmTokens.warmMuted)))
                          : _groupMode == GroupMode.date
                              ? _buildDateGroups(filtered)
                              : _buildTagGroups(filtered),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RecordingPage()),
          );
        },
        child: const Icon(Icons.mic),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.book_outlined, size: 64, color: WarmTokens.warmMuted),
          const SizedBox(height: 16),
          Text('还没有日记，点击 + 开始录音',
              style: TextStyle(fontSize: 16, color: WarmTokens.warmMuted)),
        ],
      ),
    );
  }

  Widget _buildDateGroups(List<DiaryEntry> entries) {
    final groups = <String, List<DiaryEntry>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in entries) {
      final date = DateTime(
          entry.createdAt.year, entry.createdAt.month, entry.createdAt.day);
      final diff = today.difference(date).inDays;
      final label = _getDateLabel(entry.createdAt, diff);
      groups.putIfAbsent(label, () => []).add(entry);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: groups.entries
            .expand((group) => [
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text(
                      group.key,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: WarmTokens.warmMuted),
                    ),
                  ),
                  ...group.value.map((entry) => _buildEntryCard(entry)),
                ])
            .toList(),
      ),
    );
  }

  String _getDateLabel(DateTime date, int daysDiff) {
    final monthDay = '${date.month}月${date.day}日';
    if (daysDiff == 0) return '今天（$monthDay）';
    if (daysDiff == 1) return '昨天（$monthDay）';
    if (daysDiff < 7) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '${weekdays[date.weekday - 1]}（$monthDay）';
    }
    if (daysDiff < 14) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '上周${weekdays[date.weekday - 1]}（$monthDay）';
    }
    return monthDay;
  }

  Widget _buildTagGroups(List<DiaryEntry> entries) {
    final tagGroups = <Tag, List<DiaryEntry>>{};
    final taggedIds = <String>{};

    for (final tag in _tags) {
      final tagged = entries.where((e) {
        return (_entryTags[e.id] ?? []).any((t) => t.id == tag.id);
      }).toList();
      if (tagged.isNotEmpty) {
        tagGroups[tag] = tagged;
        taggedIds.addAll(tagged.map((e) => e.id));
      }
    }

    final untagged =
        entries.where((e) => !taggedIds.contains(e.id)).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...tagGroups.entries
              .expand((group) => [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(
                        '${group.key.name}（${group.value.length}）',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: WarmTokens.warmMuted),
                      ),
                    ),
                    ...group.value
                        .map((entry) => _buildEntryCard(entry)),
                  ]),
          if (untagged.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                '未分类（${untagged.length}）',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: WarmTokens.warmMuted),
              ),
            ),
            ...untagged.map((entry) => _buildEntryCard(entry)),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryCard(DiaryEntry entry) {
    final tags = _entryTags[entry.id] ?? [];
    final isProcessing = entry.status == EntryStatus.processing;
    final isFailed = entry.status == EntryStatus.failed;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isFailed ? WarmTokens.failedBg : null,
      child: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.displayTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: tags
                      .map((tag) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _getTagColor(tag)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(tag.name,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: _getTagColor(tag))),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '${entry.formattedDate}  ${entry.durationDisplay}${entry.weatherDisplay.isNotEmpty ? '  ${entry.weatherDisplay}' : ''}'),
        ),
        trailing: isProcessing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: WarmTokens.warmMuted),
              )
            : isFailed
                ? Icon(Icons.error_outline, color: WarmTokens.failedAccent, size: 20)
                : const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (_) => DiaryDetailPage(entry: entry)))
              .then((_) => _loadData());
        },
      ),
    );
  }

  Color _getTagColor(Tag tag) {
    if (tag.color != null) {
      try {
        return Color(int.parse(tag.color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return Theme.of(context).colorScheme.primary;
  }
}

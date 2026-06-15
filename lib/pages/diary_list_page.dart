import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../design_tokens.dart';
import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import '../models/tag.dart';
import '../services/diary_storage_service.dart';
import '../widgets/app_title.dart';
import '../widgets/tag_chip_bar.dart';
import 'daily_summary_page.dart';
import 'diary_detail_page.dart';
import 'recording_page.dart';
import 'tag_management_page.dart';
import '../services/recording_processor.dart' show ensureProcessingFgsRunning;

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
  Map<String, DailySummary> _dailySummaries = {};
  bool _loading = true;
  int _loadVersion = 0; // 并发保护：_loadData 版本号

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
    // 并发保护：_onTaskData / onRefresh / 页面返回 .then 等多处可能并发触发 _loadData，
    // 用版本号确保只有最后一次发起的加载结果写入 UI，避免旧结果覆盖新结果。
    final version = ++_loadVersion;
    final entries = await _storageService.getAllEntries();
    final tags = await _storageService.getAllTags();
    // 复用上面已查的 tags，避免 getAllEntryTags 内部重复查询 tags 表
    final entryTags = await _storageService.getAllEntryTags(allTags: tags);
    final dailySummaries = await _storageService.getAllDailySummaries();
    if (version != _loadVersion) return;
    if (mounted) {
      setState(() {
        _entries = entries;
        _tags = tags;
        _entryTags = entryTags;
        _dailySummaries = {for (final d in dailySummaries) d.date: d};
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
        if ((_entryTags[e.id] ?? []).any(
          (t) => t.name.toLowerCase().contains(q),
        )) {
          return true;
        }
        return false;
      }).toList();
    }

    if (_selectedTagId != null) {
      result = result.where((e) {
        return (_entryTags[e.id] ?? []).any((t) => t.id == _selectedTagId);
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

  /// 接收 FGS 消息，录音/每日总结完成/失败/阶段更新时刷新列表
  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    if (type == 'completed' ||
        type == 'failed' ||
        type == 'dailySummaryCompleted' ||
        type == 'dailySummaryFailed' ||
        type == 'dailySummaryStage') {
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
                decoration: InputDecoration(
                  hintText: '搜索日记...',
                  hintStyle: TextStyle(color: WarmTokens.warmMuted),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: WarmTokens.warmBrown),
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
                  .push(
                    MaterialPageRoute(
                      builder: (_) => const TagManagementPage(),
                    ),
                  )
                  .then((_) => _loadData());
            },
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: WarmTokens.warmAmber.withValues(alpha: 0.6),
              ),
            )
          : _entries.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                if (_tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                      ? Center(
                          child: Text(
                            '没有匹配的日记',
                            style: TextStyle(
                              fontSize: 15,
                              color: WarmTokens.warmMuted,
                            ),
                          ),
                        )
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

  // ─── 空状态 ───────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: WarmTokens.warmSurface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 40,
                color: WarmTokens.warmAmber,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '还没有日记',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: WarmTokens.warmBrown,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角 🎙️ 开始第一篇',
              style: TextStyle(fontSize: 14, color: WarmTokens.warmMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 分组标题（琥珀色竖线装饰） ──────────────────────────────────

  Widget _buildGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10, left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: WarmTokens.warmAmber,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WarmTokens.warmMuted,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 日期分组 ───────────────────────────────────────────────

  Widget _buildDateGroups(List<DiaryEntry> entries) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    // 按 dateKey 'yyyy-MM-dd' 分组，保留插入顺序（entries 已按 createdAt desc）
    final groups = <String, List<DiaryEntry>>{};
    for (final entry in entries) {
      final key = _dateKey(entry.createdAt);
      groups.putIfAbsent(key, () => []).add(entry);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: WarmTokens.warmAmber,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: groups.entries.expand((group) {
          final date = DateTime.parse(group.key);
          final diff = todayDate.difference(date).inDays;
          final label = _getDateLabel(date, diff);
          return [
            _buildGroupHeader(label),
            _buildDailySummaryRow(group.key),
            ...group.value.map((entry) => _buildEntryCard(entry)),
          ];
        }).toList(),
      ),
    );
  }

  /// DateTime → 'yyyy-MM-dd'。
  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 请求生成/重新生成某天的每日总结：置 status=processing + 启动 FGS。
  Future<void> _requestDailySummary(String dateKey) async {
    final now = DateTime.now();
    final existing = _dailySummaries[dateKey];
    await _storageService.saveDailySummary(
      DailySummary(
        date: dateKey,
        title: '正在生成…',
        status: EntryStatus.processing,
        sourceEntryIds: existing?.sourceEntryIds ?? const [],
        entryCount: existing?.entryCount ?? 0,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    await ensureProcessingFgsRunning(notificationText: '生成每日总结...');
    _loadData();
  }

  /// 每个日期分组下的「本日总结」行，按 DailySummary 状态自适应。
  Widget _buildDailySummaryRow(String dateKey) {
    final summary = _dailySummaries[dateKey];

    // processing：转圈
    if (summary?.status == EntryStatus.processing) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WarmTokens.warmProcessBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WarmTokens.warmAmber,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '⏳ 正在生成本日总结…',
              style: TextStyle(fontSize: 14, color: WarmTokens.warmBrown),
            ),
          ],
        ),
      );
    }

    // failed：重试
    if (summary?.status == EntryStatus.failed) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WarmTokens.failedBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: WarmTokens.failedAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠ 生成失败',
                style: TextStyle(fontSize: 14, color: WarmTokens.failedText),
              ),
            ),
            TextButton(
              onPressed: () => _requestDailySummary(dateKey),
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // completed：标题预览 + 重新生成
    if (summary?.status == EntryStatus.completed) {
      final s = summary!;
      return GestureDetector(
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => DailySummaryPage(date: dateKey),
                ),
              )
              .then((_) => _loadData());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: WarmTokens.warmCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: WarmTokens.warmAmber.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_stories, size: 18, color: WarmTokens.warmAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WarmTokens.warmBrown,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _requestDailySummary(dateKey),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh,
                    size: 16,
                    color: WarmTokens.warmMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 无记录：生成本日总结
    return GestureDetector(
      onTap: () => _requestDailySummary(dateKey),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WarmTokens.warmAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: WarmTokens.warmAmber.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_note, size: 18, color: WarmTokens.warmAmber),
            const SizedBox(width: 8),
            Text(
              '📝 生成本日总结',
              style: TextStyle(
                fontSize: 14,
                color: WarmTokens.warmAmber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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

  // ─── 标签分组 ───────────────────────────────────────────────

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

    final untagged = entries.where((e) => !taggedIds.contains(e.id)).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: WarmTokens.warmAmber,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...tagGroups.entries.expand(
            (group) => [
              _buildGroupHeader('${group.key.name}（${group.value.length}）'),
              ...group.value.map((entry) => _buildEntryCard(entry)),
            ],
          ),
          if (untagged.isNotEmpty) ...[
            _buildGroupHeader('未分类（${untagged.length}）'),
            ...untagged.map((entry) => _buildEntryCard(entry)),
          ],
        ],
      ),
    );
  }

  // ─── 日记卡片 ───────────────────────────────────────────────

  Widget _buildEntryCard(DiaryEntry entry) {
    final tags = _entryTags[entry.id] ?? [];
    final isProcessing = entry.status == EntryStatus.processing;
    final isFailed = entry.status == EntryStatus.failed;

    // 卡片背景色
    final bgColor = isFailed
        ? WarmTokens.failedBg
        : isProcessing
        ? WarmTokens.warmProcessBg
        : WarmTokens.warmCardBg;

    // 边框色
    final borderColor = isFailed
        ? WarmTokens.failedAccent.withValues(alpha: 0.3)
        : WarmTokens.warmDivider;

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: entry)),
            )
            .then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：标题 + 状态
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isFailed
                          ? WarmTokens.failedText
                          : WarmTokens.warmBrown,
                      height: 1.4,
                    ),
                  ),
                ),
                if (isProcessing)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: WarmTokens.warmAmber,
                      ),
                    ),
                  ),
                if (isFailed)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.error_outline,
                      color: WarmTokens.failedAccent,
                      size: 18,
                    ),
                  ),
              ],
            ),

            // 第二行：元数据
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _buildMetadataRow(entry),
            ),

            // 第三行：标签
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildTagChips(tags),
              ),
          ],
        ),
      ),
    );
  }

  // ─── 元数据行 ───────────────────────────────────────────────

  Widget _buildMetadataRow(DiaryEntry entry) {
    final items = <Widget>[];

    // 时间
    items.add(_metaIconText(Icons.access_time, entry.formattedDate));

    // 时长
    items.add(_metaIconText(Icons.timer_outlined, entry.durationDisplay));

    // 天气信息
    if (entry.weatherDisplay.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            entry.weatherDisplay,
            style: TextStyle(
              fontSize: 12,
              color: WarmTokens.warmMuted,
              height: 1.3,
            ),
          ),
        ),
      );
    }

    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: items);
  }

  Widget _metaIconText(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: WarmTokens.warmMuted),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: WarmTokens.warmMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 标签 chips ───────────────────────────────────────────────

  Widget _buildTagChips(List<Tag> tags) {
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: tags.map((tag) {
        final color = _getTagColor(tag);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
          ),
          child: Text(
            tag.name,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        );
      }).toList(),
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

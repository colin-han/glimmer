import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../design_tokens.dart';
import '../models/tag.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';
import '../widgets/app_title.dart';

class TagManagementPage extends StatefulWidget {
  const TagManagementPage({super.key});

  @override
  State<TagManagementPage> createState() => _TagManagementPageState();
}

class _TagManagementPageState extends State<TagManagementPage> {
  final _storageService = DiaryStorageService();
  final _llmService = LlmService();
  final _uuid = const Uuid();
  List<Tag> _tags = [];
  Map<String, int> _diaryCounts = {};
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _storageService.getAllTags();
    final counts = <String, int>{};
    for (final tag in tags) {
      counts[tag.id] = await _storageService.getDiaryCountForTag(tag.id);
    }
    if (mounted) {
      setState(() {
        _tags = tags;
        _diaryCounts = counts;
        _loading = false;
      });
    }
  }

  Future<void> _createTag() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('新建标签'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '标签名称'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('创建')),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    setState(() => _creating = true);
    try {
    final tag = Tag(
      id: _uuid.v4(),
      name: name,
      matchPrompt: '',
      createdAt: DateTime.now(),
    );
    await _storageService.createTag(tag);

    if (mounted) {
      final confirmedDiaryIds = await _showRecommendations(tag);
      if (confirmedDiaryIds != null && confirmedDiaryIds.isNotEmpty) {
        try {
          final entries = await _storageService.getAllEntries();
          final confirmedEntries = entries
              .where((e) => confirmedDiaryIds.contains(e.id))
              .toList();
          final diarySummaries = <DiarySummaryInfo>[];
          for (final entry in confirmedEntries) {
            String summary = '';
            try {
              if (await _storageService.hasLlmResult(entry.folderPath)) {
                final llmData =
                    await _storageService.readLlmResult(entry.folderPath);
                summary = llmData.summary.length > 200
                    ? llmData.summary.substring(0, 200)
                    : llmData.summary;
              }
            } catch (_) {}
            diarySummaries.add(DiarySummaryInfo(
                id: entry.id, title: entry.title, summary: summary));
          }
          final prompt =
              await _llmService.generateMatchPrompt(name, diarySummaries);
          final updatedTag = Tag(
            id: tag.id,
            name: tag.name,
            matchPrompt: prompt,
            color: tag.color,
            createdAt: tag.createdAt,
          );
          await _storageService.updateTag(updatedTag);

          for (final diaryId in confirmedDiaryIds) {
            await _storageService.addDiaryTag(diaryId, tag.id,
                source: 'manual');
          }
        } catch (e) {
          debugPrint('生成提示词失败: $e');
        }
      }
      _loadTags();
    }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<List<String>?> _showRecommendations(Tag tag) async {
    final entries = await _storageService.getAllEntries();
    final diarySummaries = <DiarySummaryInfo>[];
    for (final entry in entries) {
      String summary = '';
      try {
        if (await _storageService.hasLlmResult(entry.folderPath)) {
          final llmData =
              await _storageService.readLlmResult(entry.folderPath);
          summary = llmData.summary.length > 200
              ? llmData.summary.substring(0, 200)
              : llmData.summary;
        }
      } catch (_) {}
      diarySummaries.add(
          DiarySummaryInfo(id: entry.id, title: entry.title, summary: summary));
    }

    final recommendations =
        await _llmService.recommendDiariesForTag(tag.name, diarySummaries);
    if (recommendations.isEmpty) return [];
    if (!mounted) return null;

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final selected = <String>{};
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('「${tag.name}」推荐日记'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: recommendations.length,
                  itemBuilder: (_, index) {
                    final rec = recommendations[index];
                    final entry =
                        entries.firstWhere((e) => e.id == rec.diaryId);
                    return CheckboxListTile(
                      value: selected.contains(rec.diaryId),
                      title: Text(entry.displayTitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(rec.reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            selected.add(rec.diaryId);
                          } else {
                            selected.remove(rec.diaryId);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, <String>[]),
                    child: const Text('跳过')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, selected.toList()),
                    child: const Text('确认')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editTag(Tag tag) async {
    final nameController = TextEditingController(text: tag.name);
    final promptController = TextEditingController(text: tag.matchPrompt);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('编辑「${tag.name}」'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '标签名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '匹配提示词',
                  hintText: '描述什么样的日记内容属于该标签',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        );
      },
    );

    if (result == true) {
      await _storageService.updateTag(Tag(
        id: tag.id,
        name: nameController.text.trim().isNotEmpty
            ? nameController.text.trim()
            : tag.name,
        matchPrompt: promptController.text.trim(),
        color: tag.color,
        createdAt: tag.createdAt,
      ));
      _loadTags();
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${tag.name}」'),
        content: Text('删除后所有日记的该标签关联也会移除，确定删除吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除',
                  style: TextStyle(color: WarmTokens.failedAccent))),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.deleteTag(tag.id);
      _loadTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(title: '标签管理'),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _tags.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.label_off,
                              size: 64, color: WarmTokens.warmMuted),
                          const SizedBox(height: 16),
                          Text('还没有标签',
                              style: TextStyle(
                                  fontSize: 16, color: WarmTokens.warmMuted)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _tags.length,
                      itemBuilder: (context, index) {
                        final tag = _tags[index];
                        final count = _diaryCounts[tag.id] ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: tag.color != null
                                  ? _parseColor(tag.color!)
                                  : Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              child: Text(tag.name[0],
                                  style:
                                      const TextStyle(color: Colors.white)),
                            ),
                            title: Text(tag.name),
                            subtitle: Text(
                                '$count 篇日记${tag.matchPrompt.isNotEmpty ? ' · 已设置匹配规则' : ''}',
                                style: TextStyle(
                                    fontSize: 12, color: WarmTokens.warmMuted)),
                            trailing: PopupMenuButton(
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit', child: Text('编辑')),
                                const PopupMenuItem(
                                    value: 'delete', child: Text('删除')),
                              ],
                              onSelected: (val) {
                                if (val == 'edit') _editTag(tag);
                                if (val == 'delete') _deleteTag(tag);
                              },
                            ),
                            onTap: () => _editTag(tag),
                          ),
                        );
                      },
                    ),
          if (_creating)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('AI 正在分析日记...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _creating ? null : _createTag,
        child: const Icon(Icons.add),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return WarmTokens.warmAmber;
    }
  }
}

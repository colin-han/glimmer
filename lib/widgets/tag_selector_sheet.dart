import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/tag.dart';
import '../services/diary_storage_service.dart';

Future<List<String>?> showTagSelectorSheet(
  BuildContext context, {
  required List<String> selectedTagIds,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TagSelectorContent(selectedTagIds: selectedTagIds),
  );
}

class _TagSelectorContent extends StatefulWidget {
  final List<String> selectedTagIds;

  const _TagSelectorContent({required this.selectedTagIds});

  @override
  State<_TagSelectorContent> createState() => _TagSelectorContentState();
}

class _TagSelectorContentState extends State<_TagSelectorContent> {
  final _storageService = DiaryStorageService();
  List<Tag> _tags = [];
  late Set<String> _selectedIds;
  bool _loading = true;
  bool _showCreateField = false;
  final _newTagNameController = TextEditingController();
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedTagIds);
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _storageService.getAllTags();
    if (mounted) {
      setState(() {
        _tags = tags;
        _loading = false;
      });
    }
  }

  Future<void> _createTag(String name) async {
    final trimmed = name.trim();
    // tags.name 有唯一约束，直接 insert 重名会触发 UniqueIntegrityException；
    // 先在已加载列表里查重，命中则复用已有标签，避免崩溃。
    Tag? dup;
    for (final t in _tags) {
      if (t.name == trimmed) {
        dup = t;
        break;
      }
    }
    final tagId = dup?.id ?? _uuid.v4();
    if (dup == null) {
      await _storageService.createTag(Tag(
        id: tagId,
        name: trimmed,
        matchPrompt: '',
        createdAt: DateTime.now(),
      ));
    }
    _selectedIds.add(tagId);
    _newTagNameController.clear();
    _showCreateField = false;
    await _loadTags();
  }

  @override
  void dispose() {
    _newTagNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('选择标签', style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => Navigator.pop(context, _selectedIds.toList()),
                child: const Text('完成'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags.map((tag) {
                final selected = _selectedIds.contains(tag.id);
                return FilterChip(
                  label: Text(tag.name),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedIds.add(tag.id);
                      } else {
                        _selectedIds.remove(tag.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (_showCreateField)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTagNameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '输入新标签名称',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) _createTag(val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      if (_newTagNameController.text.trim().isNotEmpty) {
                        _createTag(_newTagNameController.text);
                      }
                    },
                  ),
                ],
              )
            else
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('新建标签'),
                onPressed: () => setState(() => _showCreateField = true),
              ),
          ],
        ],
      ),
    );
  }
}

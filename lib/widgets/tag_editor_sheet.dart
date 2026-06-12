import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../models/tag.dart';
import '../services/diary_storage_service.dart';

Future<void> showTagEditorSheet(
  BuildContext context, {
  required Tag tag,
  required bool isRemoval,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TagEditorContent(tag: tag, isRemoval: isRemoval),
  );
}

class _TagEditorContent extends StatefulWidget {
  final Tag tag;
  final bool isRemoval;

  const _TagEditorContent({required this.tag, required this.isRemoval});

  @override
  State<_TagEditorContent> createState() => _TagEditorContentState();
}

class _TagEditorContentState extends State<_TagEditorContent> {
  final _storageService = DiaryStorageService();
  late TextEditingController _promptController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.tag.matchPrompt);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updatedTag = Tag(
      id: widget.tag.id,
      name: widget.tag.name,
      matchPrompt: _promptController.text.trim(),
      color: widget.tag.color,
      createdAt: widget.tag.createdAt,
    );
    await _storageService.updateTag(updatedTag);
    if (mounted) Navigator.pop(context);
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
          Text(
            widget.isRemoval
                ? '调整「${widget.tag.name}」匹配规则'
                : '编辑「${widget.tag.name}」匹配规则',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (widget.isRemoval)
            Text(
              '已移除该标签。你可以调整匹配提示词，避免后续日记被自动打上此标签。',
              style: TextStyle(color: WarmTokens.warmMuted, fontSize: 13),
            )
          else
            Text(
              '你可以编辑匹配提示词，帮助 AI 更准确地自动归类。也可以直接跳过。',
              style: TextStyle(color: WarmTokens.warmMuted, fontSize: 13),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '匹配提示词',
              hintText: '描述什么样的日记内容属于该标签',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('跳过'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

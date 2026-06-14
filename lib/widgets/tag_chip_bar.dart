import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../models/tag.dart';

enum GroupMode { date, tag }

class TagChipBar extends StatelessWidget {
  final List<Tag> tags;
  final String? selectedTagId;
  final GroupMode groupMode;
  final ValueChanged<String?> onTagSelected;
  final ValueChanged<GroupMode> onGroupModeChanged;

  const TagChipBar({
    super.key,
    required this.tags,
    this.selectedTagId,
    required this.groupMode,
    required this.onTagSelected,
    required this.onGroupModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.start,
            children: [
              _buildChip(
                label: '全部',
                selected: selectedTagId == null,
                onTap: () => onTagSelected(null),
              ),
              ...tags.map(
                (tag) => _buildChip(
                  label: tag.name,
                  selected: selectedTagId == tag.id,
                  onTap: () =>
                      onTagSelected(selectedTagId == tag.id ? null : tag.id),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildGroupToggle(context),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        label: Text(label, style: TextStyle(fontSize: 12)),
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildGroupToggle(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WarmTokens.warmDivider,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleBtn(
            icon: Icons.calendar_today,
            selected: groupMode == GroupMode.date,
            onTap: () => onGroupModeChanged(GroupMode.date),
          ),
          _buildToggleBtn(
            icon: Icons.label,
            selected: groupMode == GroupMode.tag,
            onTap: () => onGroupModeChanged(GroupMode.tag),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? WarmTokens.warmCardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: selected ? null : WarmTokens.warmMuted,
        ),
      ),
    );
  }
}

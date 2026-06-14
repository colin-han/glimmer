import 'package:flutter/material.dart';

import '../../design_tokens.dart';
import '../../models/diary_entry.dart';

class DetailInfoBar extends StatelessWidget {
  final DiaryEntry entry;

  const DetailInfoBar({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final parts = <_InfoItem>[];

    // 日期时间
    parts.add(
      _InfoItem(icon: Icons.calendar_today_outlined, text: entry.formattedDate),
    );

    // 时长
    parts.add(
      _InfoItem(icon: Icons.timer_outlined, text: entry.durationDisplay),
    );

    // 位置
    if (entry.locationName != null && entry.locationName!.isNotEmpty) {
      parts.add(
        _InfoItem(icon: Icons.location_on_outlined, text: entry.locationName!),
      );
    }

    // 天气
    if (entry.weatherIcon != null || entry.weatherText != null) {
      final emoji = entry.weatherIcon != null
          ? (DiaryEntry.weatherEmoji(entry.weatherIcon!) ??
                entry.weatherText ??
                '')
          : entry.weatherText ?? '';
      if (emoji.isNotEmpty) {
        parts.add(_InfoItem(icon: null, text: emoji));
      }
    }

    // 温度
    if (entry.temperature != null && entry.temperature!.isNotEmpty) {
      parts.add(
        _InfoItem(
          icon: Icons.thermostat_outlined,
          text: '${entry.temperature}°C',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 0,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < parts.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildInfoChip(parts[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(_InfoItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.icon != null) ...[
          Icon(item.icon, size: 14, color: WarmTokens.warmMuted),
          const SizedBox(width: 4),
        ],
        Text(
          item.text,
          style: const TextStyle(
            fontSize: 12,
            color: WarmTokens.warmMuted,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _InfoItem {
  final IconData? icon;
  final String text;

  const _InfoItem({this.icon, required this.text});
}

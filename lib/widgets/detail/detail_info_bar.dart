import 'package:flutter/material.dart';

import '../../models/diary_entry.dart';

/// 暖色设计常量
class _DesignTokens {
  static const Color warmMuted = Color(0xFF9B8E7E);
}

class DetailInfoBar extends StatelessWidget {
  final DiaryEntry entry;

  const DetailInfoBar({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final parts = <_InfoItem>[];

    // 日期时间
    parts.add(_InfoItem(
      icon: Icons.calendar_today_outlined,
      text: entry.formattedDate,
    ));

    // 时长
    parts.add(_InfoItem(
      icon: Icons.timer_outlined,
      text: entry.durationDisplay,
    ));

    // 位置
    if (entry.locationName != null && entry.locationName!.isNotEmpty) {
      parts.add(_InfoItem(
        icon: Icons.location_on_outlined,
        text: entry.locationName!,
      ));
    }

    // 天气
    if (entry.weatherIcon != null || entry.weatherText != null) {
      final emoji = entry.weatherIcon != null
          ? (DiaryEntry.weatherEmoji(entry.weatherIcon!) ??
              entry.weatherText ??
              '')
          : entry.weatherText ?? '';
      if (emoji.isNotEmpty) {
        parts.add(_InfoItem(
          icon: null,
          text: emoji,
        ));
      }
    }

    // 温度
    if (entry.temperature != null && entry.temperature!.isNotEmpty) {
      parts.add(_InfoItem(
        icon: Icons.thermostat_outlined,
        text: '${entry.temperature}°C',
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 0,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            _buildInfoChip(parts[i]),
            if (i < parts.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '·',
                  style: TextStyle(
                    fontSize: 14,
                    color: _DesignTokens.warmMuted.withValues(alpha: 0.6),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(_InfoItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.icon != null) ...[
          Icon(
            item.icon,
            size: 14,
            color: _DesignTokens.warmMuted,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          item.text,
          style: const TextStyle(
            fontSize: 12,
            color: _DesignTokens.warmMuted,
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

import 'package:flutter/material.dart';

import '../../models/diary_entry.dart';

class DetailInfoBar extends StatelessWidget {
  final DiaryEntry entry;

  const DetailInfoBar({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final parts = <Widget>[];

    // 日期 + 时间
    parts.add(Text(entry.formattedDate, style: style));

    // 时长
    parts.add(Text('⏰${entry.durationDisplay}', style: style));

    // 位置
    if (entry.locationName != null && entry.locationName!.isNotEmpty) {
      parts.add(Text('📍${entry.locationName}', style: style));
    }

    // 天气
    if (entry.weatherIcon != null || entry.weatherText != null) {
      final emoji = entry.weatherIcon != null
          ? (DiaryEntry.weatherEmoji(entry.weatherIcon!) ?? entry.weatherText ?? '')
          : entry.weatherText ?? '';
      if (emoji.isNotEmpty) {
        parts.add(Text(emoji, style: style));
      }
    }

    // 温度
    if (entry.temperature != null && entry.temperature!.isNotEmpty) {
      parts.add(Text('🌡️${entry.temperature}°C', style: style));
    }

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }
}

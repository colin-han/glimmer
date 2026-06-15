import 'diary_entry.dart';

// --- 容错解析工具（与 utterance.dart 一致的降级风格）---
String _asString(dynamic v) =>
    v is String ? v : (v == null ? '' : v.toString());

int _asInt(dynamic v, [int def = 0]) =>
    v is int ? v : (v is num ? v.toInt() : def);

/// 每日总结的元数据，对应 SQLite DailySummaries 表的一行。
class DailySummary {
  /// 日期 'yyyy-MM-dd'，主键。
  final String date;
  final String title;
  final EntryStatus status;
  final List<String> sourceEntryIds;
  final int entryCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const DailySummary({
    required this.date,
    required this.title,
    required this.status,
    required this.sourceEntryIds,
    required this.entryCount,
    required this.createdAt,
    this.updatedAt,
  });

  DailySummary copyWith({
    String? title,
    EntryStatus? status,
    List<String>? sourceEntryIds,
    int? entryCount,
    DateTime? updatedAt,
  }) {
    return DailySummary(
      date: date,
      title: title ?? this.title,
      status: status ?? this.status,
      sourceEntryIds: sourceEntryIds ?? this.sourceEntryIds,
      entryCount: entryCount ?? this.entryCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 每日总结正文文件 `daily/daily_summary_<date>.json` 的模型。
class DailySummaryData {
  final int version;
  final String date;
  final String title;
  final String summary;
  final String outline;
  final List<String> sourceEntryIds;
  final bool degraded;

  const DailySummaryData({
    required this.version,
    required this.date,
    required this.title,
    required this.summary,
    required this.outline,
    required this.sourceEntryIds,
    required this.degraded,
  });

  factory DailySummaryData.fromJson(Map<String, dynamic> json) {
    return DailySummaryData(
      version: _asInt(json['version'], 1),
      date: _asString(json['date']),
      title: _asString(json['title']),
      summary: _asString(json['summary']),
      outline: _asString(json['outline']),
      sourceEntryIds:
          (json['sourceEntryIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      degraded: json['degraded'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'date': date,
    'title': title,
    'summary': summary,
    'outline': outline,
    'sourceEntryIds': sourceEntryIds,
    'degraded': degraded,
  };
}

/// 一天的天气聚合结果（详情页现算，不入库）。
class DayWeatherSummary {
  final String? locationName;
  final String? weatherIcon;
  final String? weatherText;
  final num? tempMin;
  final num? tempMax;

  const DayWeatherSummary({
    this.locationName,
    this.weatherIcon,
    this.weatherText,
    this.tempMin,
    this.tempMax,
  });

  bool get isEmpty =>
      locationName == null &&
      weatherIcon == null &&
      weatherText == null &&
      tempMin == null &&
      tempMax == null;

  /// 温度展示：无数据→''；全相同→'24°'；有差异→'18°~25°'。
  String get tempDisplay {
    if (tempMin == null || tempMax == null) return '';
    if (tempMin == tempMax) return '${tempMin!.round()}°';
    return '${tempMin!.round()}°~${tempMax!.round()}°';
  }

  /// 聚合天气的展示文本，如 '海淀区  ☁️ 18°~25°'；无数据返回 ''。
  String get display {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    if (weatherIcon != null) {
      final emoji = DiaryEntry.weatherEmoji(weatherIcon!) ?? weatherText ?? '';
      if (emoji.isNotEmpty) parts.add(emoji);
    }
    if (tempDisplay.isNotEmpty) parts.add(tempDisplay);
    return parts.join('  ');
  }
}

/// 超长降级阈值（拼接全文超过此字数则退回各篇 summary 聚合）。
const int kDaySummaryDegradeThreshold = 25000;

/// 各篇录音供全文拼接的片段：创建时刻 + 该篇 ASR 全文。
typedef DayFullTextSegment = ({DateTime createdAt, String text});

/// 把一天各篇 ASR 全文按时间顺序拼接，篇间插入分隔标记。
/// 标记格式：`### 第 N 段 · HH:mm`（HH:mm 取该篇 createdAt 时刻）。
String buildDayFullText(List<DayFullTextSegment> segments) {
  final buf = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final hh = s.createdAt.hour.toString().padLeft(2, '0');
    final mm = s.createdAt.minute.toString().padLeft(2, '0');
    buf.writeln('### 第 ${i + 1} 段 · $hh:$mm');
    buf.writeln(s.text.trim());
    buf.writeln();
  }
  return buf.toString().trimRight();
}

/// 拼接全文是否超过降级阈值。
bool shouldDegrade(String fullText) =>
    fullText.length > kDaySummaryDegradeThreshold;

/// 降级模式下各篇供拼接的片段：创建时刻 + 标题 + summary。
typedef DaySummarySegment = ({
  DateTime createdAt,
  String title,
  String summary,
});

/// 降级模式：拼接各篇 LLM summary（而非全文）。
String buildDaySummariesText(List<DaySummarySegment> segments) {
  final buf = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final hh = s.createdAt.hour.toString().padLeft(2, '0');
    final mm = s.createdAt.minute.toString().padLeft(2, '0');
    buf.writeln('### 第 ${i + 1} 段 · $hh:$mm（${s.title}）');
    buf.writeln(s.summary.trim());
    buf.writeln();
  }
  return buf.toString().trimRight();
}

/// 取频次最高的 key（众数）；空 map 返回 null；平局取先出现的。
String? _modeKey(Map<String, int> counts) {
  if (counts.isEmpty) return null;
  var bestKey = counts.keys.first;
  var bestCount = counts[bestKey]!;
  counts.forEach((k, v) {
    if (v > bestCount) {
      bestKey = k;
      bestCount = v;
    }
  });
  return bestKey;
}

/// 聚合一天各篇录音的天气：地点众数 + 天气众数（按 weatherIcon 统计）+ 温度 min~max。
/// 详情页现算，不入库；全无数据时返回 isEmpty 的对象。
DayWeatherSummary aggregateDayWeather(List<DiaryEntry> entries) {
  final locCounts = <String, int>{};
  final iconCounts = <String, int>{};
  final iconToText = <String, String>{};
  final temps = <num>[];

  for (final e in entries) {
    final loc = e.locationName;
    if (loc != null && loc.isNotEmpty) {
      locCounts[loc] = (locCounts[loc] ?? 0) + 1;
    }
    final icon = e.weatherIcon;
    if (icon != null && icon.isNotEmpty) {
      iconCounts[icon] = (iconCounts[icon] ?? 0) + 1;
      if (!iconToText.containsKey(icon) &&
          e.weatherText != null &&
          e.weatherText!.isNotEmpty) {
        iconToText[icon] = e.weatherText!;
      }
    }
    final temp = e.temperature;
    if (temp != null && temp.isNotEmpty) {
      final n = num.tryParse(temp);
      if (n != null) temps.add(n);
    }
  }

  final iconMode = _modeKey(iconCounts);

  num? tempMin;
  num? tempMax;
  if (temps.isNotEmpty) {
    temps.sort();
    tempMin = temps.first;
    tempMax = temps.last;
  }

  return DayWeatherSummary(
    locationName: _modeKey(locCounts),
    weatherIcon: iconMode,
    weatherText: iconMode == null ? null : iconToText[iconMode],
    tempMin: tempMin,
    tempMax: tempMax,
  );
}

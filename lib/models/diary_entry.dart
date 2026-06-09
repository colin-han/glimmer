import 'processing_stage.dart';

enum EntryStatus { processing, completed, failed }

class DiaryEntry {
  final String id;
  final String title;
  final String folderPath;
  final int durationSeconds;
  final DateTime createdAt;
  final String? tosKey;
  final String audioFormat;
  final DateTime? uploadedAt;
  final String? weatherIcon;
  final String? weatherText;
  final String? temperature;
  final String? locationName;
  final double? locationLat;
  final double? locationLon;
  final EntryStatus status;
  final ProcessingStage processingStage;
  final String? asrTaskId;

  const DiaryEntry({
    required this.id,
    required this.title,
    required this.folderPath,
    required this.durationSeconds,
    required this.createdAt,
    this.tosKey,
    this.audioFormat = 'wav',
    this.uploadedAt,
    this.weatherIcon,
    this.weatherText,
    this.temperature,
    this.locationName,
    this.locationLat,
    this.locationLon,
    this.status = EntryStatus.completed,
    this.processingStage = ProcessingStage.uploading,
    this.asrTaskId,
  });

  String get displayTitle =>
      title.isNotEmpty ? title : '未命名日记';

  String get formattedDate {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get durationDisplay {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 天气摘要文本，如 "海淀区  ☁️ 24°"，无天气时返回空字符串
  String get weatherDisplay {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    if (weatherIcon != null) {
      final emoji = weatherEmoji(weatherIcon!) ?? weatherText ?? '';
      if (emoji.isNotEmpty) parts.add(emoji);
    }
    if (temperature != null) parts.add('$temperature°');
    return parts.join('  ');
  }

  /// 和风天气图标代码 → emoji 映射
  static String? weatherEmoji(String iconCode) => _weatherEmojiMap[iconCode];

  static const _weatherEmojiMap = {
    '100': '☀️',
    '101': '🌤️',
    '102': '⛅',
    '103': '⛅',
    '104': '☁️',
    '150': '☀️',
    '151': '🌤️',
    '300': '🌧️',
    '301': '⛈️',
    '302': '⛈️',
    '303': '⛈️',
    '304': '⛈️',
    '305': '🌧️',
    '306': '🌧️',
    '307': '🌧️',
    '308': '🌧️',
    '309': '🌧️',
    '310': '🌧️',
    '311': '🌧️',
    '312': '🌧️',
    '313': '🌧️',
    '314': '🌧️',
    '315': '🌧️',
    '399': '🌧️',
    '400': '🌨️',
    '401': '🌨️',
    '402': '🌨️',
    '403': '🌨️',
    '404': '🌨️',
    '405': '🌨️',
    '406': '🌨️',
    '407': '🌨️',
    '408': '🌨️',
    '409': '🌨️',
    '499': '🌨️',
    '500': '🌫️',
    '501': '🌫️',
    '502': '🌫️',
    '503': '🌫️',
    '504': '🌫️',
    '507': '🌫️',
    '508': '🌫️',
    '509': '🌫️',
    '510': '🌫️',
    '511': '🌫️',
    '512': '🌫️',
    '513': '🌫️',
    '514': '🌫️',
    '515': '🌫️',
    '900': '🌡️',
    '901': '🌡️',
    '999': '🌡️',
  };
}

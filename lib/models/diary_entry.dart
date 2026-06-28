import 'processing_stage.dart';
import 'weather_condition.dart';

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
  final WeatherCondition? weatherCondition;
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
    this.weatherCondition,
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

  DiaryEntry copyWith({
    String? title,
    EntryStatus? status,
    ProcessingStage? processingStage,
    String? tosKey,
    String? asrTaskId,
  }) {
    return DiaryEntry(
      id: id,
      title: title ?? this.title,
      folderPath: folderPath,
      durationSeconds: durationSeconds,
      createdAt: createdAt,
      tosKey: tosKey ?? this.tosKey,
      audioFormat: audioFormat,
      uploadedAt: uploadedAt,
      weatherCondition: weatherCondition,
      weatherIcon: weatherIcon,
      weatherText: weatherText,
      temperature: temperature,
      locationName: locationName,
      locationLat: locationLat,
      locationLon: locationLon,
      status: status ?? this.status,
      processingStage: processingStage ?? this.processingStage,
      asrTaskId: asrTaskId ?? this.asrTaskId,
    );
  }

  String get displayTitle => title.isNotEmpty ? title : '未命名日记';

  String get formattedDate {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get durationDisplay {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 天气摘要文本，如 "海淀区  🌦️ 阵雨  24°"，无天气时返回空字符串
  String get weatherDisplay {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    final c = effectiveCondition;
    if (c != null && c.displayPart.isNotEmpty) parts.add(c.displayPart);
    if (temperature != null) parts.add('$temperature°');
    return parts.join('  ');
  }

  /// 有效天气：优先 weatherCondition，为空则从历史 weather_icon 兜底。
  WeatherCondition? get effectiveCondition =>
      weatherCondition ??
      (weatherIcon != null
          ? WeatherCondition.fromQweatherCode(weatherIcon!)
          : null);
}

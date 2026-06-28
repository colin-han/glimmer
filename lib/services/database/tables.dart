import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/weather_condition.dart';

/// drift TypeConverter：`Map<String, dynamic>` ↔ JSON text（用于 ProcessingTasks.meta）。
class MapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const MapConverter();
  @override
  Map<String, dynamic> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}

/// 可空版 WeatherCondition TypeConverter（用于 nullable 列）。
class NullableWeatherConditionConverter
    extends TypeConverter<WeatherCondition?, String?> {
  const NullableWeatherConditionConverter();
  @override
  WeatherCondition? fromSql(String? fromDb) =>
      fromDb != null ? WeatherCondition.values.byName(fromDb) : null;
  @override
  String? toSql(WeatherCondition? value) => value?.name;
}

class DiaryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get folderPath => text()();
  IntColumn get durationSeconds => integer()();
  IntColumn get createdAt => integer()();
  TextColumn get tosKey => text().nullable()();
  TextColumn get audioFormat => text().withDefault(const Constant('wav'))();
  IntColumn get uploadedAt => integer().nullable()();
  TextColumn get weatherCondition =>
      text().map(const NullableWeatherConditionConverter()).nullable()();
  TextColumn get weatherIcon => text().nullable()();
  TextColumn get weatherText => text().nullable()();
  TextColumn get temperature => text().nullable()();
  TextColumn get locationName => text().nullable()();
  RealColumn get locationLat => real().nullable()();
  RealColumn get locationLon => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get processingStage =>
      text().withDefault(const Constant('uploading'))();
  TextColumn get asrTaskId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get matchPrompt => text().withDefault(const Constant(''))();
  TextColumn get color => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {name},
  ];
}

class DiaryTagRelations extends Table {
  TextColumn get diaryId => text().references(DiaryEntries, #id)();
  TextColumn get tagId => text().references(Tags, #id)();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {diaryId, tagId};
}

class ApiLogs extends Table {
  TextColumn get id => text()();
  TextColumn get diaryId => text()();
  TextColumn get apiType => text()();
  TextColumn get step => text()();
  TextColumn get status => text()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get responseSummary => text().nullable()();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  IntColumn get totalTokens => integer().nullable()();
  IntColumn get cachedTokens => integer().nullable()();
  IntColumn get reasoningTokens => integer().nullable()();
  IntColumn get audioDurationSeconds => integer().nullable()();
  IntColumn get ttsCharacterCount => integer().nullable()();
  RealColumn get estimatedCost => real().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 每日总结元数据表。每行对应一天的「日」总结实体。
/// 行类名用 DataClassName 显式指定为 DailySummaryRow，避免与 model 层的
/// DailySummary（lib/models/daily_summary.dart）同名冲突。
@DataClassName('DailySummaryRow')
class DailySummaries extends Table {
  /// 日期 'yyyy-MM-dd'，主键。
  TextColumn get date => text()();

  TextColumn get title => text()();

  /// processing / completed / failed（与 DiaryEntries.status 语义一致）。
  TextColumn get status => text().withDefault(const Constant('processing'))();

  /// 参与总结的录音 id 列表，JSON 数组字符串，如 '["uuid1","uuid2"]'。
  TextColumn get sourceEntryIds => text().withDefault(const Constant('[]'))();

  IntColumn get entryCount => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}

/// 处理任务队列表（消息队列语义）。每行一个处理任务，completed/failed 行保留作历史。
/// 行类名用 DataClassName 显式指定为 ProcessingTaskRow，避免与 model 层
/// ProcessingTask（lib/models/processing_task.dart）同名冲突。
@DataClassName('ProcessingTaskRow')
class ProcessingTasks extends Table {
  /// 任务 id（UUID）。
  TextColumn get id => text()();

  /// 'diary' | 'daily_summary'（可扩展）。
  TextColumn get taskType => text()();

  /// diary 的 entryId，或 daily_summary 的日期 'yyyy-MM-dd'。
  TextColumn get refId => text()();

  /// 'queued' | 'running' | 'completed' | 'failed'。
  TextColumn get status => text().withDefault(const Constant('queued'))();

  /// 通用调度字段，FGS 续跑用。diary: uploading/asr/llm/tagging；daily_summary 可 null。
  TextColumn get stage => text().nullable()();

  /// task 进入 failed 时的原因（异常 toString）。只在 failed 时写。
  TextColumn get failedMessage => text().nullable()();

  /// 任务专有数据（JSON）。diary 的 {"asrTaskId":"..."}；daily_summary 的 {}。
  TextColumn get meta =>
      text().map(const MapConverter()).withDefault(const Constant('{}'))();

  /// 入队时间（毫秒）。
  IntColumn get queuedAt => integer()();

  /// FGS 开始处理时间。
  IntColumn get startedAt => integer().nullable()();

  /// 完成/失败时间。
  IntColumn get finishedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

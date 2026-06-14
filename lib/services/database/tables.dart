import 'package:drift/drift.dart';

class DiaryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get folderPath => text()();
  IntColumn get durationSeconds => integer()();
  IntColumn get createdAt => integer()();
  TextColumn get tosKey => text().nullable()();
  TextColumn get audioFormat => text().withDefault(const Constant('wav'))();
  IntColumn get uploadedAt => integer().nullable()();
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

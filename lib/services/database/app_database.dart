import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

import '../../models/weather_condition.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    DiaryEntries,
    Tags,
    DiaryTagRelations,
    ApiLogs,
    DailySummaries,
    ProcessingTasks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal() : super(_openConnection());
  static AppDatabase? _instance;

  /// 单例工厂。
  ///
  /// AppDatabase 内部用 NativeDatabase.createInBackground，每个实例都会起一个独立
  /// 后台 isolate 连接 voice_diary.db。代码里 DiaryStorageService / ApiLogService 以及
  /// 各页面都各自 `new`，会导致同一 isolate 内并存多个连接（资源浪费 + 并发写 SQLITE_BUSY）。
  /// 全 app 共享同一实例后，每个 isolate 只剩一个连接。
  ///
  /// 注：Dart static 是「每 isolate 一份」，主 isolate 与 FGS isolate 各自持有一个实例——
  /// 这正是所需（drift 连接不能跨 isolate），符合预期。
  factory AppDatabase() => _instance ??= AppDatabase._internal();

  /// 测试用：注入内存执行器，绕过单例和文件连接。
  /// 生产代码请用 `AppDatabase()` 工厂。
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // WAL + busy_timeout：main isolate 与 FGS isolate 各持有一个 DB 连接，
      // 并发读写（store 读 task / FGS 写 task）时避免 SQLITE_BUSY (code 5)。
      // WAL 持久（数据库级，首次设置后保持）；busy_timeout 连接级（每次打开设，写冲突时等待而非立即失败）。
      await customStatement('PRAGMA journal_mode=WAL');
      await customStatement('PRAGMA busy_timeout=5000');
    },
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // 幂等迁移：每个 step 先检测目标是否已存在，已存在则跳过。
      // 不再用 `try/catch(_){}` 吞掉异常——真正的失败（磁盘满/IO 错误等）必须抛出，
      // 否则 schemaVersion 会推进到残缺状态，下次启动不再重试，DB 永久缺列。
      // 真正失败时 drift 不会更新 user_version，下次启动从同一 from 版本重试（幂等故安全）。
      if (from < 2) {
        if (!await _tableExists('tags')) await m.createTable(tags);
        if (!await _tableExists('diary_tag_relations')) {
          await m.createTable(diaryTagRelations);
        }
      }
      if (from < 3) {
        if (!await _columnExists('diary_entries', 'tos_key')) {
          await m.addColumn(diaryEntries, diaryEntries.tosKey);
        }
        if (!await _columnExists('diary_entries', 'audio_format')) {
          await m.addColumn(diaryEntries, diaryEntries.audioFormat);
        }
        if (!await _columnExists('diary_entries', 'uploaded_at')) {
          await m.addColumn(diaryEntries, diaryEntries.uploadedAt);
        }
      }
      if (from < 4) {
        if (!await _columnExists('diary_entries', 'weather_icon')) {
          await m.addColumn(diaryEntries, diaryEntries.weatherIcon);
        }
        if (!await _columnExists('diary_entries', 'weather_text')) {
          await m.addColumn(diaryEntries, diaryEntries.weatherText);
        }
        if (!await _columnExists('diary_entries', 'temperature')) {
          await m.addColumn(diaryEntries, diaryEntries.temperature);
        }
        if (!await _columnExists('diary_entries', 'location_name')) {
          await m.addColumn(diaryEntries, diaryEntries.locationName);
        }
        if (!await _columnExists('diary_entries', 'location_lat')) {
          await m.addColumn(diaryEntries, diaryEntries.locationLat);
        }
        if (!await _columnExists('diary_entries', 'location_lon')) {
          await m.addColumn(diaryEntries, diaryEntries.locationLon);
        }
      }
      if (from < 5) {
        if (!await _columnExists('diary_entries', 'status')) {
          await m.addColumn(diaryEntries, diaryEntries.status);
        }
      }
      if (from < 6) {
        if (!await _columnExists('diary_entries', 'processing_stage')) {
          await m.addColumn(diaryEntries, diaryEntries.processingStage);
        }
        if (!await _columnExists('diary_entries', 'asr_task_id')) {
          await m.addColumn(diaryEntries, diaryEntries.asrTaskId);
        }
      }
      if (from < 7) {
        if (!await _tableExists('api_logs')) await m.createTable(apiLogs);
      }
      if (from < 8) {
        if (!await _tableExists('daily_summaries')) {
          await m.createTable(dailySummaries);
        }
      }
      if (from < 9) {
        if (!await _tableExists('processing_tasks')) {
          await m.createTable(processingTasks);
          // 建表后搬迁旧 status 数据（processing/failed → task 行；completed 不补）
          await _migrateStatusToTasks();
        }
      }
      if (from < 10) {
        if (!await _columnExists('diary_entries', 'weather_condition')) {
          await m.addColumn(diaryEntries, diaryEntries.weatherCondition);
        }
        await _migrateWeatherCondition();
      }
    },
  );

  /// 表是否存在（用于幂等迁移）。
  Future<bool> _tableExists(String tableName) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable.withString(tableName)],
    ).get();
    return rows.isNotEmpty;
  }

  /// 指定列是否存在（用于幂等迁移）。
  Future<bool> _columnExists(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

  /// 把旧 DiaryEntries/DailySummaries 的 status 搬到 processing_tasks。
  /// processing/failed → 建 task 行（failed 保留失败历史）；completed 不补。
  /// 幂等：仅在 processing_tasks 表首次创建时（from<9 块内）执行一次。
  Future<void> _migrateStatusToTasks() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // diary：status in (processing, failed)
    final diaryRows = await customSelect(
      "SELECT id, status, processing_stage, asr_task_id FROM diary_entries "
      "WHERE status IN ('processing', 'failed')",
    ).get();
    for (final r in diaryRows) {
      final id = r.read<String>('id');
      final status = r.read<String>('status');
      final stage = r.read<String?>('processing_stage');
      final asrTaskId = r.read<String?>('asr_task_id');
      await into(processingTasks).insert(
        ProcessingTasksCompanion.insert(
          id: 'migrated-diary-$id',
          taskType: 'diary',
          refId: id,
          status: Value(status == 'failed' ? 'failed' : 'running'),
          stage: Value(stage),
          meta: Value(
            asrTaskId != null
                ? <String, dynamic>{'asrTaskId': asrTaskId}
                : <String, dynamic>{},
          ),
          queuedAt: now,
        ),
      );
    }
    // daily_summary：status in (processing, failed)
    final summaryRows = await customSelect(
      "SELECT date, status FROM daily_summaries "
      "WHERE status IN ('processing', 'failed')",
    ).get();
    for (final r in summaryRows) {
      final date = r.read<String>('date');
      final status = r.read<String>('status');
      await into(processingTasks).insert(
        ProcessingTasksCompanion.insert(
          id: 'migrated-summary-$date',
          taskType: 'daily_summary',
          refId: date,
          status: Value(status == 'failed' ? 'failed' : 'running'),
          queuedAt: now,
        ),
      );
    }
  }

  /// 回填 weather_condition：把历史 weather_icon（和风代码）映射到枚举。
  /// 幂等：仅处理 weather_condition IS NULL 的行。
  Future<void> _migrateWeatherCondition() async {
    final rows = await customSelect(
      "SELECT id, weather_icon FROM diary_entries "
      "WHERE weather_condition IS NULL AND weather_icon IS NOT NULL",
    ).get();
    for (final r in rows) {
      final icon = r.read<String>('weather_icon');
      final condition = WeatherCondition.fromQweatherCode(icon);
      await customStatement(
        "UPDATE diary_entries SET weather_condition = ? WHERE id = ?",
        [condition.name, r.read<String>('id')],
      );
    }
  }

  // --- DiaryEntries ---

  Future<List<DiaryEntry>> getAllEntries() {
    return (select(
      diaryEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  Future<DiaryEntry> getEntryById(String id) {
    return (select(diaryEntries)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> insertEntry(DiaryEntriesCompanion entry) {
    return into(diaryEntries).insert(entry);
  }

  Future<void> updateEntry(DiaryEntriesCompanion entry) {
    return (update(
      diaryEntries,
    )..where((t) => t.id.equals(entry.id.value))).write(entry);
  }

  Future<void> deleteEntry(String id) {
    return (delete(diaryEntries)..where((t) => t.id.equals(id))).go();
  }

  /// 查询 status=processing 的日记（已废弃，db 层）。
  @Deprecated(
    '已废弃：改用 processing_tasks 表（DiaryStorageService.getPendingProcessingTasks）。业务表 status 不再维护。',
  )
  Future<List<DiaryEntry>> getPendingEntries() {
    return (select(diaryEntries)
          ..where((t) => t.status.equals('processing'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  // --- Tags ---

  Future<List<Tag>> getAllTags() {
    return (select(
      tags,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
  }

  Future<Tag> getTagById(String id) {
    return (select(tags)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> insertTag(TagsCompanion tag) {
    return into(tags).insert(tag);
  }

  Future<void> updateTag(TagsCompanion tag) {
    return (update(tags)..where((t) => t.id.equals(tag.id.value))).write(tag);
  }

  Future<void> deleteTag(String id) {
    return (delete(tags)..where((t) => t.id.equals(id))).go();
  }

  // --- DiaryTagRelations ---

  Future<void> insertDiaryTag(DiaryTagRelationsCompanion relation) {
    return into(
      diaryTagRelations,
    ).insert(relation, mode: InsertMode.insertOrIgnore);
  }

  Future<void> deleteDiaryTag(String diaryId, String tagId) {
    return (delete(
      diaryTagRelations,
    )..where((t) => t.diaryId.equals(diaryId) & t.tagId.equals(tagId))).go();
  }

  Future<void> deleteDiaryTagsByTag(String tagId) {
    return (delete(
      diaryTagRelations,
    )..where((t) => t.tagId.equals(tagId))).go();
  }

  Future<void> deleteDiaryTagsByDiary(String diaryId) {
    return (delete(
      diaryTagRelations,
    )..where((t) => t.diaryId.equals(diaryId))).go();
  }

  Future<List<DiaryTagRelation>> getTagsForDiary(String diaryId) {
    return (select(
      diaryTagRelations,
    )..where((t) => t.diaryId.equals(diaryId))).get();
  }

  Future<List<DiaryTagRelation>> getDiariesForTag(String tagId) {
    return (select(
      diaryTagRelations,
    )..where((t) => t.tagId.equals(tagId))).get();
  }

  Future<int> getDiaryCountForTag(String tagId) {
    return (select(
      diaryTagRelations,
    )..where((t) => t.tagId.equals(tagId))).get().then((rows) => rows.length);
  }

  /// 查询未完成的日记数量（processing + failed）（已废弃，db 层）。
  @Deprecated(
    '已废弃：改用 processing_tasks 表（processingTaskStore.activeCount）。业务表 status 不再维护。',
  )
  Future<int> getProcessingEntryCount() {
    return (select(diaryEntries)..where(
          (t) => t.status.equals('processing') | t.status.equals('failed'),
        ))
        .get()
        .then((rows) => rows.length);
  }

  // --- ApiLogs ---

  Future<void> insertApiLog(ApiLogsCompanion log) {
    return into(apiLogs).insert(log);
  }

  Future<List<ApiLog>> getLogsForDiary(String diaryId) {
    return (select(apiLogs)
          ..where((t) => t.diaryId.equals(diaryId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<ApiLog>> getRecentLogs({int limit = 50, int offset = 0}) {
    return (select(apiLogs)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  // --- ProcessingTasks ---

  Future<void> insertProcessingTask(ProcessingTasksCompanion task) {
    return into(processingTasks).insert(task);
  }

  // --- DailySummaries ---

  Future<DailySummaryRow?> getDailySummaryByDate(String date) {
    return (select(
      dailySummaries,
    )..where((t) => t.date.equals(date))).getSingleOrNull();
  }

  /// 查询 status=processing 的每日总结（已废弃，db 层）。
  @Deprecated(
    '已废弃：改用 processing_tasks 表（taskType=daily_summary）。业务表 status 不再维护。',
  )
  Future<List<DailySummaryRow>> getPendingDailySummaries() {
    return (select(dailySummaries)
          ..where((t) => t.status.equals('processing'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<DailySummaryRow>> getAllDailySummaries() {
    return (select(
      dailySummaries,
    )..orderBy([(t) => OrderingTerm.desc(t.date)])).get();
  }

  Future<void> upsertDailySummary(DailySummariesCompanion row) {
    return into(dailySummaries).insert(row, mode: InsertMode.insertOrReplace);
  }

  Future<void> deleteDailySummaryRow(String date) {
    return (delete(dailySummaries)..where((t) => t.date.equals(date))).go();
  }

  /// 查询某天（'yyyy-MM-dd'）的所有日记条目，按 createdAt 升序。
  /// 用半开区间 [start, end) 避免边界包含次日 0 点。
  Future<List<DiaryEntry>> getEntriesByDate(String date) {
    final day = DateTime.parse(date);
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = DateTime(
      day.year,
      day.month,
      day.day,
    ).add(const Duration(days: 1)).millisecondsSinceEpoch;
    return (select(diaryEntries)
          ..where(
            (t) =>
                t.createdAt.isBiggerOrEqualValue(start) &
                t.createdAt.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'voice_diary.db'));
    return NativeDatabase.createInBackground(file);
  });
}

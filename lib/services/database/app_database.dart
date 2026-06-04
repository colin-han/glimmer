import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [DiaryEntries, Tags, DiaryTagRelations])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // 每个 step 容错：列已存在时忽略，避免设备上 DB 状态不一致导致崩溃
          if (from < 2) {
            try { await m.createTable(tags); } catch (_) {}
            try { await m.createTable(diaryTagRelations); } catch (_) {}
          }
          if (from < 3) {
            try { await m.addColumn(diaryEntries, diaryEntries.tosKey); } catch (_) {}
            try { await m.addColumn(diaryEntries, diaryEntries.audioFormat); } catch (_) {}
            try { await m.addColumn(diaryEntries, diaryEntries.uploadedAt); } catch (_) {}
          }
          if (from < 4) {
            try { await m.addColumn(diaryEntries, diaryEntries.weatherIcon); } catch (_) {}
            try { await m.addColumn(diaryEntries, diaryEntries.weatherText); } catch (_) {}
            try { await m.addColumn(diaryEntries, diaryEntries.temperature); } catch (_) {}
            try { await m.addColumn(diaryEntries, diaryEntries.locationName); } catch (_) {}
            try { await m.addColumn(diaryEntries, diaryEntries.locationLat); } catch (_) {}
            try { await m.addColumn(diaryEntries, diaryEntries.locationLon); } catch (_) {}
          }
          if (from < 5) {
            try { await m.addColumn(diaryEntries, diaryEntries.status); } catch (_) {}
          }
        },
      );

  // --- DiaryEntries ---

  Future<List<DiaryEntry>> getAllEntries() {
    return (select(diaryEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<DiaryEntry> getEntryById(String id) {
    return (select(diaryEntries)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> insertEntry(DiaryEntriesCompanion entry) {
    return into(diaryEntries).insert(entry);
  }

  Future<void> updateEntry(DiaryEntriesCompanion entry) {
    return (update(diaryEntries)..where((t) => t.id.equals(entry.id.value)))
        .write(entry);
  }

  Future<void> deleteEntry(String id) {
    return (delete(diaryEntries)..where((t) => t.id.equals(id))).go();
  }

  // --- Tags ---

  Future<List<Tag>> getAllTags() {
    return (select(tags)..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
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
    return into(diaryTagRelations)
        .insert(relation, mode: InsertMode.insertOrIgnore);
  }

  Future<void> deleteDiaryTag(String diaryId, String tagId) {
    return (delete(diaryTagRelations)
          ..where((t) => t.diaryId.equals(diaryId) & t.tagId.equals(tagId)))
        .go();
  }

  Future<void> deleteDiaryTagsByTag(String tagId) {
    return (delete(diaryTagRelations)..where((t) => t.tagId.equals(tagId)))
        .go();
  }

  Future<void> deleteDiaryTagsByDiary(String diaryId) {
    return (delete(diaryTagRelations)..where((t) => t.diaryId.equals(diaryId)))
        .go();
  }

  Future<List<DiaryTagRelation>> getTagsForDiary(String diaryId) {
    return (select(diaryTagRelations)..where((t) => t.diaryId.equals(diaryId)))
        .get();
  }

  Future<List<DiaryTagRelation>> getDiariesForTag(String tagId) {
    return (select(diaryTagRelations)..where((t) => t.tagId.equals(tagId)))
        .get();
  }

  Future<int> getDiaryCountForTag(String tagId) {
    return (select(diaryTagRelations)..where((t) => t.tagId.equals(tagId)))
        .get()
        .then((rows) => rows.length);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'voice_diary.db'));
    return NativeDatabase.createInBackground(file);
  });
}

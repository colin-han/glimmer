import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => await db.close());

  group('DailySummaries CRUD', () {
    test('upsertDailySummary 插入并可按 date 读取', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: '一天的总结',
          status: const Value('completed'),
          sourceEntryIds: const Value('["u1","u2"]'),
          entryCount: const Value(2),
          createdAt: 1,
        ),
      );
      final got = await db.getDailySummaryByDate('2026-06-13');
      expect(got, isNotNull);
      expect(got!.title, '一天的总结');
      expect(got.status, 'completed');
      expect(got.entryCount, 2);
    });

    test('相同 date upsert 覆盖（insertOrReplace）', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: '旧',
          createdAt: 1,
        ),
      );
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: '新',
          createdAt: 2,
        ),
      );
      final got = await db.getDailySummaryByDate('2026-06-13');
      expect(got!.title, '新');
      expect(got.createdAt, 2);
    });

    test('getPendingDailySummaries 只返回 processing', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: 'a',
          createdAt: 1,
          status: const Value('processing'),
        ),
      );
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-12',
          title: 'b',
          createdAt: 2,
          status: const Value('completed'),
        ),
      );
      final pending = await db.getPendingDailySummaries();
      expect(pending, hasLength(1));
      expect(pending.first.date, '2026-06-13');
    });

    test('deleteDailySummaryRow 删除', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: 'a',
          createdAt: 1,
        ),
      );
      await db.deleteDailySummaryRow('2026-06-13');
      expect(await db.getDailySummaryByDate('2026-06-13'), isNull);
    });
  });

  group('getEntriesByDate', () {
    test('按当天范围过滤并按 createdAt 升序', () async {
      const day = '2026-06-13';
      final d = DateTime.parse(day);
      await db.insertEntry(
        DiaryEntriesCompanion.insert(
          id: 'e1',
          title: 't1',
          folderPath: '/p1',
          durationSeconds: 0,
          createdAt: DateTime(
            d.year,
            d.month,
            d.day,
            20,
          ).millisecondsSinceEpoch,
        ),
      );
      await db.insertEntry(
        DiaryEntriesCompanion.insert(
          id: 'e2',
          title: 't2',
          folderPath: '/p2',
          durationSeconds: 0,
          createdAt: DateTime(d.year, d.month, d.day, 9).millisecondsSinceEpoch,
        ),
      );
      await db.insertEntry(
        DiaryEntriesCompanion.insert(
          id: 'e3',
          title: 't3',
          folderPath: '/p3',
          durationSeconds: 0,
          createdAt: DateTime(
            d.year,
            d.month,
            d.day - 1,
            12,
          ).millisecondsSinceEpoch,
        ),
      );
      final rows = await db.getEntriesByDate(day);
      expect(rows.map((r) => r.id), ['e2', 'e1']); // 9点在前
      expect(rows, hasLength(2));
    });

    test('当天无记录返回空列表', () async {
      expect(await db.getEntriesByDate('2020-01-01'), isEmpty);
    });
  });
}

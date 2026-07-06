import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/processing_stage.dart';
import 'package:voice_diary/services/database/app_database.dart'
    hide DiaryEntry, Tag, DiaryTagRelation;
import 'package:voice_diary/services/diary_storage_service.dart';

void main() {
  late AppDatabase db;
  late DiaryStorageService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = DiaryStorageService.forTesting(db);
  });
  tearDown(() async => await db.close());

  Future<void> createEntry({
    required String id,
    String? tosKey,
    String? asrTaskId,
  }) async {
    await service.createEntry(
      DiaryEntry(
        id: id,
        title: '原标题',
        folderPath: '/tmp/$id',
        durationSeconds: 60,
        createdAt: DateTime(2026, 6, 14),
        tosKey: tosKey,
        audioFormat: 'wav',
        status: EntryStatus.completed,
        processingStage: ProcessingStage.completed,
        asrTaskId: asrTaskId,
      ),
    );
  }

  test('updateLocationName 只改 locationName 字段', () async {
    await service.createEntry(
      DiaryEntry(
        id: 'x',
        title: 't',
        folderPath: '/x',
        durationSeconds: 1,
        createdAt: DateTime(2026, 6, 28),
        locationName: '雁塔区',
        locationLat: 34.0,
        locationLon: 108.0,
      ),
    );
    await service.updateLocationName('x', '家');
    final entries = await service.getAllEntries();
    final e = entries.firstWhere((e) => e.id == 'x');
    expect(e.locationName, '家');
    expect(e.locationLat, 34.0); // 其他字段不变
    expect(e.title, 't');
  });

  test('resetEntryForReanalysis 有 tosKey 时重置为 asr 阶段', () async {
    await createEntry(id: 'e1', tosKey: 'tos-key-1', asrTaskId: 'old-task');

    await service.resetEntryForReanalysis('e1');

    final reset = await service.getEntryById('e1');
    expect(reset.status, EntryStatus.processing);
    expect(reset.processingStage, ProcessingStage.asr);
    expect(reset.asrTaskId, isNull);
    expect(reset.tosKey, 'tos-key-1'); // 保留，不重新上传
  });

  test('resetEntryForReanalysis 无 tosKey 时落到 uploading 阶段', () async {
    await createEntry(id: 'e2'); // tosKey=null

    await service.resetEntryForReanalysis('e2');

    final reset = await service.getEntryById('e2');
    expect(reset.status, EntryStatus.processing);
    expect(reset.processingStage, ProcessingStage.uploading);
    expect(reset.asrTaskId, isNull);
  });

  test('resetEntryForReanalysis 不改 title 等非处理字段', () async {
    await createEntry(id: 'e3', tosKey: 'tos-key-3');

    await service.resetEntryForReanalysis('e3');

    final reset = await service.getEntryById('e3');
    expect(reset.title, '原标题');
    expect(reset.folderPath, '/tmp/e3');
    expect(reset.durationSeconds, 60);
  });

  group('getRecordingDayStats', () {
    Future<void> entryAt(String id, DateTime createdAt) async {
      await service.createEntry(
        DiaryEntry(
          id: id,
          title: 't',
          folderPath: '/tmp/$id',
          durationSeconds: 60,
          createdAt: createdAt,
        ),
      );
    }

    test('空库 → (0, 0)', () async {
      expect(await service.getRecordingDayStats(now: DateTime(2026, 7, 6)), (
        currentStreak: 0,
        totalDays: 0,
      ));
    });

    test('今天 + 昨天 → (2, 2)；以注入 now 为准', () async {
      await entryAt('a', DateTime(2026, 7, 6, 9));
      await entryAt('b', DateTime(2026, 7, 5, 21));
      expect(
        await service.getRecordingDayStats(now: DateTime(2026, 7, 6, 12)),
        (currentStreak: 2, totalDays: 2),
      );
    });

    test('同一天多条 → 去重 (1, 1)', () async {
      await entryAt('a', DateTime(2026, 7, 6, 8));
      await entryAt('b', DateTime(2026, 7, 6, 20));
      expect(await service.getRecordingDayStats(now: DateTime(2026, 7, 6)), (
        currentStreak: 1,
        totalDays: 1,
      ));
    });

    test('不传 now 时使用 DateTime.now()（冒烟：返回 totalDays==已插入数）', () async {
      await entryAt('now1', DateTime.now());
      final r = await service.getRecordingDayStats();
      expect(r.totalDays, greaterThanOrEqualTo(1));
      expect(r.currentStreak, greaterThanOrEqualTo(1));
    });
  });
}

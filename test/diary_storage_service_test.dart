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
}

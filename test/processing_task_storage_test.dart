import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/processing_task.dart';
import 'package:voice_diary/services/database/app_database.dart';
import 'package:voice_diary/services/diary_storage_service.dart';

void main() {
  late AppDatabase db;
  late DiaryStorageService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = DiaryStorageService.forTesting(db);
  });
  tearDown(() async => await db.close());

  ProcessingTask sample({
    required String id,
    String refId = 'entry-1',
    TaskStatus status = TaskStatus.queued,
    String? stage = 'asr',
    Map<String, dynamic>? meta,
    DateTime? queuedAt,
  }) => ProcessingTask(
    id: id,
    taskType: TaskType.diary,
    refId: refId,
    status: status,
    stage: stage,
    meta: meta ?? const {},
    queuedAt: queuedAt ?? DateTime(2026, 6, 21),
  );

  group('insertProcessingTask + getLatestProcessingTask', () {
    test('插入后能按 ref_id 取到最新行', () async {
      await service.insertProcessingTask(sample(id: 't1', refId: 'e1'));
      final latest = await service.getLatestProcessingTask('e1');
      expect(latest, isNotNull);
      expect(latest!.id, 't1');
      expect(latest.status, TaskStatus.queued);
      expect(latest.stage, 'asr');
    });

    test('多条同 ref_id → 取 queued_at 最新', () async {
      await service.insertProcessingTask(
        sample(id: 't1', refId: 'e1', queuedAt: DateTime(2026, 6, 21, 10)),
      );
      await service.insertProcessingTask(
        sample(id: 't2', refId: 'e1', queuedAt: DateTime(2026, 6, 21, 14)),
      );
      final latest = await service.getLatestProcessingTask('e1');
      expect(latest!.id, 't2'); // t2 的 queued_at 更晚
    });

    test('meta JSON 读写正确', () async {
      await service.insertProcessingTask(
        sample(id: 't1', meta: {'asrTaskId': 'asr-xyz'}),
      );
      final latest = await service.getLatestProcessingTask('entry-1');
      expect(latest!.meta['asrTaskId'], 'asr-xyz');
    });
  });

  group('updateProcessingTaskStatus', () {
    test('更新 status + 写 finished_at（completed/failed）', () async {
      await service.insertProcessingTask(sample(id: 't1', refId: 'e1'));
      await service.updateProcessingTaskStatus(
        't1',
        TaskStatus.failed,
        failedMessage: 'ASR 超时',
      );
      final latest = await service.getLatestProcessingTask('e1');
      expect(latest!.status, TaskStatus.failed);
      expect(latest.failedMessage, 'ASR 超时');
      expect(latest.finishedAt, isNotNull);
    });

    test('非 failed 状态更新不传 failedMessage → 保留旧的失败原因', () async {
      await service.insertProcessingTask(sample(id: 't1', refId: 'e1'));
      // 先标记 failed + 失败原因
      await service.updateProcessingTaskStatus(
        't1',
        TaskStatus.failed,
        failedMessage: 'ASR 超时',
      );
      // 再更新到 running（重试），不传 failedMessage
      await service.updateProcessingTaskStatus('t1', TaskStatus.running);
      final latest = await service.getLatestProcessingTask('e1');
      expect(latest!.status, TaskStatus.running);
      expect(latest.failedMessage, 'ASR 超时'); // 保留，未被清空
    });
  });

  group('getPendingProcessingTasks', () {
    test('只返回 queued + running，按 queued_at 升序', () async {
      await service.insertProcessingTask(
        sample(id: 't1', refId: 'e1', status: TaskStatus.queued),
      );
      await service.insertProcessingTask(
        sample(id: 't2', refId: 'e2', status: TaskStatus.completed),
      );
      await service.insertProcessingTask(
        sample(id: 't3', refId: 'e3', status: TaskStatus.running),
      );
      final pending = await service.getPendingProcessingTasks();
      expect(pending.length, 2); // t1 + t3
      expect(pending.map((t) => t.id), containsAll(['t1', 't3']));
    });
  });
}

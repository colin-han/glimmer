import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/processing_task.dart';
import 'package:voice_diary/services/database/app_database.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/processing_task_store.dart';

void main() {
  late AppDatabase db;
  late DiaryStorageService storage;
  late ProcessingTaskStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = DiaryStorageService.forTesting(db);
    store = ProcessingTaskStore(storage: storage);
  });
  tearDown(() async {
    await db.close();
  });

  group('enqueueTask', () {
    test('入队后内存有该 ref，DB 有该行，ValueNotifier 通知', () async {
      var notifyCount = 0;
      store.activeRefIds.addListener(() => notifyCount++);

      await store.enqueueTask(
        taskType: TaskType.diary,
        refId: 'e1',
        stage: 'asr',
        meta: {'asrTaskId': 'x'},
      );

      expect(store.isProcessing('e1'), isTrue);
      expect(store.activeCount, 1);
      expect(store.activeRefIds.value, contains('e1'));
      expect(notifyCount, greaterThan(0)); // 通知触发了

      // DB 也有
      final dbTask = await storage.getLatestProcessingTask('e1');
      expect(dbTask, isNotNull);
      expect(dbTask!.status, TaskStatus.queued);
      expect(dbTask.meta['asrTaskId'], 'x');
    });

    test('同一 ref 再次入队 → 内存更新为最新行（方案 A：新建行）', () async {
      await store.enqueueTask(
        taskType: TaskType.diary,
        refId: 'e1',
        stage: 'asr',
      );
      await store.enqueueTask(
        taskType: TaskType.diary,
        refId: 'e1',
        stage: 'llm',
      );

      expect(store.activeCount, 1); // 同 ref，内存里还是一个
      final task = store.getTask('e1');
      expect(task!.stage, 'llm'); // 最新行的 stage
    });
  });

  group('启动加载', () {
    test('loadFromDb 把 DB active task 填进内存', () async {
      // 直接往 DB 插一个 active task（绕过 store）
      await storage.insertProcessingTask(
        ProcessingTask(
          id: 't1',
          taskType: TaskType.diary,
          refId: 'e1',
          status: TaskStatus.queued,
          stage: 'asr',
          queuedAt: DateTime(2026, 6, 21),
        ),
      );
      // completed 的不入内存
      await storage.insertProcessingTask(
        ProcessingTask(
          id: 't2',
          taskType: TaskType.diary,
          refId: 'e2',
          status: TaskStatus.completed,
          queuedAt: DateTime(2026, 6, 21),
        ),
      );

      await store.loadFromDb();

      expect(store.isProcessing('e1'), isTrue); // queued 入内存
      expect(store.isProcessing('e2'), isFalse); // completed 不入
      expect(store.activeCount, 1);
    });
  });

  group('查询', () {
    test('getTask 返回内存里的 active task', () async {
      await store.enqueueTask(
        taskType: TaskType.dailySummary,
        refId: '2026-06-21',
      );
      final task = store.getTask('2026-06-21');
      expect(task, isNotNull);
      expect(task!.taskType, TaskType.dailySummary);
    });

    test('getTask 未入队返回 null', () {
      expect(store.getTask('nope'), isNull);
    });
  });
}

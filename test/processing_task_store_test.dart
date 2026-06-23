import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/processing_task.dart';
import 'package:voice_diary/services/database/app_database.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/processing_fgs_backend.dart';
import 'package:voice_diary/services/processing_fgs_controller.dart';
import 'package:voice_diary/services/processing_task_store.dart';

/// 记录调用、可控返回的 fake backend（同 controller 测试的 _FakeBackend 思路）。
/// 让 enqueueTask 调 controller.start() 不触达平台，并可断言 start 是否被调。
class _FakeBackend implements ProcessingFgsBackend {
  bool startResult = true;
  int startCalls = 0;
  int stopCalls = 0;
  bool isServiceRunningValue = false;

  @override
  Future<bool> startProcessingFgs() async {
    startCalls++;
    return startResult;
  }

  @override
  void stopFgs() => stopCalls++;

  @override
  Future<int> getProcessingDelay() async => 0;

  @override
  Future<bool> isServiceRunning() async => isServiceRunningValue;
}

void main() {
  late AppDatabase db;
  late DiaryStorageService storage;
  late ProcessingTaskStore store;
  late _FakeBackend backend;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = DiaryStorageService.forTesting(db);
    backend = _FakeBackend();
    ProcessingFgsController.backend = backend;
    ProcessingFgsController.resetForTesting();
    store = ProcessingTaskStore(storage: storage);
  });
  tearDown(() async {
    ProcessingFgsController.resetForTesting();
    ProcessingFgsController.backend = const FlutterForegroundTaskBackend();
    await db.close();
  });

  group('enqueueTask', () {
    test('入队后内存有该 ref，DB 有该行，ValueNotifier 通知，触发 controller.start', () async {
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

      // 触发了 FGS controller.start（同步：_isStarting=true，hasActivity=true；
      // startProcessingFgs 在 start 的 500ms Timer fire 后才调）
      expect(ProcessingFgsController.hasActivity, isTrue);
      expect(ProcessingFgsController.isRunning, isFalse); // 还在 _isStarting
    });

    test('同一 ref 再次入队 → 内存更新为最新行（新建行）', () async {
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

  group('FGS 消息处理', () {
    test('stageUpdate 更新内存 task.stage（refId 取自 refId）', () async {
      await store.enqueueTask(
        taskType: TaskType.dailySummary,
        refId: '2026-06-21',
      );
      expect(store.getTask('2026-06-21')!.stage, isNull);

      store.onTaskDataForTesting({
        'type': 'dailySummaryStage',
        'refId': '2026-06-21',
        'stage': 'summarizing',
      });

      expect(store.getTask('2026-06-21')!.stage, 'summarizing');
    });

    test('stageUpdate 回退取 entryId（diary 消息用 entryId）', () async {
      await store.enqueueTask(taskType: TaskType.diary, refId: 'e1');

      store.onTaskDataForTesting({
        'type': 'stageUpdate',
        'entryId': 'e1', // diary 的 stageUpdate 用 entryId
        'stage': 'llm',
      });

      expect(store.getTask('e1')!.stage, 'llm');
    });

    test('stageUpdate 忽略未知 refId（内存没有的）', () async {
      await store.enqueueTask(taskType: TaskType.diary, refId: 'e1');
      final before = store.activeCount;

      store.onTaskDataForTesting({
        'type': 'stageUpdate',
        'entryId': 'unknown',
        'stage': 'llm',
      });

      expect(store.activeCount, before); // 不新增
      expect(store.getTask('unknown'), isNull);
    });

    test('taskStarted 从 DB 刷新内存（更新为 DB 最新行）', () async {
      // 内存先入一个 queued（stage=uploading）
      await store.enqueueTask(
        taskType: TaskType.diary,
        refId: 'e1',
        stage: 'uploading',
      );
      // 模拟 FGS 已把 DB 写成 running + stage=asr
      final current = store.getTask('e1')!;
      await storage.updateProcessingTaskStatus(current.id, TaskStatus.running);
      await storage.updateProcessingTaskStage(current.id, 'asr');

      store.onTaskDataForTesting({
        'type': 'taskStarted',
        'refId': 'e1',
        'taskId': current.id,
      });

      // taskStarted 触发 _refreshFromDb（async），等一下再断言
      await Future<void>.delayed(Duration.zero);
      final refreshed = store.getTask('e1')!;
      expect(refreshed.status, TaskStatus.running);
      expect(refreshed.stage, 'asr');
    });

    test('completed 从内存移除（active→done）', () async {
      await store.enqueueTask(taskType: TaskType.diary, refId: 'e1');
      expect(store.isProcessing('e1'), isTrue);

      store.onTaskDataForTesting({
        'type': 'completed',
        'entryId': 'e1',
        'taskId': store.getTask('e1')!.id,
      });

      expect(store.isProcessing('e1'), isFalse);
      expect(store.activeCount, 0);
    });

    test('failed 从内存移除（active→done）', () async {
      await store.enqueueTask(taskType: TaskType.diary, refId: 'e1');

      store.onTaskDataForTesting({
        'type': 'failed',
        'entryId': 'e1',
        'taskId': store.getTask('e1')!.id,
        'error': 'boom',
      });

      expect(store.isProcessing('e1'), isFalse);
    });

    test('dailySummaryCompleted 从内存移除', () async {
      await store.enqueueTask(
        taskType: TaskType.dailySummary,
        refId: '2026-06-21',
      );

      store.onTaskDataForTesting({
        'type': 'dailySummaryCompleted',
        'refId': '2026-06-21',
      });

      expect(store.isProcessing('2026-06-21'), isFalse);
    });

    test('processingDone → controller.onStopped（清活动状态）', () async {
      // enqueue 把 controller 标成活动（_isStarting）
      await store.enqueueTask(taskType: TaskType.diary, refId: 'e1');
      expect(ProcessingFgsController.hasActivity, isTrue);

      store.onTaskDataForTesting({'type': 'processingDone'});

      // onStopped 把 _isRunning/_isStarting 都清，hasActivity 归 false
      expect(ProcessingFgsController.hasActivity, isFalse);
      expect(ProcessingFgsController.isRunning, isFalse);
    });

    test('非 Map 消息忽略（不抛）', () async {
      store.onTaskDataForTesting('not a map');
      store.onTaskDataForTesting(42);
      // 无异常即通过
    });
  });
}

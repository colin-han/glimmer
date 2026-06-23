import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:uuid/uuid.dart';

import '../models/processing_task.dart';
import 'diary_storage_service.dart';
import 'processing_fgs_controller.dart';

/// Processing task 状态中心（main isolate）。
///
/// 维护内存活跃集合（queued/running 的 task，按 ref_id 索引），是 DB 的镜像：
/// - 启动时 [loadFromDb] 从 DB 加载（校准，防消息丢导致 stale）
/// - [startListening] 注册 FGS 消息回调，收 processing 类消息实时刷新内存
/// - [enqueueTask] 写 DB + 内存 + 通知 + 触发 FGS（[ProcessingFgsController.start]）
///
/// UI 通过 [activeRefIds]（ValueNotifier）订阅刷新，通过 [getTask]/[isProcessing]
/// 查询。
///
/// 注意：[ProcessingFgsController] 全部是 static 方法（历史状态收口设计），故本类
/// 直接调 `ProcessingFgsController.start()/onStopped()`，不持有实例。测试通过
/// `ProcessingFgsController.backend` 注入 fake 控制其行为。
class ProcessingTaskStore {
  final DiaryStorageService _storage;
  final _uuid = const Uuid();

  /// ref_id → 最新 active task（内存镜像）。
  final Map<String, ProcessingTask> _activeByRefId = {};

  /// 活跃 ref_id 集合（供 UI 订阅 rebuild）。
  final ValueNotifier<Set<String>> activeRefIds = ValueNotifier<Set<String>>(
    const {},
  );

  ProcessingTaskStore({required DiaryStorageService storage})
    // 字段私有（_storage）与公开参数名（storage）不同，无法用 initializing formal。
    : _storage = storage; // ignore: prefer_initializing_formals

  /// 注册 FGS 消息回调。app 启动时调。
  void startListening() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  /// 注销回调（app 退出/dispose）。
  void stopListening() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
  }

  /// FGS processing 类消息处理：更新内存 + 通知 UI + processingDone→controller。
  @visibleForTesting
  void onTaskDataForTesting(Object data) => _onTaskData(data);

  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    // refId 优先 refId，回退 entryId（diary 的 stageUpdate 用 entryId）
    final refId = data['refId'] as String? ?? data['entryId'] as String?;

    switch (type) {
      case 'taskStarted':
        if (refId != null) _refreshFromDb(refId);
      case 'stageUpdate':
      case 'dailySummaryStage':
        if (refId != null && _activeByRefId.containsKey(refId)) {
          final stage = data['stage'] as String?;
          _activeByRefId[refId] = _activeByRefId[refId]!.copyWith(stage: stage);
          _notify();
        }
      case 'completed':
      case 'failed':
      case 'dailySummaryCompleted':
      case 'dailySummaryFailed':
        // task 结束：从内存移除（active→done）
        if (refId != null) {
          _activeByRefId.remove(refId);
          _notify();
        }
      case 'processingDone':
        // FGS 整体停止：通知 controller 清 isRunning
        ProcessingFgsController.onStopped();
    }
  }

  Future<void> _refreshFromDb(String refId) async {
    final latest = await _storage.getLatestProcessingTask(refId);
    if (latest != null && latest.isActive) {
      _activeByRefId[refId] = latest;
    } else {
      _activeByRefId.remove(refId);
    }
    _notify();
  }

  /// 启动加载：从 DB 读 active（queued/running）填内存。app 启动时调。
  Future<void> loadFromDb() async {
    final pending = await _storage.getPendingProcessingTasks();
    _activeByRefId.clear();
    for (final t in pending) {
      // 同 ref 多行时，getPending 按 queued_at 升序，后面覆盖前面 → 留最新
      _activeByRefId[t.refId] = t;
    }
    _notify();
  }

  /// 入队：写 task 表(queued) + 加内存 + 通知 + 触发 FGS。
  /// 返回新建的 task（调用方可拿 id）。
  Future<ProcessingTask> enqueueTask({
    required TaskType taskType,
    required String refId,
    String? stage,
    Map<String, dynamic> meta = const {},
  }) async {
    final task = ProcessingTask(
      id: _uuid.v4(),
      taskType: taskType,
      refId: refId,
      status: TaskStatus.queued,
      stage: stage,
      meta: meta,
      queuedAt: DateTime.now(),
    );
    await _storage.insertProcessingTask(task);
    _activeByRefId[refId] = task; // 覆盖旧的（新行是最新）
    _notify();
    ProcessingFgsController.start(); // 触发 FGS 处理队列（同步返回 bool）
    return task;
  }

  /// 取某 ref 的活跃 task（内存）。未入队/已完成返回 null。
  ProcessingTask? getTask(String refId) => _activeByRefId[refId];

  /// 某 ref 是否在处理（内存有 active task）。
  bool isProcessing(String refId) => _activeByRefId.containsKey(refId);

  /// 活跃任务数（badge 用）。
  int get activeCount => _activeByRefId.length;

  void _notify() {
    activeRefIds.value = Set<String>.from(_activeByRefId.keys);
  }
}

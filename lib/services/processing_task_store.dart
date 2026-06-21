import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/processing_task.dart';
import 'diary_storage_service.dart';

/// Processing task 状态中心（main isolate）。
///
/// 维护内存活跃集合（queued/running 的 task，按 ref_id 索引），是 DB 的镜像：
/// - 启动时 loadFromDb 从 DB 加载（校准，防消息丢导致 stale）
/// - enqueueTask 写 DB + 内存 + 通知 UI
/// - （Plan B 加：FGS 消息实时刷新内存）
///
/// UI 通过 [activeRefIds]（ValueNotifier）订阅刷新，通过 [getTask]/[isProcessing] 查询。
///
/// 注意：本类是 Plan A 版本——只管内存 + 查询 + enqueue，不接 FGS 消息、不调
/// ProcessingFgsController.start（Plan B 接入）。
class ProcessingTaskStore {
  final DiaryStorageService storage;
  final _uuid = const Uuid();

  /// ref_id → 最新 active task（内存镜像）。
  final Map<String, ProcessingTask> _activeByRefId = {};

  /// 活跃 ref_id 集合（供 UI 订阅 rebuild）。
  final ValueNotifier<Set<String>> activeRefIds = ValueNotifier<Set<String>>(
    const {},
  );

  ProcessingTaskStore({required this.storage});

  /// 启动加载：从 DB 读 active（queued/running）填内存。app 启动时调。
  Future<void> loadFromDb() async {
    final pending = await storage.getPendingProcessingTasks();
    _activeByRefId.clear();
    for (final t in pending) {
      // 同 ref 多行时，getPending 按 queued_at 升序，后面覆盖前面 → 留最新
      _activeByRefId[t.refId] = t;
    }
    _notify();
  }

  /// 入队：写 task 表(queued) + 加内存 + 通知。
  /// 返回新建的 task（调用方可拿 id）。
  ///
  /// 注意：Plan A 版本不触发 FGS（Plan B 加 controller.start）。
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
    await storage.insertProcessingTask(task);
    _activeByRefId[refId] = task; // 覆盖旧的（方案 A：新行是最新）
    _notify();
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

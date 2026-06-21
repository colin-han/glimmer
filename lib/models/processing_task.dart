import 'package:flutter/foundation.dart';

/// 处理任务类型。
enum TaskType {
  diary,
  dailySummary;

  static TaskType fromString(String s) {
    switch (s) {
      case 'diary':
        return TaskType.diary;
      case 'daily_summary':
        return TaskType.dailySummary;
    }
    return TaskType.diary;
  }

  String get value {
    switch (this) {
      case TaskType.diary:
        return 'diary';
      case TaskType.dailySummary:
        return 'daily_summary';
    }
  }
}

/// 处理任务状态（消息队列语义）。
enum TaskStatus {
  queued,
  running,
  completed,
  failed;

  static TaskStatus fromString(String s) {
    switch (s) {
      case 'queued':
        return TaskStatus.queued;
      case 'running':
        return TaskStatus.running;
      case 'completed':
        return TaskStatus.completed;
      case 'failed':
        return TaskStatus.failed;
    }
    return TaskStatus.queued;
  }

  String get value {
    switch (this) {
      case TaskStatus.queued:
        return 'queued';
      case TaskStatus.running:
        return 'running';
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.failed:
        return 'failed';
    }
  }
}

/// processing_tasks 表的 model（与 drift 行 ProcessingTaskRow 分离，同 DiaryEntry 模式）。
@immutable
class ProcessingTask {
  final String id;
  final TaskType taskType;
  final String refId;
  final TaskStatus status;
  final String? stage;
  final String? failedMessage;
  final Map<String, dynamic> meta;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const ProcessingTask({
    required this.id,
    required this.taskType,
    required this.refId,
    required this.status,
    required this.queuedAt,
    this.stage,
    this.failedMessage,
    this.meta = const {},
    this.startedAt,
    this.finishedAt,
  });

  /// 是否处于活跃状态（在队列或正在跑）。
  bool get isActive =>
      status == TaskStatus.queued || status == TaskStatus.running;

  /// 复制（FGS 消息刷新内存时用：更新 stage/status，其余字段不变）。
  ProcessingTask copyWith({String? stage, TaskStatus? status}) {
    return ProcessingTask(
      id: id,
      taskType: taskType,
      refId: refId,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      failedMessage: failedMessage,
      meta: meta,
      queuedAt: queuedAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
  }
}

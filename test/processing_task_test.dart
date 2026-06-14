import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/processing_stage.dart';
import 'package:voice_diary/services/diary_processing_task.dart';
import 'package:voice_diary/services/processing_task.dart';

DiaryEntry _entry({
  String id = 'e1',
  ProcessingStage stage = ProcessingStage.completed,
  String title = '',
}) {
  return DiaryEntry(
    id: id,
    title: title,
    folderPath: '/x',
    durationSeconds: 0,
    createdAt: DateTime(2026, 6, 13),
    status: EntryStatus.processing,
    processingStage: stage,
  );
}

void main() {
  // DiaryProcessingTask 是从原 ProcessingTaskHandler 提取的纯搬运（行为完全不变）。
  // 其 execute 内部调用 FlutterForegroundTask（platform 插件），单测环境无法驱动，
  // 故这里只验证 Task 契约；execute 行为由 Task 10 手动集成验证覆盖
  // （与 spec §11「测调度而非提取全链路」一致）。
  test('DiaryProcessingTask 实现 ProcessingTask 契约', () {
    final task = DiaryProcessingTask(_entry());
    expect(task, isA<ProcessingTask>());
    expect(task.taskType, 'diary');
    expect(task.id, 'e1');
    expect(task.notificationText, isNotEmpty);
  });

  test('notificationText 基于 displayTitle', () {
    final task = DiaryProcessingTask(
      DiaryEntry(
        id: 'e2',
        title: '今天很开心',
        folderPath: '/x',
        durationSeconds: 0,
        createdAt: DateTime(2026, 6, 13),
      ),
    );
    expect(task.notificationText, contains('今天很开心'));
  });
}

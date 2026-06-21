import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/exceptions.dart';
import 'package:voice_diary/models/daily_summary.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/processing_task.dart' as task_model;
import 'package:voice_diary/services/api_log_service.dart';
import 'package:voice_diary/services/asr_service.dart';
import 'package:voice_diary/services/daily_summary_processing_task.dart';
import 'package:voice_diary/services/daily_summary_service.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/llm_service.dart';
import 'package:voice_diary/services/processing_task.dart';
import 'package:voice_diary/services/tos_upload_service.dart';

class _MockStorage extends Mock implements DiaryStorageService {}

class _MockDailySummary extends Mock implements DailySummaryService {}

class _MockLlm extends Mock implements LlmService {}

class _MockAsr extends Mock implements AsrService {}

class _MockTos extends Mock implements TosUploadService {}

class _MockApiLog extends Mock implements ApiLogService {}

DiaryEntry _entry({EntryStatus status = EntryStatus.completed}) {
  return DiaryEntry(
    id: 'e1',
    title: 't',
    folderPath: '/x',
    durationSeconds: 0,
    createdAt: DateTime(2026, 6, 13),
    status: status,
  );
}

/// 构造一个 daily_summary model task（refId=date）。
task_model.ProcessingTask _task(String date, {String id = 'ts1'}) {
  return task_model.ProcessingTask(
    id: id,
    taskType: task_model.TaskType.dailySummary,
    refId: date,
    status: task_model.TaskStatus.queued,
    queuedAt: DateTime(2026, 6, 13),
  );
}

ProcessingContext _ctx({
  required _MockStorage storage,
  required _MockDailySummary dailySummary,
  required List<Map<String, dynamic>> sent,
}) {
  return ProcessingContext(
    storage: storage,
    llm: _MockLlm(),
    asr: _MockAsr(),
    tos: _MockTos(),
    apiLog: _MockApiLog(),
    dailySummary: dailySummary,
    sendToMain: sent.add,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      DailySummary(
        date: 'fb',
        title: '',
        status: EntryStatus.completed,
        sourceEntryIds: const [],
        entryCount: 0,
        createdAt: DateTime(2026, 6, 13),
      ),
    );
    registerFallbackValue(
      const DailySummaryData(
        version: 1,
        date: 'fb',
        title: '',
        summary: '',
        outline: '',
        sourceEntryIds: [],
        degraded: false,
      ),
    );
    registerFallbackValue(<DiaryEntry>[]);
    registerFallbackValue(task_model.TaskStatus.queued);
  });

  /// 统一 stub：task.status 更新（running/completed/failed 都会调）。
  void stubStatusUpdates(_MockStorage storage) {
    when(
      () => storage.updateProcessingTaskStatus(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => storage.updateProcessingTaskStatus(
        any(),
        any(),
        failedMessage: any(named: 'failedMessage'),
      ),
    ).thenAnswer((_) async {});
    // 默认无 active task（hasProcessing=false）；个别测试 override
    when(
      () => storage.getPendingProcessingTasks(),
    ).thenAnswer((_) async => <task_model.ProcessingTask>[]);
  }

  test('0 篇 → 标记 completed 空总结，通知 dailySummaryCompleted', () async {
    const date = '2026-06-13';
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    stubStatusUpdates(storage);
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => const []);
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(
      () => storage.writeDailySummaryJson(any(), any()),
    ).thenAnswer((_) async {});
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask(
      _task(date),
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verify(() => storage.writeDailySummaryJson(date, any())).called(1);
    verify(() => storage.saveDailySummary(any())).called(1);
    verify(
      () => storage.updateProcessingTaskStatus(
        'ts1',
        task_model.TaskStatus.completed,
      ),
    ).called(1);
    verifyNever(() => dailySummary.summarizeDay(any()));
    expect(sent.any((m) => m['type'] == 'dailySummaryCompleted'), isTrue);
  });

  test('当天有 processing 篇 → 标记 failed，不调 summarizeDay', () async {
    const date = '2026-06-13';
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    stubStatusUpdates(storage);
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => [_entry(status: EntryStatus.processing)]);
    // 当天 diary e1 有 active task → hasProcessing=true → failed
    when(() => storage.getPendingProcessingTasks()).thenAnswer(
      (_) async => [
        task_model.ProcessingTask(
          id: 'pt1',
          taskType: task_model.TaskType.diary,
          refId: 'e1',
          status: task_model.TaskStatus.running,
          queuedAt: DateTime(2026, 6, 13),
        ),
      ],
    );

    await DailySummaryProcessingTask(
      _task(date),
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verifyNever(() => dailySummary.summarizeDay(any()));
    verifyNever(() => storage.writeDailySummaryJson(any(), any()));
    verifyNever(() => storage.saveDailySummary(any()));
    verify(
      () => storage.updateProcessingTaskStatus(
        'ts1',
        task_model.TaskStatus.failed,
        failedMessage: any(named: 'failedMessage'),
      ),
    ).called(1);
    expect(sent.any((m) => m['type'] == 'dailySummaryFailed'), isTrue);
  });

  test('正常 → summarizeDay + 写文件 + completed', () async {
    const date = '2026-06-13';
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    stubStatusUpdates(storage);
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => [_entry()]);
    when(() => dailySummary.summarizeDay(any())).thenAnswer(
      (_) async => const DailySummaryResult(
        title: 't',
        summary: 's',
        outline: 'o',
        degraded: false,
      ),
    );
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(
      () => storage.writeDailySummaryJson(any(), any()),
    ).thenAnswer((_) async {});
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask(
      _task(date),
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verify(() => dailySummary.summarizeDay(any())).called(1);
    verify(() => storage.writeDailySummaryJson(date, any())).called(1);
    verify(
      () => storage.updateProcessingTaskStatus(
        'ts1',
        task_model.TaskStatus.completed,
      ),
    ).called(1);
    expect(sent.any((m) => m['type'] == 'dailySummaryCompleted'), isTrue);
  });

  test('summarizeDay 失败 → 标记 failed + dailySummaryFailed', () async {
    const date = '2026-06-13';
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    stubStatusUpdates(storage);
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => [_entry()]);
    when(
      () => dailySummary.summarizeDay(any()),
    ).thenThrow(const DailySummaryException('聚合失败'));

    await DailySummaryProcessingTask(
      _task(date),
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verifyNever(() => storage.writeDailySummaryJson(any(), any()));
    verifyNever(() => storage.saveDailySummary(any()));
    verify(
      () => storage.updateProcessingTaskStatus(
        'ts1',
        task_model.TaskStatus.failed,
        failedMessage: any(named: 'failedMessage'),
      ),
    ).called(1);
    expect(sent.any((m) => m['type'] == 'dailySummaryFailed'), isTrue);
  });
}

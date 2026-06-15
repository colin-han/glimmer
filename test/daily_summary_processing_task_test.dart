import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/exceptions.dart';
import 'package:voice_diary/models/daily_summary.dart';
import 'package:voice_diary/models/diary_entry.dart';
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
  });

  test('0 篇 → 标记 completed 空总结，通知 dailySummaryCompleted', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => const []);
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(
      () => storage.writeDailySummaryJson(any(), any()),
    ).thenAnswer((_) async {});
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask(
      '2026-06-13',
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verify(() => storage.writeDailySummaryJson('2026-06-13', any())).called(1);
    verify(() => storage.saveDailySummary(any())).called(1);
    verifyNever(() => dailySummary.summarizeDay(any()));
    expect(sent.any((m) => m['type'] == 'dailySummaryCompleted'), isTrue);
  });

  test('当天有 processing 篇 → 标记 failed，不调 summarizeDay', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => [_entry(status: EntryStatus.processing)]);
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask(
      '2026-06-13',
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verifyNever(() => dailySummary.summarizeDay(any()));
    verifyNever(() => storage.writeDailySummaryJson(any(), any()));
    expect(sent.any((m) => m['type'] == 'dailySummaryFailed'), isTrue);
  });

  test('正常 → summarizeDay + 写文件 + completed', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
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
      '2026-06-13',
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verify(() => dailySummary.summarizeDay(any())).called(1);
    verify(() => storage.writeDailySummaryJson('2026-06-13', any())).called(1);
    expect(sent.any((m) => m['type'] == 'dailySummaryCompleted'), isTrue);
  });

  test('summarizeDay 失败 → 标记 failed + dailySummaryFailed', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => [_entry()]);
    when(
      () => dailySummary.summarizeDay(any()),
    ).thenThrow(const DailySummaryException('聚合失败'));
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask(
      '2026-06-13',
    ).execute(_ctx(storage: storage, dailySummary: dailySummary, sent: sent));

    verifyNever(() => storage.writeDailySummaryJson(any(), any()));
    expect(sent.any((m) => m['type'] == 'dailySummaryFailed'), isTrue);
  });
}

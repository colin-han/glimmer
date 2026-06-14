import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/exceptions.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/utterance.dart';
import 'package:voice_diary/services/api_log_service.dart';
import 'package:voice_diary/services/daily_summary_service.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/llm_service.dart';

class _MockStorage extends Mock implements DiaryStorageService {}

class _MockLlm extends Mock implements LlmService {}

class _MockApiLog extends Mock implements ApiLogService {}

DiaryEntry _entry({
  required String id,
  required DateTime createdAt,
  String folder = '/x',
}) {
  return DiaryEntry(
    id: id,
    title: 't',
    folderPath: folder,
    durationSeconds: 0,
    createdAt: createdAt,
  );
}

void main() {
  late _MockStorage storage;
  late _MockLlm llm;
  late _MockApiLog apiLog;
  late DailySummaryService service;

  setUp(() {
    storage = _MockStorage();
    llm = _MockLlm();
    apiLog = _MockApiLog();
    service = DailySummaryService(storage: storage, llm: llm, apiLog: apiLog);
    // logApiCall 默认 no-op
    when(
      () => apiLog.logApiCall(
        diaryId: any(named: 'diaryId'),
        apiType: any(named: 'apiType'),
        step: any(named: 'step'),
        status: any(named: 'status'),
        durationMs: any(named: 'durationMs'),
        errorMessage: any(named: 'errorMessage'),
        responseSummary: any(named: 'responseSummary'),
        promptTokens: any(named: 'promptTokens'),
        completionTokens: any(named: 'completionTokens'),
        totalTokens: any(named: 'totalTokens'),
        cachedTokens: any(named: 'cachedTokens'),
        reasoningTokens: any(named: 'reasoningTokens'),
      ),
    ).thenAnswer((_) async {});
  });

  test('正常模式：拼接各篇全文（按时间排序），degraded=false', () async {
    final e1 = _entry(id: 'e1', createdAt: DateTime(2026, 6, 13, 9));
    final e2 = _entry(id: 'e2', createdAt: DateTime(2026, 6, 13, 14));
    when(() => storage.readTranscriptJson(any())).thenAnswer(
      (_) async => TranscriptData(
        version: 1,
        utterances: [Utterance(text: '内容', startTime: 0, endTime: 1)],
      ),
    );
    when(
      () => llm.summarizeDayText(any(), degraded: any(named: 'degraded')),
    ).thenAnswer(
      (_) async => const DailySummaryResult(
        title: '标题',
        summary: '正文',
        outline: '播报',
        degraded: false,
      ),
    );

    final result = await service.summarizeDay([e2, e1]); // 故意倒序验证排序

    expect(result.title, '标题');
    expect(result.degraded, isFalse);
    final captured = verify(
      () => llm.summarizeDayText(
        captureAny(),
        degraded: captureAny(named: 'degraded'),
      ),
    ).captured;
    expect(captured[0], contains('### 第 1 段 · 09:00')); // e1 排序后在前
    expect(captured[0], contains('### 第 2 段 · 14:00'));
    expect(captured[1], isFalse);
  });

  test('降级模式：全文超阈值改用各篇 summary 聚合，degraded=true', () async {
    final e1 = _entry(id: 'e1', createdAt: DateTime(2026, 6, 13, 9));
    when(() => storage.readTranscriptJson(any())).thenAnswer(
      (_) async => TranscriptData(
        version: 1,
        utterances: [Utterance(text: 'x' * 30000, startTime: 0, endTime: 1)],
      ),
    );
    when(() => storage.readLlmResult(any())).thenAnswer(
      (_) async => LlmResultData(
        version: 1,
        title: '早晨',
        summary: '晨跑内容',
        outline: '',
        utterances: const [],
      ),
    );
    when(
      () => llm.summarizeDayText(any(), degraded: any(named: 'degraded')),
    ).thenAnswer(
      (_) async => const DailySummaryResult(
        title: 't',
        summary: 's',
        outline: 'o',
        degraded: true,
      ),
    );

    final result = await service.summarizeDay([e1]);

    expect(result.degraded, isTrue);
    final captured = verify(
      () => llm.summarizeDayText(
        captureAny(),
        degraded: captureAny(named: 'degraded'),
      ),
    ).captured;
    expect(captured[1], isTrue);
    expect(captured[0], contains('晨跑内容')); // 用了 summary 而非全文
  });

  test('LLM 失败时抛 DailySummaryException', () async {
    final e1 = _entry(id: 'e1', createdAt: DateTime(2026, 6, 13, 9));
    when(() => storage.readTranscriptJson(any())).thenAnswer(
      (_) async => TranscriptData(
        version: 1,
        utterances: [Utterance(text: 'a', startTime: 0, endTime: 1)],
      ),
    );
    when(
      () => llm.summarizeDayText(any(), degraded: any(named: 'degraded')),
    ).thenThrow(Exception('网络错误'));

    expect(
      () => service.summarizeDay([e1]),
      throwsA(isA<DailySummaryException>()),
    );
  });
}

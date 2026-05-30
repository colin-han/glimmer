import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
import '../models/utterance.dart';
import 'database/app_database.dart' hide DiaryEntry;

class DiaryStorageService {
  final AppDatabase _db;

  DiaryStorageService() : _db = AppDatabase();

  Future<String> get _baseDir async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, 'diaries');
  }

  Future<String> createDiaryFolder(String id) async {
    final base = await _baseDir;
    final folder = Directory(p.join(base, id));
    await folder.create(recursive: true);
    return folder.path;
  }

  Future<void> createEntry(DiaryEntry entry) async {
    await _db.insertEntry(DiaryEntriesCompanion.insert(
      id: entry.id,
      title: entry.title,
      folderPath: entry.folderPath,
      durationSeconds: entry.durationSeconds,
      createdAt: entry.createdAt.millisecondsSinceEpoch,
    ));
  }

  // --- transcript.json ---

  Future<void> writeTranscriptJson(
      String folderPath, TranscriptData data) async {
    final file = File(p.join(folderPath, 'transcript.json'));
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  Future<TranscriptData> readTranscriptJson(String folderPath) async {
    final file = File(p.join(folderPath, 'transcript.json'));
    final content = await file.readAsString();
    return TranscriptData.fromJson(
        jsonDecode(content) as Map<String, dynamic>);
  }

  // --- summary.md ---

  Future<void> writeSummary(String folderPath, String content) async {
    final file = File(p.join(folderPath, 'summary.md'));
    await file.writeAsString(content);
  }

  Future<String> readSummary(String folderPath) async {
    final file = File(p.join(folderPath, 'summary.md'));
    return file.readAsString();
  }

  // --- summary_utterances.json ---

  Future<void> writeSummaryUtterances(
      String folderPath, SummaryUtteranceData data) async {
    final file = File(p.join(folderPath, 'summary_utterances.json'));
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  Future<SummaryUtteranceData> readSummaryUtterances(
      String folderPath) async {
    final file = File(p.join(folderPath, 'summary_utterances.json'));
    final content = await file.readAsString();
    return SummaryUtteranceData.fromJson(
        jsonDecode(content) as Map<String, dynamic>);
  }

  // --- llm_result.json ---

  Future<void> writeLlmResult(String folderPath, LlmResultData data) async {
    final file = File(p.join(folderPath, 'llm_result.json'));
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  Future<LlmResultData> readLlmResult(String folderPath) async {
    final file = File(p.join(folderPath, 'llm_result.json'));
    final content = await file.readAsString();
    return LlmResultData.fromJson(
        jsonDecode(content) as Map<String, dynamic>);
  }

  /// 检查 llm_result.json 是否存在（用于向后兼容判断）
  Future<bool> hasLlmResult(String folderPath) async {
    final file = File(p.join(folderPath, 'llm_result.json'));
    return file.exists();
  }

  // --- 查询 ---

  Future<List<DiaryEntry>> getAllEntries() async {
    final rows = await _db.getAllEntries();
    return rows
        .map((r) => DiaryEntry(
              id: r.id,
              title: r.title,
              folderPath: r.folderPath,
              durationSeconds: r.durationSeconds,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ))
        .toList();
  }

  Future<DiaryEntry> getEntryById(String id) async {
    final r = await _db.getEntryById(id);
    return DiaryEntry(
      id: r.id,
      title: r.title,
      folderPath: r.folderPath,
      durationSeconds: r.durationSeconds,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    );
  }

  Future<void> deleteEntry(String id, String folderPath) async {
    await _db.deleteEntry(id);
    final folder = Directory(folderPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  }
}

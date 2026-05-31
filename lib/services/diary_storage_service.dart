import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
import '../models/tag.dart';
import '../models/utterance.dart';
import 'database/app_database.dart' hide DiaryEntry, Tag, DiaryTagRelation;

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
      tosKey: Value(entry.tosKey),
      audioFormat: Value(entry.audioFormat),
      uploadedAt: Value(entry.uploadedAt?.millisecondsSinceEpoch),
    ));
  }

  Future<void> updateTitle(String id, String title) async {
    await (_db.update(_db.diaryEntries)
          ..where((t) => t.id.equals(id)))
        .write(DiaryEntriesCompanion(title: Value(title)));
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
              tosKey: r.tosKey,
              audioFormat: r.audioFormat,
              uploadedAt: r.uploadedAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(r.uploadedAt!)
                  : null,
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
      tosKey: r.tosKey,
      audioFormat: r.audioFormat,
      uploadedAt: r.uploadedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(r.uploadedAt!)
          : null,
    );
  }

  Future<void> deleteEntry(String id, String folderPath) async {
    await _db.deleteEntry(id);
    final folder = Directory(folderPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  }

  // --- Tag CRUD ---

  Future<List<Tag>> getAllTags() async {
    final rows = await _db.getAllTags();
    return rows
        .map((r) => Tag(
              id: r.id,
              name: r.name,
              matchPrompt: r.matchPrompt,
              color: r.color,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ))
        .toList();
  }

  Future<Tag> getTagById(String id) async {
    final r = await _db.getTagById(id);
    return Tag(
      id: r.id,
      name: r.name,
      matchPrompt: r.matchPrompt,
      color: r.color,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    );
  }

  Future<void> createTag(Tag tag) async {
    await _db.insertTag(TagsCompanion.insert(
      id: tag.id,
      name: tag.name,
      matchPrompt: Value(tag.matchPrompt),
      color: Value(tag.color),
      createdAt: tag.createdAt.millisecondsSinceEpoch,
    ));
  }

  Future<void> updateTag(Tag tag) async {
    await _db.updateTag(TagsCompanion(
      id: Value(tag.id),
      name: Value(tag.name),
      matchPrompt: Value(tag.matchPrompt),
      color: Value(tag.color),
      createdAt: Value(tag.createdAt.millisecondsSinceEpoch),
    ));
  }

  Future<void> deleteTag(String tagId) async {
    await _db.deleteDiaryTagsByTag(tagId);
    await _db.deleteTag(tagId);
  }

  // --- DiaryTagRelation ---

  Future<void> addDiaryTag(String diaryId, String tagId,
      {String source = 'manual'}) async {
    await _db.insertDiaryTag(DiaryTagRelationsCompanion.insert(
      diaryId: diaryId,
      tagId: tagId,
      source: Value(source),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> removeDiaryTag(String diaryId, String tagId) async {
    await _db.deleteDiaryTag(diaryId, tagId);
  }

  Future<List<DiaryTagRelation>> getTagsForDiary(String diaryId) async {
    final rows = await _db.getTagsForDiary(diaryId);
    return rows
        .map((r) => DiaryTagRelation(
              diaryId: r.diaryId,
              tagId: r.tagId,
              source: r.source,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ))
        .toList();
  }

  Future<int> getDiaryCountForTag(String tagId) async {
    return await _db.getDiaryCountForTag(tagId);
  }

  Future<void> autoTagDiary(String diaryId, List<String> tagIds) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final tagId in tagIds) {
      await _db.insertDiaryTag(DiaryTagRelationsCompanion.insert(
        diaryId: diaryId,
        tagId: tagId,
        source: const Value('auto'),
        createdAt: now,
      ));
    }
  }

  Future<List<Tag>> getFullTagsForDiary(String diaryId) async {
    final relations = await getTagsForDiary(diaryId);
    final tags = <Tag>[];
    for (final rel in relations) {
      try {
        tags.add(await getTagById(rel.tagId));
      } catch (_) {}
    }
    return tags;
  }

  /// 更新日记的 TOS 上传信息
  Future<void> updateTosInfo(String id,
      {String? tosKey, String? audioFormat, int? uploadedAt}) async {
    final companion = DiaryEntriesCompanion(
      tosKey: Value(tosKey),
      audioFormat: Value(audioFormat ?? 'wav'),
      uploadedAt: Value(uploadedAt),
    );
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id)))
        .write(companion);
  }

  /// 根据音频格式获取音频文件路径，优先 OGG，回退 WAV
  String getAudioPath(String folderPath, String audioFormat) {
    final oggPath = p.join(folderPath, 'audio.ogg');
    final wavPath = p.join(folderPath, 'audio.wav');
    if (audioFormat == 'ogg' || File(oggPath).existsSync()) {
      return oggPath;
    }
    return wavPath;
  }

  Future<List<DiaryEntry>> searchEntries(String query) async {
    final allEntries = await getAllEntries();
    final lowerQuery = query.toLowerCase();

    final results = <DiaryEntry>[];
    for (final entry in allEntries) {
      if (entry.title.toLowerCase().contains(lowerQuery)) {
        results.add(entry);
        continue;
      }
      try {
        if (await hasLlmResult(entry.folderPath)) {
          final llmData = await readLlmResult(entry.folderPath);
          if (llmData.content.toLowerCase().contains(lowerQuery)) {
            results.add(entry);
          }
        }
      } catch (_) {}
    }
    return results;
  }
}

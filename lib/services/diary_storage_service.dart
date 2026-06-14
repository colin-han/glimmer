import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
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

  /// 原子写入：先写临时文件（同目录、flush 后）再 rename 覆盖目标。
  /// 直接 writeAsString 会先截断目标文件，若写入中途进程被杀会留下截断/损坏的 JSON，
  /// 导致正文永久丢失。临时文件+rename 在同一文件系统上是原子的，崩溃时旧文件仍完整。
  Future<void> _writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
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
      weatherIcon: Value(entry.weatherIcon),
      weatherText: Value(entry.weatherText),
      temperature: Value(entry.temperature),
      locationName: Value(entry.locationName),
      locationLat: Value(entry.locationLat),
      locationLon: Value(entry.locationLon),
      status: Value(entry.status.name),
      processingStage: Value(entry.processingStage.value),
      asrTaskId: Value(entry.asrTaskId),
    ));
  }

  Future<void> updateEntry(DiaryEntry entry) async {
    await _db.updateEntry(DiaryEntriesCompanion(
      id: Value(entry.id),
      title: Value(entry.title),
      folderPath: Value(entry.folderPath),
      durationSeconds: Value(entry.durationSeconds),
      createdAt: Value(entry.createdAt.millisecondsSinceEpoch),
      tosKey: Value(entry.tosKey),
      audioFormat: Value(entry.audioFormat),
      uploadedAt: Value(entry.uploadedAt?.millisecondsSinceEpoch),
      weatherIcon: Value(entry.weatherIcon),
      weatherText: Value(entry.weatherText),
      temperature: Value(entry.temperature),
      locationName: Value(entry.locationName),
      locationLat: Value(entry.locationLat),
      locationLon: Value(entry.locationLon),
      status: Value(entry.status.name),
      processingStage: Value(entry.processingStage.value),
      asrTaskId: Value(entry.asrTaskId),
    ));
  }

  Future<void> updateTitle(String id, String title) async {
    await (_db.update(_db.diaryEntries)
          ..where((t) => t.id.equals(id)))
        .write(DiaryEntriesCompanion(title: Value(title)));
  }

  Future<void> updateEntryStatus(String id, EntryStatus status) async {
    await (_db.update(_db.diaryEntries)
          ..where((t) => t.id.equals(id)))
        .write(DiaryEntriesCompanion(status: Value(status.name)));
  }

  Future<void> updateEntryTitleAndStatus(
      String id, String title, EntryStatus status) async {
    await (_db.update(_db.diaryEntries)
          ..where((t) => t.id.equals(id)))
        .write(DiaryEntriesCompanion(
      title: Value(title),
      status: Value(status.name),
    ));
  }

  // === 数据格式兼容性基线 ===
  // 自 v1.0.0 起，本应用只保证对 v1.0.0 及之后产生的数据格式向后兼容
  // （transcript.json / llm_result.json / audio.wav|ogg）。
  // v1.0.0 之前基于 summary.md + summary_utterances.json 的旧格式【不再支持读取】，
  // 因此 readLlmResult / hasLlmResult 不回退读旧格式——这是有意为之，非遗漏。
  // 下方的 writeSummary / writeSummaryUtterances 仅为历史保留，已无写入路径调用。
  // 详见 CLAUDE.md「数据兼容性要求」。

  // --- transcript.json ---

  Future<void> writeTranscriptJson(
      String folderPath, TranscriptData data) async {
    final file = File(p.join(folderPath, 'transcript.json'));
    await _writeAtomic(file, jsonEncode(data.toJson()));
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
    await _writeAtomic(file, content);
  }

  Future<String> readSummary(String folderPath) async {
    final file = File(p.join(folderPath, 'summary.md'));
    return file.readAsString();
  }

  // --- summary_utterances.json ---

  Future<void> writeSummaryUtterances(
      String folderPath, SummaryUtteranceData data) async {
    final file = File(p.join(folderPath, 'summary_utterances.json'));
    await _writeAtomic(file, jsonEncode(data.toJson()));
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
    await _writeAtomic(file, jsonEncode(data.toJson()));
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

  /// 查询处理中的日记数量
  Future<int> getProcessingEntryCount() => _db.getProcessingEntryCount();

  EntryStatus _parseStatus(String? status) {
    if (status == 'processing') return EntryStatus.processing;
    if (status == 'failed') return EntryStatus.failed;
    return EntryStatus.completed;
  }

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
              weatherIcon: r.weatherIcon,
              weatherText: r.weatherText,
              temperature: r.temperature,
              locationName: r.locationName,
              locationLat: r.locationLat,
              locationLon: r.locationLon,
              status: _parseStatus(r.status),
              processingStage: ProcessingStage.fromString(r.processingStage),
              asrTaskId: r.asrTaskId,
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
      weatherIcon: r.weatherIcon,
      weatherText: r.weatherText,
      temperature: r.temperature,
      locationName: r.locationName,
      locationLat: r.locationLat,
      locationLon: r.locationLon,
      status: _parseStatus(r.status),
      processingStage: ProcessingStage.fromString(r.processingStage),
      asrTaskId: r.asrTaskId,
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

  /// 获取未上传到 TOS 的日记条目（用于历史迁移）
  Future<List<DiaryEntry>> getEntriesWithoutTos() async {
    final all = await getAllEntries();
    return all.where((e) => e.tosKey == null).toList();
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
          if (llmData.summary.toLowerCase().contains(lowerQuery)) {
            results.add(entry);
          }
        }
      } catch (_) {}
    }
    return results;
  }

  /// 查询所有待处理的条目（status=processing），按创建时间升序
  Future<List<DiaryEntry>> getPendingEntries() async {
    final rows = await _db.getPendingEntries();
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
              weatherIcon: r.weatherIcon,
              weatherText: r.weatherText,
              temperature: r.temperature,
              locationName: r.locationName,
              locationLat: r.locationLat,
              locationLon: r.locationLon,
              status: _parseStatus(r.status),
              processingStage: ProcessingStage.fromString(r.processingStage),
              asrTaskId: r.asrTaskId,
            ))
        .toList();
  }

  /// 更新处理阶段
  Future<void> updateProcessingStage(String id, ProcessingStage stage) async {
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id)))
        .write(DiaryEntriesCompanion(
      processingStage: Value(stage.value),
    ));
  }

  /// 更新处理阶段和 tosKey
  Future<void> updateTosKeyAndStage(String id, String tosKey, ProcessingStage stage) async {
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id)))
        .write(DiaryEntriesCompanion(
      tosKey: Value(tosKey),
      processingStage: Value(stage.value),
    ));
  }

  /// 更新处理阶段和 asrTaskId
  Future<void> updateAsrTaskIdAndStage(String id, String asrTaskId, ProcessingStage stage) async {
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id)))
        .write(DiaryEntriesCompanion(
      asrTaskId: Value(asrTaskId),
      processingStage: Value(stage.value),
    ));
  }

  /// 获取条目的 tosKey
  Future<String?> getTosKey(String id) async {
    final entry = await _db.getEntryById(id);
    return entry.tosKey;
  }
}

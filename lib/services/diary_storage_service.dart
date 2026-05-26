import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
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

  Future<void> writeTranscript(String folderPath, String text) async {
    final file = File(p.join(folderPath, 'transcript.txt'));
    await file.writeAsString(text);
  }

  Future<void> writeSummary(String folderPath, String content) async {
    final file = File(p.join(folderPath, 'summary.md'));
    await file.writeAsString(content);
  }

  Future<String> readTranscript(String folderPath) async {
    final file = File(p.join(folderPath, 'transcript.txt'));
    return file.readAsString();
  }

  Future<String> readSummary(String folderPath) async {
    final file = File(p.join(folderPath, 'summary.md'));
    return file.readAsString();
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

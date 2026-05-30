import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageMigrationService {
  static const _versionKey = 'storage_version';
  static const _currentVersion = 1;

  Future<void> runMigrations() async {
    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getInt(_versionKey) ?? 0;

    if (currentVersion >= _currentVersion) return;

    for (var v = currentVersion + 1; v <= _currentVersion; v++) {
      await _runMigration(v);
    }

    await prefs.setInt(_versionKey, _currentVersion);
  }

  Future<void> _runMigration(int version) async {
    switch (version) {
      case 1:
        await _migrateV0ToV1();
        break;
    }
  }

  Future<void> _migrateV0ToV1() async {
    final docDir = await getApplicationDocumentsDirectory();
    final diariesDir = Directory(p.join(docDir.path, 'diaries'));
    if (await diariesDir.exists()) {
      await diariesDir.delete(recursive: true);
    }

    final dbFile = File(p.join(docDir.path, 'voice_diary.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  }
}

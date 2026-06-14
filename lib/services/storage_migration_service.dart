import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageMigrationService {
  static const _versionKey = 'storage_version';
  static const _currentVersion = 2;

  Future<void> runMigrations() async {
    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getInt(_versionKey) ?? 0;

    if (currentVersion >= _currentVersion) return;

    // 版本变化时先备份当前存储目录
    await _backupBeforeMigration(currentVersion);

    for (var v = currentVersion + 1; v <= _currentVersion; v++) {
      await _runMigration(v);
    }

    await prefs.setInt(_versionKey, _currentVersion);
  }

  /// 将应用文档目录打包为 zip 备份
  Future<void> _backupBeforeMigration(int fromVersion) async {
    final docDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docDir.parent.path, 'migration_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final backupName = 'backup_v${fromVersion}_$timestamp.zip';
    final backupPath = p.join(backupDir.path, backupName);

    final encoder = ZipFileEncoder();
    encoder.zipDirectory(Directory(docDir.path), filename: backupPath);
    debugPrint('[迁移备份] 已备份至 $backupPath');
  }

  Future<void> _runMigration(int version) async {
    switch (version) {
      // v0→v1 已废弃（原始实现会删除 diaries 和数据库，过于危险）
      // v1→v2: 占位，保留迁移框架供未来使用
    }
  }
}

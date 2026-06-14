import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_encoder_service.dart';
import 'diary_storage_service.dart';
import '../models/diary_entry.dart';
import 'tos_upload_service.dart';

/// 历史数据迁移服务：将未上传的音频文件上传 TOS。
class MigrationService {
  static const _migratedKey = 'tos_migration_done';

  final DiaryStorageService _storage;
  final TosUploadService _tos;

  MigrationService(this._storage, this._tos);

  /// 迁移是否已完成
  static Future<bool> isMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_migratedKey) ?? false;
  }

  /// 执行迁移，返回迁移的条目数量。
  /// 只有全部条目处理完毕后才标记 flag，支持部分失败后重试。
  Future<int> migrateUnuploadedEntries() async {
    final entries = await _storage.getEntriesWithoutTos();
    if (entries.isEmpty) {
      await _markDone();
      return 0;
    }

    int migrated = 0;
    for (final entry in entries) {
      try {
        final ok = await _migrateEntry(entry);
        if (ok) migrated++;
      } catch (e) {
        debugPrint('[迁移] 失败: ${entry.id}, $e');
        // 单条失败不阻塞后续，但不标记完成，下次启动重试
      }
    }

    // 只有全部条目都有了 tosKey 才标记完成
    final remaining = await _storage.getEntriesWithoutTos();
    if (remaining.isEmpty) {
      await _markDone();
    }

    return migrated;
  }

  /// 迁移单条日记，返回是否实际执行了上传。
  Future<bool> _migrateEntry(DiaryEntry entry) async {
    final folder = entry.folderPath;
    final wavPath = p.join(folder, 'audio.wav');
    final oggPath = p.join(folder, 'audio.ogg');
    final hasWav = await File(wavPath).exists();
    final hasOgg = await File(oggPath).exists();

    if (hasWav) {
      // 旧格式：WAV → OGG 转码 → 上传
      // 仅在 OGG 不存在时才转码（避免重复转码）
      if (!hasOgg) {
        await _convertWavToOgg(wavPath, oggPath);
      }
      final tosKey = await _tos.uploadAudio(oggPath, entry.id);
      await _storage.updateTosInfo(
        entry.id,
        tosKey: tosKey,
        audioFormat: 'wav',
      );
      return true;
    } else if (hasOgg) {
      // 新格式（录音已是 OGG，但 TOS 上传失败）：直接上传
      final tosKey = await _tos.uploadAudio(oggPath, entry.id);
      await _storage.updateTosInfo(
        entry.id,
        tosKey: tosKey,
        audioFormat: 'ogg',
      );
      return true;
    } else {
      // 音频文件不存在，标记为已处理避免每次启动重复检查
      await _storage.updateTosInfo(entry.id, tosKey: '', audioFormat: 'ogg');
      debugPrint('[迁移] 跳过: ${entry.id}, 音频文件不存在');
      return false;
    }
  }

  /// WAV 转 OGG：读取 WAV PCM 数据 → Opus 编码 → OGG 文件。
  Future<void> _convertWavToOgg(String wavPath, String oggPath) async {
    final wavBytes = await File(wavPath).readAsBytes();
    final pcmData = Uint8List.sublistView(wavBytes, 44);

    final encoder = AudioEncoderService();
    await encoder.start(oggPath);

    const frameSize = 1920;
    for (int offset = 0; offset < pcmData.length; offset += frameSize) {
      final end = offset + frameSize > pcmData.length
          ? pcmData.length
          : offset + frameSize;
      final frame = Uint8List.sublistView(pcmData, offset, end);
      await encoder.addPcmData(frame);
    }

    await encoder.stop();
  }

  Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_migratedKey, true);
  }
}

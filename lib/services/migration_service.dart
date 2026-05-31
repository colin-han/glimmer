import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'audio_encoder_service.dart';
import 'diary_storage_service.dart';
import '../models/diary_entry.dart';
import 'tos_upload_service.dart';

/// 历史数据迁移服务：将未上传的 WAV 文件转码为 OGG 并上传 TOS。
class MigrationService {
  final DiaryStorageService _storage;
  final TosUploadService _tos;

  MigrationService(this._storage, this._tos);

  /// 执行迁移，返回迁移的条目数量。
  /// 通过 tosKey 是否为 null 判断进度，支持中断恢复。
  Future<int> migrateUnuploadedEntries() async {
    final entries = await _storage.getEntriesWithoutTos();
    if (entries.isEmpty) return 0;

    int migrated = 0;
    for (final entry in entries) {
      try {
        await _migrateEntry(entry);
        migrated++;
      } catch (e) {
        // 单条失败不阻塞后续迁移
        print('[迁移] 失败: ${entry.id}, $e');
      }
    }
    return migrated;
  }

  Future<void> _migrateEntry(DiaryEntry entry) async {
    final wavPath = p.join(entry.folderPath, 'audio.wav');
    final wavFile = File(wavPath);
    if (!await wavFile.exists()) return;

    // WAV → OGG 转码
    final oggPath = p.join(entry.folderPath, 'audio.ogg');
    await _convertWavToOgg(wavPath, oggPath);

    // 上传 OGG 到 TOS
    final tosKey = await _tos.uploadAudio(oggPath, entry.id);

    // 更新数据库（保留原格式标记 'wav'）
    await _storage.updateTosInfo(entry.id,
        tosKey: tosKey, audioFormat: 'wav');
  }

  /// WAV 转 OGG：读取 WAV PCM 数据 → Opus 编码 → OGG 文件。
  Future<void> _convertWavToOgg(String wavPath, String oggPath) async {
    final wavBytes = await File(wavPath).readAsBytes();
    // 跳过 44 字节 WAV header，获取原始 PCM 数据
    final pcmData = Uint8List.sublistView(wavBytes, 44);

    final encoder = AudioEncoderService();
    await encoder.start(oggPath);

    // 按帧喂入（每帧 1920 bytes = 960 samples * 2 bytes * 1 channel）
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
}

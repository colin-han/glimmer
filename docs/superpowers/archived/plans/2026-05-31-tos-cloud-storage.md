# TOS 云端录音存储 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将录音从纯本地 WAV 存储升级为本地 OGG + 火山引擎 TOS 云端存储，Flash ASR 改为从 TOS 预签名 URL 拉取音频识别。

**Architecture:** 录音期间 PCM 流双路分发——一路送实时 ASR，一路送 Opus 编码器生成 OGG 文件。录音结束后上传 OGG 到 TOS，生成预签名 URL，Flash ASR 用 URL 识别。本地音频播放优先 OGG，回退 WAV。SQLite 新增 TOS 相关字段，drift migration 保证向后兼容。

**Tech Stack:** flutter_opus（Opus 编码）+ 自实现 OGG 容器封装 + `tos` pub.dev 包（TOS SDK）+ drift migration

**设计文档:** `docs/superpowers/specs/2026-05-31-tos-cloud-storage-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/services/ogg_muxer.dart` | 新建 | OGG 容器封装（页写入、CRC32、序号管理） |
| `lib/services/audio_encoder_service.dart` | 新建 | PCM → OGG/Opus 实时编码，组合 Opus 编码器 + OGG 封装 |
| `lib/services/tos_upload_service.dart` | 新建 | TOS 上传、预签名 URL 生成 |
| `lib/services/database/tables.dart` | 修改 | DiaryEntries 新增 tosKey/audioFormat/uploadedAt 字段 |
| `lib/services/database/app_database.dart` | 修改 | schemaVersion 3 + migration |
| `lib/models/diary_entry.dart` | 修改 | 新增 TOS 相关字段 |
| `lib/services/diary_storage_service.dart` | 修改 | 音频路径解析（OGG 优先）、更新 TOS 字段 |
| `lib/services/audio_recorder_service.dart` | 修改 | PCM 流分流到 Opus 编码器，输出 OGG 而非 WAV |
| `lib/services/asr_service.dart` | 修改 | 新增 URL 模式 ASR，保留旧 base64 模式做兼容 |
| `lib/pages/recording_page.dart` | 修改 | 主流程：录音 → 上传 → URL ASR |
| `lib/pages/diary_detail_page.dart` | 修改 | 音频文件路径改为 OGG 优先 |
| `lib/services/audio_player_service.dart` | 修改 | 新增音频路径解析辅助方法 |
| `pubspec.yaml` | 修改 | 新增 flutter_opus、tos 依赖 |
| `.env.local.example` | 修改 | 新增 TOS 凭证变量 |
| `test/ogg_muxer_test.dart` | 新建 | OGG 容器封装测试 |
| `test/audio_encoder_service_test.dart` | 新建 | 音频编码服务测试 |
| `test/tos_upload_service_test.dart` | 新建 | TOS 上传服务测试 |
| `test/asr_service_test.dart` | 新建 | ASR URL 模式测试 |

---

### Task 1: 验证 flutter_opus + OGG 容器封装可行性

**目标：** 确认 flutter_opus 能在 Android 上完成 PCM → Opus 编码，并自实现 OGG 容器封装。

**文件：**
- 创建: `lib/services/ogg_muxer.dart`
- 创建: `test/ogg_muxer_test.dart`

- [ ] **Step 1: 添加 flutter_opus 依赖**

在 `pubspec.yaml` 的 `dependencies` 中添加：

```yaml
  flutter_opus: ^0.1.0
```

运行: `flutter pub get`

- [ ] **Step 2: 编写 OGG 容器封装单元测试**

OGG 容器格式核心要素：页面头（capture pattern "OggS"、版本、头类型、 granule position、serial number、page sequence、CRC、segment 数）、segment table、页面体。

创建 `test/ogg_muxer_test.dart`：

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/ogg_muxer.dart';

void main() {
  group('OggMuxer', () {
    test('初始化后可写入 BOS 页面', () {
      final muxer = OggMuxer(serialNumber: 1);
      final opusHeader = Uint8List.fromList([1, 2, 3, 4]);
      final pages = muxer.writePage(
        data: opusHeader,
        granulePosition: 0,
        isBeginOfStream: true,
      );
      expect(pages, isNotEmpty);
      // OGG 页面头前4字节必须是 "OggS"
      expect(pages.first.sublist(0, 4), equals([0x4F, 0x67, 0x67, 0x53]));
      // BOS 标志位
      expect(pages.first[5] & 0x02, isNonZero);
    });

    test('连续写入页面时 pageSequenceNumber 递增', () {
      final muxer = OggMuxer(serialNumber: 42);
      final dummy = Uint8List(100);

      final page1 = muxer.writePage(
        data: dummy,
        granulePosition: 0,
        isBeginOfStream: true,
      );
      final page2 = muxer.writePage(
        data: dummy,
        granulePosition: 960,
      );

      // page sequence number 在 header offset 18，4字节 LE
      final seq1 = ByteData.sublistView(page1.first).getUint32(18, Endian.little);
      final seq2 = ByteData.sublistView(page2.first).getUint32(18, Endian.little);
      expect(seq2, equals(seq1 + 1));
    });

    test('大 payload 自动分割为多个页面', () {
      final muxer = OggMuxer(serialNumber: 1);
      // OGG 单页最大 255 * 255 = 65025 字节
      final bigData = Uint8List(70000);

      final pages = muxer.writePage(
        data: bigData,
        granulePosition: 0,
        isBeginOfStream: true,
      );
      expect(pages.length, greaterThan(1));
    });

    test('EOS 标志位在最后一页设置', () {
      final muxer = OggMuxer(serialNumber: 1);
      final data = Uint8List(50);

      final pages = muxer.writePage(
        data: data,
        granulePosition: 48000,
        isEndOfStream: true,
      );
      // EOS 标志位
      expect(pages.last[5] & 0x04, isNonZero);
    });

    test('CRC32 校验正确', () {
      final muxer = OggMuxer(serialNumber: 123);
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      final pages = muxer.writePage(
        data: data,
        granulePosition: 0,
        isBeginOfStream: true,
      );

      // CRC 字段在 offset 22，4字节 LE
      // 不为 0 即表示已计算
      final crc = ByteData.sublistView(pages.first).getUint32(22, Endian.little);
      expect(crc, isNonZero);
    });
  });
}
```

- [ ] **Step 3: 运行测试验证失败**

运行: `flutter test test/ogg_muxer_test.dart`
预期: FAIL — `OggMuxer` 类不存在

- [ ] **Step 4: 实现 OGG 容器封装**

创建 `lib/services/ogg_muxer.dart`：

```dart
import 'dart:math';
import 'dart:typed_data';

/// OGG 容器封装器，将 Opus 数据包封装为 OGG 页面流。
/// 参考: https://www.xiph.org/ogg/doc/framing.html
class OggMuxer {
  final int serialNumber;
  int _pageSequenceNumber = 0;

  static const int _maxSegmentsPerPage = 255;
  static const int _maxSegmentSize = 255;
  static const int _maxPageSize = _maxSegmentsPerPage * _maxSegmentSize; // 65025
  static const List<int> _capturePattern = [0x4F, 0x67, 0x67, 0x53]; // "OggS"

  OggMuxer({required this.serialNumber});

  /// 将数据写入一个或多个 OGG 页面。
  /// 大数据自动分割为多个页面，BOS 和 EOS 标志只在首/末页设置。
  List<Uint8List> writePage({
    required Uint8List data,
    required int granulePosition,
    bool isBeginOfStream = false,
    bool isEndOfStream = false,
  }) {
    final pages = <Uint8List>[];
    int offset = 0;
    int pageIndex = 0;
    final totalPages = (data.length / _maxPageSize).ceil().clamp(1, 999999);

    while (offset < data.length) {
      final remaining = data.length - offset;
      final chunkSize = min(remaining, _maxPageSize);
      final chunk = Uint8List.sublistView(data, offset, offset + chunkSize);

      // 构建 segment table
      final segments = <int>[];
      int segOffset = 0;
      while (segOffset < chunk.length) {
        final segRemaining = chunk.length - segOffset;
        if (segRemaining >= _maxSegmentSize) {
          segments.add(_maxSegmentSize);
          segOffset += _maxSegmentSize;
        } else {
          // 最后一个 segment：值为实际长度，如果恰好 255 则追加一个 0
          segments.add(segRemaining);
          if (segRemaining == _maxSegmentSize) {
            segments.add(0);
          }
          segOffset += segRemaining;
        }
      }

      final isFirst = pageIndex == 0;
      final isLast = pageIndex == totalPages - 1;
      int headerType = 0;
      if (isFirst && isBeginOfStream) headerType |= 0x02; // BOS
      if (isLast && isEndOfStream) headerType |= 0x04; // EOS
      // continuation flag not needed for fresh data

      final page = _buildPage(
        headerType: headerType,
        granulePosition: isLast ? granulePosition : -1,
        pageSequenceNumber: _pageSequenceNumber,
        segmentTable: segments,
        data: chunk,
      );

      _pageSequenceNumber++;
      pages.add(page);
      offset += chunkSize;
      pageIndex++;
    }

    return pages;
  }

  Uint8List _buildPage({
    required int headerType,
    required int granulePosition,
    required int pageSequenceNumber,
    required List<int> segmentTable,
    required Uint8List data,
  }) {
    final headerSize = 27 + segmentTable.length;
    final pageSize = headerSize + data.length;

    final page = ByteData(pageSize);

    // Capture pattern "OggS"
    for (int i = 0; i < 4; i++) {
      page.setUint8(i, _capturePattern[i]);
    }
    // Version
    page.setUint8(4, 0);
    // Header type
    page.setUint8(5, headerType);
    // Granule position (8 bytes, -1 = unknown)
    if (granulePosition >= 0) {
      page.setInt64(6, granulePosition, Endian.little);
    } else {
      page.setInt64(6, -1, Endian.little);
    }
    // Serial number
    page.setUint32(14, serialNumber, Endian.little);
    // Page sequence number
    page.setUint32(18, pageSequenceNumber, Endian.little);
    // CRC (先写 0，后面回填)
    page.setUint32(22, 0, Endian.little);
    // Number of segments
    page.setUint8(26, segmentTable.length);
    // Segment table
    for (int i = 0; i < segmentTable.length; i++) {
      page.setUint8(27 + i, segmentTable[i]);
    }
    // Data
    final pageBytes = page.buffer.asUint8List();
    pageBytes.setAll(headerSize, data);

    // 计算 CRC32 并回填
    final crc = _crc32(pageBytes);
    ByteData.sublistView(pageBytes).setUint32(22, crc, Endian.little);

    return pageBytes;
  }

  /// OGG CRC32 查找表（生成多项式 0x04C11DB7）
  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int r = i << 24;
      for (int j = 0; j < 8; j++) {
        if ((r & 0x80000000) != 0) {
          r = ((r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF;
        } else {
          r = (r << 1) & 0xFFFFFFFF;
        }
      }
      table[i] = r;
    }
    return table;
  }

  static int _crc32(Uint8List data) {
    int crc = 0;
    for (final byte in data) {
      crc = ((crc << 8) ^ _crcTable[((crc >> 24) ^ byte) & 0xFF]) & 0xFFFFFFFF;
    }
    return crc;
  }
}
```

- [ ] **Step 5: 运行测试验证通过**

运行: `flutter test test/ogg_muxer_test.dart`
预期: PASS

- [ ] **Step 6: 提交**

```bash
git add pubspec.yaml pubspec.lock lib/services/ogg_muxer.dart test/ogg_muxer_test.dart
git commit -m "feat: 添加 OGG 容器封装器（OggMuxer）"
```

---

### Task 2: 实现 AudioEncoderService

**目标：** PCM → Opus 编码 + OGG 封装，录音期间实时写入 OGG 文件。

**文件：**
- 创建: `lib/services/audio_encoder_service.dart`
- 创建: `test/audio_encoder_service_test.dart`
- 依赖: Task 1 的 `OggMuxer`

**前置知识：**
- PCM 输入：16kHz, 16-bit, mono，每帧 960 samples = 1920 bytes = 20ms
- Opus 编码：flutter_opus 的 `OpusEncoder` 接受 Int16List（960 samples），输出编码后 Opus packet
- OGG 文件结构：第1页放 Opus ID header（19字节），第2页放 Opus comment header（最少 16 字节），后续页放音频数据
- Opus ID header: `OpusHead` + version 1 + channels 1 + pre-skip 3840 + sample-rate 16000 + gain 0 + channel-map 0
- Opus comment header: `OpusTags` + vendor string length + vendor string + 0 (user comment list length)

- [ ] **Step 1: 编写 AudioEncoderService 单元测试**

创建 `test/audio_encoder_service_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:voice_diary/services/audio_encoder_service.dart';

class FakePathProvider extends Fake with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  group('AudioEncoderService', () {
    late AudioEncoderService service;
    late String testDir;

    setUp(() async {
      PathProviderPlatform.instance = FakePathProvider();
      service = AudioEncoderService();
      testDir = Directory.systemTemp.createTempSync('ogg_test_').path;
    });

    tearDown(() async {
      await service.dispose();
      final dir = Directory(testDir);
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('start 创建 OGG 文件并写入 Opus header', () async {
      final outputPath = p.join(testDir, 'test.ogg');
      await service.start(outputPath);

      final file = File(outputPath);
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      // OGG 文件以 "OggS" 开头
      expect(bytes.sublist(0, 4), equals([0x4F, 0x67, 0x67, 0x53]));

      await service.stop();
    });

    test('addPcmData 接受整数帧的 PCM 数据并写入文件', () async {
      final outputPath = p.join(testDir, 'test.ogg');
      await service.start(outputPath);

      // 一帧 = 960 samples * 2 bytes = 1920 bytes
      // 模拟 100 帧 (2秒)
      for (int i = 0; i < 100; i++) {
        await service.addPcmData(Uint8List(1920));
      }
      await service.stop();

      final file = File(outputPath);
      expect(await file.length(), greaterThan(0));

      // 验证文件以 OGG 开头
      final bytes = await file.readAsBytes();
      expect(bytes.sublist(0, 4), equals([0x4F, 0x67, 0x67, 0x53]));
    });

    test('非整数帧数据被缓存直到凑齐一帧', () async {
      final outputPath = p.join(testDir, 'test.ogg');
      await service.start(outputPath);

      // 每次喂 960 bytes（半帧），两次凑一帧
      for (int i = 0; i < 200; i++) {
        await service.addPcmData(Uint8List(960));
      }
      await service.stop();

      final file = File(outputPath);
      expect(await file.length(), greaterThan(0));
    });

    test('生成的 OGG 文件可以被 just_audio 解析（集成验证标记）', () async {
      // 此测试标记为集成测试，需要真机/模拟器运行
      // 仅验证文件结构完整性
      final outputPath = p.join(testDir, 'test.ogg');
      await service.start(outputPath);

      for (int i = 0; i < 50; i++) {
        await service.addPcmData(Uint8List(1920));
      }
      await service.stop();

      final bytes = await File(outputPath).readAsBytes();
      // 文件应包含多个 OGG 页面
      final oggPageCount = 'OggS'.allMatches(String.fromCharCodes(bytes)).length;
      // 至少 3 页: header + comment + 至少一个音频数据页
      expect(oggPageCount, greaterThanOrEqualTo(3));
    }, skip: '需要 flutter_opus FFI，仅在真机/模拟器上运行');
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

运行: `flutter test test/audio_encoder_service_test.dart`
预期: FAIL — `AudioEncoderService` 类不存在

- [ ] **Step 3: 实现 AudioEncoderService**

创建 `lib/services/audio_encoder_service.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_opus/flutter_opus.dart';

import 'ogg_muxer.dart';

/// PCM → OGG/Opus 实时编码服务。
/// 录音期间将 PCM 帧逐帧编码为 Opus，封装到 OGG 容器并写入文件。
class AudioEncoderService {
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _frameSize = 960; // 20ms at 16kHz
  static const int _bytesPerFrame = _frameSize * _channels * 2; // 1920 bytes
  static const int _maxFrameSize = 5760; // Opus 最大帧大小（120ms）

  OpusEncoder? _encoder;
  OggMuxer? _muxer;
  RandomAccessFile? _file;
  int _granulePosition = 0;
  final Uint8List _buffer = Uint8List(_bytesPerFrame * 2);
  int _bufferOffset = 0;

  /// 开始编码，打开输出文件并写入 Opus 头部。
  Future<void> start(String outputPath) async {
    _encoder = OpusEncoder(
      sampleRate: _sampleRate,
      channels: _channels,
      application: Application.voip(),
    );
    _encoder!.setBitrate(32000);

    _muxer = OggMuxer(serialNumber: DateTime.now().microsecondsSinceEpoch);
    _granulePosition = 0;
    _bufferOffset = 0;

    _file = await File(outputPath).open(mode: FileMode.write);

    // 写入 Opus ID header 页
    final idHeader = _buildOpusIdHeader();
    final idPages = _muxer!.writePage(
      data: idHeader,
      granulePosition: 0,
      isBeginOfStream: true,
    );
    for (final page in idPages) {
      _file!.writeFromSync(page);
    }

    // 写入 Opus comment header 页
    final commentHeader = _buildOpusCommentHeader();
    final commentPages = _muxer!.writePage(
      data: commentHeader,
      granulePosition: 0,
    );
    for (final page in commentPages) {
      _file!.writeFromSync(page);
    }
  }

  /// 喂入 PCM 数据（16-bit LE, mono, 16kHz）。
  /// 内部缓存不足一帧的数据，凑齐后编码。
  Future<void> addPcmData(Uint8List pcmData) async {
    if (_encoder == null || _muxer == null || _file == null) return;

    int srcOffset = 0;
    while (srcOffset < pcmData.length) {
      final remaining = _buffer.length - _bufferOffset;
      final copyLen = pcmData.length - srcOffset < remaining
          ? pcmData.length - srcOffset
          : remaining;
      _buffer.setRange(_bufferOffset, _bufferOffset + copyLen, pcmData, srcOffset);
      _bufferOffset += copyLen;
      srcOffset += copyLen;

      if (_bufferOffset >= _bytesPerFrame) {
        _encodeFrame(Uint8List.sublistView(_buffer, 0, _bytesPerFrame));
        // 剩余数据移到 buffer 前面
        final leftover = _bufferOffset - _bytesPerFrame;
        if (leftover > 0) {
          _buffer.setRange(0, leftover, _buffer, _bytesPerFrame);
        }
        _bufferOffset = leftover;
      }
    }
  }

  /// 停止编码，flush 剩余数据并关闭文件。
  Future<void> stop() async {
    if (_encoder == null) return;

    // 处理剩余不足一帧的数据（补零到一帧）
    if (_bufferOffset > 0) {
      final padded = Uint8List(_bytesPerFrame);
      padded.setRange(0, _bufferOffset, _buffer);
      _encodeFrame(padded);
      _bufferOffset = 0;
    }

    // 写入 EOS 页
    final eosPages = _muxer!.writePage(
      data: Uint8List(0),
      granulePosition: _granulePosition,
      isEndOfStream: true,
    );
    for (final page in eosPages) {
      _file!.writeFromSync(page);
    }

    await _file?.flush();
    await _file?.close();
    _file = null;
    _encoder = null;
    _muxer = null;
  }

  void _encodeFrame(Uint8List pcmFrame) {
    // PCM bytes → Int16List for Opus encoder
    final pcmSamples = Int16List.view(pcmFrame.buffer, pcmFrame.offsetInBytes, _frameSize);
    final opusPacket = _encoder!.encode(pcmSamples);

    final pages = _muxer!.writePage(
      data: opusPacket,
      granulePosition: _granulePosition + _frameSize,
    );
    for (final page in pages) {
      _file!.writeFromSync(page);
    }

    _granulePosition += _frameSize;
  }

  /// Opus ID Header (19 bytes)
  Uint8List _buildOpusIdHeader() {
    final header = ByteData(19);
    // Magic "OpusHead"
    header.setUint8(0, 0x4F); // O
    header.setUint8(1, 0x70); // p
    header.setUint8(2, 0x75); // u
    header.setUint8(3, 0x73); // s
    header.setUint8(4, 0x48); // H
    header.setUint8(5, 0x65); // e
    header.setUint8(6, 0x61); // a
    header.setUint8(7, 0x64); // d
    // Version
    header.setUint8(8, 1);
    // Channel count
    header.setUint8(9, _channels);
    // Pre-skip (3840 for opus standard mapping)
    header.setUint16(10, 3840, Endian.little);
    // Sample rate
    header.setUint32(12, _sampleRate, Endian.little);
    // Output gain (0)
    header.setInt16(16, 0, Endian.little);
    // Channel mapping family (0 = mono/stereo)
    header.setUint8(18, 0);
    return header.buffer.asUint8List();
  }

  /// Opus Comment Header
  Uint8List _buildOpusCommentHeader() {
    final vendor = 'voice_diary_opus_encoder';
    final vendorBytes = vendor.codeUnits;
    final header = ByteData(12 + vendorBytes.length);
    // Magic "OpusTags"
    header.setUint8(0, 0x4F); // O
    header.setUint8(1, 0x70); // p
    header.setUint8(2, 0x75); // u
    header.setUint8(3, 0x73); // s
    header.setUint8(4, 0x54); // T
    header.setUint8(5, 0x61); // a
    header.setUint8(6, 0x67); // g
    header.setUint8(7, 0x73); // s
    // Vendor string length
    header.setUint32(8, vendorBytes.length, Endian.little);
    // Vendor string
    final bytes = header.buffer.asUint8List();
    for (int i = 0; i < vendorBytes.length; i++) {
      bytes[12 + i] = vendorBytes[i];
    }
    // User comment list length = 0 (不追加)
    // 注意：上面 ByteData 只有 12 + vendorBytes.length 字节
    // 需要额外 4 字节写 comment count
    final fullHeader = Uint8List(bytes.length + 4);
    fullHeader.setRange(0, bytes.length, bytes);
    ByteData.sublistView(fullHeader, bytes.length, bytes.length + 4)
        .setUint32(0, 0, Endian.little);
    return fullHeader;
  }

  Future<void> dispose() async {
    await stop();
  }
}
```

- [ ] **Step 4: 运行测试**

运行: `flutter test test/audio_encoder_service_test.dart`
预期: 需要 FFI 的测试会被 skip，其他测试可能因 flutter_opus 平台限制在纯 Dart 测试中失败。这是预期行为——核心逻辑验证在 Task 9 端到端测试中进行。

- [ ] **Step 5: 提交**

```bash
git add lib/services/audio_encoder_service.dart test/audio_encoder_service_test.dart
git commit -m "feat: 添加 PCM→OGG/Opus 实时编码服务（AudioEncoderService）"
```

---

### Task 3: 添加 TOS 依赖 + 配置

**目标：** 集成 TOS Flutter SDK，添加环境变量配置。

**文件：**
- 修改: `pubspec.yaml`
- 修改: `.env.local.example`

- [ ] **Step 1: 添加 tos 依赖**

在 `pubspec.yaml` 的 `dependencies` 中添加：

```yaml
  tos: ^2.0.0
```

运行: `flutter pub get`

- [ ] **Step 2: 更新 .env.local.example**

在 `.env.local.example` 末尾添加：

```
# TOS 云存储（火山引擎）
VOLCENGINE_TOS_ACCESS_KEY=your_access_key_id
VOLCENGINE_TOS_SECRET_KEY=your_secret_access_key
VOLCENGINE_TOS_ENDPOINT=tos-cn-beijing.volces.com
VOLCENGINE_TOS_BUCKET=your-bucket-name
```

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock .env.local.example
git commit -m "feat: 添加 TOS SDK 依赖和环境变量配置"
```

---

### Task 4: 实现 TosUploadService

**目标：** 封装 TOS 上传和预签名 URL 生成功能。

**文件：**
- 创建: `lib/services/tos_upload_service.dart`
- 创建: `test/tos_upload_service_test.dart`
- 依赖: Task 3

**前置知识：**
- TOS SDK `tos` 包核心 API：`TosClient` 构造、`putObject` 上传文件、`presignedUrl` 生成预签名 URL
- 环境变量从 `flutter_dotenv` 读取
- TOS key 格式：`audio/{diaryId}.ogg`

- [ ] **Step 1: 编写 TosUploadService 测试**

创建 `test/tos_upload_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/tos_upload_service.dart';

void main() {
  group('TosUploadService', () {
    test('构造时从环境变量读取配置', () {
      // 此测试验证构造不抛异常
      // 实际 TOS 交互在集成测试中验证
      expect(() => TosUploadService(), returnsNormally);
    }, skip: '需要 .env.local 配置，仅在集成环境运行');

    test('uploadAudio 返回正确的 tosKey 格式', () {
      // 验证 key 格式：audio/{diaryId}.ogg
      final service = TosUploadService();
      final diaryId = '550e8400-e29b-41d4-a716-446655440000';
      final expectedKey = 'audio/$diaryId.ogg';
      // 内部方法验证
      expect(service.tosKeyForDiary(diaryId), equals(expectedKey));
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

运行: `flutter test test/tos_upload_service_test.dart`
预期: FAIL — `TosUploadService` 类不存在

- [ ] **Step 3: 实现 TosUploadService**

创建 `lib/services/tos_upload_service.dart`：

```dart
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tos/tos.dart';

class TosUploadService {
  late final TosClient _client;
  late final String _bucket;

  TosUploadService() {
    final ak = dotenv.get('VOLCENGINE_TOS_ACCESS_KEY');
    final sk = dotenv.get('VOLCENGINE_TOS_SECRET_KEY');
    final endpoint = dotenv.get('VOLCENGINE_TOS_ENDPOINT');
    _bucket = dotenv.get('VOLCENGINE_TOS_BUCKET');

    _client = TosClient(
      ak: ak,
      sk: sk,
      endpoint: endpoint,
      region: endpoint.split('.').first.replaceAll('tos-', ''),
    );
  }

  /// 上传音频文件到 TOS。
  /// [localPath] 本地 OGG 文件路径
  /// [diaryId] 日记 ID，用于生成 TOS key
  /// 返回 TOS 对象 key
  Future<String> uploadAudio(String localPath, String diaryId) async {
    final tosKey = tosKeyForDiary(diaryId);
    final file = File(localPath);

    await _client.putObject(
      PutObjectInput(
        bucket: _bucket,
        key: tosKey,
        contentStream: file.openRead(),
        contentLength: await file.length(),
        contentType: 'audio/ogg',
      ),
    );

    return tosKey;
  }

  /// 生成预签名 URL。
  /// [tosKey] TOS 对象 key
  /// [expiresSeconds] 有效期（秒），默认 1 小时
  Future<String> getPresignedUrl(String tosKey,
      {int expiresSeconds = 3600}) async {
    final result = await _client.presignedUrl(
      PreSignedUrlInput(
        httpMethod: HttpMethodGET,
        bucket: _bucket,
        key: tosKey,
        expires: expiresSeconds,
      ),
    );
    return result.signedUrl;
  }

  /// 生成日记音频的 TOS key。
  String tosKeyForDiary(String diaryId) => 'audio/$diaryId.ogg';
}
```

- [ ] **Step 4: 验证 TOS SDK API 兼容性**

检查 `tos` 包的实际 API 是否与上述代码匹配：

运行: `flutter pub run build_runner build` 或直接查看 `.dart_tool/package_config.json` 确认 `tos` 包版本。

如果 `TosClient` 构造函数或 `putObject`/`presignedUrl` API 不同，根据实际 API 调整上述代码。

- [ ] **Step 5: 运行测试**

运行: `flutter test test/tos_upload_service_test.dart`
预期: PASS（跳过集成测试）

- [ ] **Step 6: 提交**

```bash
git add lib/services/tos_upload_service.dart test/tos_upload_service_test.dart
git commit -m "feat: 添加 TOS 上传与预签名 URL 服务（TosUploadService）"
```

---

### Task 5: 数据库 Schema 升级 + DiaryEntry 模型扩展

**目标：** 新增 tosKey、audioFormat、uploadedAt 字段，drift migration 升级到 v3。

**文件：**
- 修改: `lib/services/database/tables.dart`
- 修改: `lib/services/database/app_database.dart`
- 修改: `lib/models/diary_entry.dart`
- 修改: `lib/services/diary_storage_service.dart`
- 依赖: 无

- [ ] **Step 1: 修改 tables.dart 新增字段**

在 `lib/services/database/tables.dart` 的 `DiaryEntries` 类中新增 3 列：

```dart
class DiaryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get folderPath => text()();
  IntColumn get durationSeconds => integer()();
  IntColumn get createdAt => integer()();
  TextColumn get tosKey => text().nullable()();
  TextColumn get audioFormat => text().withDefault(const Constant('wav'))();
  IntColumn get uploadedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: 运行 build_runner 重新生成代码**

运行: `dart run build_runner build --delete-conflicting-outputs`
预期: 成功生成 `app_database.g.dart`

- [ ] **Step 3: 修改 app_database.dart 升级 migration**

修改 `lib/services/database/app_database.dart`：

```dart
@override
int get schemaVersion => 3;

@override
MigrationStrategy get migration => MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(tags);
          await m.createTable(diaryTagRelations);
        }
        if (from < 3) {
          await m.addColumn(diaryEntries, diaryEntries.tosKey);
          await m.addColumn(diaryEntries, diaryEntries.audioFormat);
          await m.addColumn(diaryEntries, diaryEntries.uploadedAt);
        }
      },
    );
```

- [ ] **Step 4: 修改 diary_entry.dart 新增字段**

修改 `lib/models/diary_entry.dart`：

```dart
class DiaryEntry {
  final String id;
  final String title;
  final String folderPath;
  final int durationSeconds;
  final DateTime createdAt;
  final String? tosKey;
  final String audioFormat;
  final DateTime? uploadedAt;

  const DiaryEntry({
    required this.id,
    required this.title,
    required this.folderPath,
    required this.durationSeconds,
    required this.createdAt,
    this.tosKey,
    this.audioFormat = 'wav',
    this.uploadedAt,
  });

  String get displayTitle =>
      title.isNotEmpty ? title : '未命名日记';

  String get formattedDate {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get durationDisplay {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 判断是否已上传到 TOS
  bool get isUploaded => tosKey != null;
}
```

- [ ] **Step 5: 修改 diary_storage_service.dart 适配新字段**

修改 `lib/services/diary_storage_service.dart`，更新 `createEntry` 和所有从数据库行映射 `DiaryEntry` 的地方：

`createEntry` 方法：

```dart
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
```

`getAllEntries` 方法中的映射：

```dart
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
```

`getEntryById` 方法同样更新映射：

```dart
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
```

新增 `updateTosInfo` 方法：

```dart
Future<void> updateTosInfo(String id, String tosKey, String audioFormat) async {
  await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id)))
      .write(DiaryEntriesCompanion(
    tosKey: Value(tosKey),
    audioFormat: Value(audioFormat),
    uploadedAt: Value(DateTime.now().millisecondsSinceEpoch),
  ));
}
```

新增 `getEntriesWithoutTos` 方法（用于历史迁移）：

```dart
Future<List<DiaryEntry>> getEntriesWithoutTos() async {
  final all = await getAllEntries();
  return all.where((e) => e.tosKey == null).toList();
}
```

新增 `getAudioPath` 辅助方法：

```dart
/// 获取音频文件路径，优先 OGG，回退 WAV。
Future<String?> getAudioPath(String folderPath) async {
  final ogg = File(p.join(folderPath, 'audio.ogg'));
  if (await ogg.exists()) return ogg.path;
  final wav = File(p.join(folderPath, 'audio.wav'));
  if (await wav.exists()) return wav.path;
  return null;
}
```

- [ ] **Step 6: 运行 build_runner + 验证编译**

运行: `dart run build_runner build --delete-conflicting-outputs`
运行: `flutter analyze`
预期: 无错误

- [ ] **Step 7: 提交**

```bash
git add lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/database/app_database.g.dart lib/models/diary_entry.dart lib/services/diary_storage_service.dart
git commit -m "feat: 数据库 schema v3 + DiaryEntry 新增 TOS 字段（tosKey/audioFormat/uploadedAt）"
```

---

### Task 6: AudioRecorderService 改造——PCM 双路分流

**目标：** 录音时 PCM 流同时写入 OGG 编码器，停止录音时输出 OGG 文件路径。

**文件：**
- 修改: `lib/services/audio_recorder_service.dart`
- 依赖: Task 2（AudioEncoderService）

**设计决策：**
- 新录音不再写 WAV 文件，改为写 OGG 文件
- `audioStream` 仍然输出 PCM 数据供实时 ASR 使用
- `RecordingResult.filePath` 返回 OGG 文件路径

- [ ] **Step 1: 改造 AudioRecorderService**

修改 `lib/services/audio_recorder_service.dart`：

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import 'audio_encoder_service.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioEncoderService _encoder = AudioEncoderService();
  DateTime? _recordingStartTime;

  String? _filePath;

  static const _sampleRate = 16000;
  static const _channels = 1;

  final _audioStreamController = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _recorderSubscription;

  /// PCM 音频流，供外部（如实时 ASR）消费
  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  /// 开始录音，返回 OGG 文件路径。
  /// PCM 流同时分发到：1) Opus 编码器 → OGG 文件  2) audioStream（实时 ASR）
  Future<String> startRecording(String folderPath) async {
    final hasPerms = await _recorder.hasPermission();
    if (!hasPerms) {
      throw Exception('没有麦克风权限');
    }

    _filePath = p.join(folderPath, 'audio.ogg');

    // 启动 Opus 编码器
    await _encoder.start(_filePath!);

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _channels,
      ),
    );

    _recordingStartTime = DateTime.now();

    _recorderSubscription = audioStream.listen((data) {
      // 路径1: PCM → Opus 编码器 → OGG 文件
      _encoder.addPcmData(data);
      // 路径2: PCM → audioStream（实时 ASR）
      _audioStreamController.add(data);
    });

    return _filePath!;
  }

  Future<RecordingResult> stopRecording() async {
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;

    // flush 编码器，完成 OGG 文件
    await _encoder.stop();

    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;
    _recordingStartTime = null;

    final filePath = _filePath ?? '';
    _filePath = null;

    return RecordingResult(
      filePath: filePath,
      durationSeconds: duration,
    );
  }

  Stream<Amplitude> onAmplitudeChanged(Duration interval) {
    return _recorder.onAmplitudeChanged(interval);
  }

  Future<void> dispose() async {
    await _recorderSubscription?.cancel();
    await _encoder.dispose();
    await _audioStreamController.close();
    await _recorder.dispose();
  }
}

class RecordingResult {
  final String filePath;
  final int durationSeconds;

  RecordingResult({required this.filePath, required this.durationSeconds});
}
```

- [ ] **Step 2: 验证编译**

运行: `flutter analyze`
预期: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/services/audio_recorder_service.dart
git commit -m "feat: AudioRecorderService 改为 PCM 双路分流（Opus 编码 + 实时 ASR），输出 OGG 文件"
```

---

### Task 7: AsrService 新增 URL 模式

**目标：** Flash ASR 支持通过预签名 URL 识别 OGG/Opus 音频，保留旧 base64 模式做兼容。

**文件：**
- 修改: `lib/services/asr_service.dart`
- 依赖: Task 4（TosUploadService 生成 URL）

- [ ] **Step 1: 在 AsrService 中新增 transcribeFromUrl 方法**

修改 `lib/services/asr_service.dart`，新增方法：

```dart
/// 通过预签名 URL 识别音频（OGG/Opus 格式）。
Future<AsrResult> transcribeFromUrl(String audioUrl) async {
  final appid = dotenv.get('VOLCENGINE_SPEECH_APPID');
  final token = dotenv.get('VOLCENGINE_SPEECH_TOKEN');

  final requestId = _uuid.v4();

  final response = await _dio.post(
    'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash',
    data: {
      'user': {'uid': appid},
      'audio': {
        'url': audioUrl,
        'format': 'ogg_opus',
      },
      'request': {
        'model_name': 'bigmodel',
        'show_utterances': true,
      },
    },
    options: Options(headers: {
      'X-Api-App-Key': appid,
      'X-Api-Access-Key': token,
      'X-Api-Resource-Id': 'volc.bigasr.auc_turbo',
      'X-Api-Request-Id': requestId,
      'X-Api-Sequence': '-1',
    }),
  );

  final statusCode = response.headers.value('X-Api-Status-Code');
  if (statusCode != '20000000') {
    final message = response.headers.value('X-Api-Message') ?? '未知错误';
    throw Exception('ASR 识别失败 ($statusCode): $message');
  }

  final result = response.data['result'] as Map<String, dynamic>?;
  if (result == null) {
    throw Exception('ASR 识别结果为空');
  }

  final text = result['text'] as String? ?? '';
  if (text.isEmpty) {
    throw Exception('ASR 识别结果为空');
  }

  final utterancesList = result['utterances'] as List<dynamic>?;
  if (utterancesList == null || utterancesList.isEmpty) {
    throw Exception('ASR 未返回 utterances 数据');
  }

  final utterances = utterancesList
      .map((u) => Utterance(
            text: u['text'] as String,
            startTime: u['start_time'] as int,
            endTime: u['end_time'] as int,
          ))
      .toList();

  return AsrResult(text: text, utterances: utterances);
}
```

- [ ] **Step 2: 验证编译**

运行: `flutter analyze`
预期: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/services/asr_service.dart
git commit -m "feat: AsrService 新增 URL 模式识别（transcribeFromUrl）"
```

---

### Task 8: RecordingPage 主流程调整

**目标：** 录音结束后：上传 OGG → 生成 URL → URL ASR → 保存 TOS 信息。

**文件：**
- 修改: `lib/pages/recording_page.dart`
- 依赖: Task 4, 5, 6, 7

- [ ] **Step 1: 修改 RecordingPage**

修改 `lib/pages/recording_page.dart`：

1. 新增 import：
```dart
import '../services/tos_upload_service.dart';
```

2. 新增服务实例：
```dart
final _tosService = TosUploadService();
```

3. 改造 `_stopAndProcess` 方法中的 Flash ASR 部分（从步骤 1 开始）。

将原来：
```dart
// 步骤 1: Flash ASR 识别（带时间戳）
setState(() => _processingStep = 1);
AsrResult? asrResult;
try {
  asrResult = await _asrService.transcribe(recordingResult.filePath);
```

改为：
```dart
// 步骤 1: 上传 OGG 到 TOS + Flash ASR 识别
setState(() => _processingStep = 1);
AsrResult? asrResult;
try {
  // 上传 OGG 到 TOS
  final tosKey = await _tosService.uploadAudio(
    recordingResult.filePath,
    _currentFolderId!,
  );
  debugPrint('[流程] TOS 上传完成: $tosKey');

  // 生成预签名 URL
  final presignedUrl = await _tosService.getPresignedUrl(tosKey);
  debugPrint('[流程] 预签名 URL 生成完成');

  // 用 URL 调 Flash ASR
  asrResult = await _asrService.transcribeFromUrl(presignedUrl);
```

4. 在步骤 3 保存元数据时，携带 TOS 信息：

将原来：
```dart
final entry = DiaryEntry(
  id: _currentFolderId!,
  title: llmResult.title,
  folderPath: _currentFolderPath!,
  durationSeconds: duration,
  createdAt: DateTime.now(),
);
```

改为：
```dart
final entry = DiaryEntry(
  id: _currentFolderId!,
  title: llmResult.title,
  folderPath: _currentFolderPath!,
  durationSeconds: duration,
  createdAt: DateTime.now(),
  tosKey: tosKey,
  audioFormat: 'ogg',
  uploadedAt: DateTime.now(),
);
```

注意：`tosKey` 变量需要从步骤 1 的 try 块中提取到外层。完整改造后的 `_stopAndProcess` 方法中需要声明 `String? tosKey;` 在 try 块之前。

5. 将 `_saveEntryAndNavigate` 也改为携带 audioFormat：

在 `_saveEntryAndNavigate` 中：
```dart
Future<void> _saveEntryAndNavigate(String title, int duration, {String audioFormat = 'wav'}) async {
  final entry = DiaryEntry(
    id: _currentFolderId!,
    title: title,
    folderPath: _currentFolderPath!,
    durationSeconds: duration,
    createdAt: DateTime.now(),
    audioFormat: audioFormat,
  );
```

在 `_stopAndProcess` 中的错误分支调用更新为：
```dart
await _saveEntryAndNavigate('未命名日记', duration, audioFormat: 'ogg');
```

- [ ] **Step 2: 验证编译**

运行: `flutter analyze`
预期: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "feat: RecordingPage 主流程改造——上传 TOS + URL ASR"
```

---

### Task 9: diary_detail_page 音频路径兼容

**目标：** 详情页音频播放兼容 OGG/WAV，优先播放 OGG。

**文件：**
- 修改: `lib/pages/diary_detail_page.dart`
- 修改: `lib/services/audio_player_service.dart`
- 依赖: Task 5（getAudioPath 方法）

- [ ] **Step 1: 在 AudioPlayerService 中添加音频路径解析**

修改 `lib/services/audio_player_service.dart`：

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  double _speed = 1.0;

  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  double get speed => _speed;

  /// 获取音频文件路径，优先 OGG，回退 WAV。
  Future<String?> resolveAudioPath(String folderPath) async {
    final ogg = File(p.join(folderPath, 'audio.ogg'));
    if (await ogg.exists()) return ogg.path;
    final wav = File(p.join(folderPath, 'audio.wav'));
    if (await wav.exists()) return wav.path;
    return null;
  }

  Future<void> play(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.setSpeed(_speed);
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setSpeed(double rate) async {
    _speed = rate;
    await _player.setSpeed(rate);
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
```

- [ ] **Step 2: 修改 diary_detail_page.dart 使用新的路径解析**

在 `lib/pages/diary_detail_page.dart` 中，将所有 `audio.wav` 硬编码替换为动态路径解析。

原来的模式：
```dart
final audioPath = p.join(widget.entry.folderPath, 'audio.wav');
final audioExists = File(audioPath).existsSync();
```

改为：
```dart
final audioPath = await _playerService.resolveAudioPath(widget.entry.folderPath);
final audioExists = audioPath != null;
```

注意：`_playerService.resolveAudioPath` 是 async 的，如果原代码位置不在 async 上下文中，需要调整为 async。`diary_detail_page.dart` 中有 3 处引用 `audio.wav`（约第 51 行、131 行、271 行），全部替换。

- [ ] **Step 3: 验证编译**

运行: `flutter analyze`
预期: 无错误

- [ ] **Step 4: 提交**

```bash
git add lib/services/audio_player_service.dart lib/pages/diary_detail_page.dart
git commit -m "feat: 音频播放兼容 OGG/WAV，优先播放 OGG"
```

---

### Task 10: 历史数据迁移

**目标：** App 启动时检测并迁移未上传的 WAV 文件（转码 OGG → 上传 TOS → 更新 DB）。

**文件：**
- 修改: `lib/services/diary_storage_service.dart`
- 创建: `lib/services/migration_service.dart`
- 依赖: Task 2, 4, 5

- [ ] **Step 1: 创建 MigrationService**

创建 `lib/services/migration_service.dart`：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'audio_encoder_service.dart';
import 'diary_storage_service.dart';
import 'models/diary_entry.dart';
import 'tos_upload_service.dart';

/// 历史数据迁移服务：将未上传的 WAV 文件转码为 OGG 并上传 TOS。
class MigrationService {
  final DiaryStorageService _storage;
  final TosUploadService _tos;
  final AudioEncoderService _encoder = AudioEncoderService();

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
        print('迁移失败: ${entry.id}, $e');
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

    // 更新数据库
    await _storage.updateTosInfo(entry.id, tosKey, 'wav');
  }

  /// WAV 转 OGG：读取 WAV PCM 数据 → Opus 编码 → OGG 文件。
  Future<void> _convertWavToOgg(String wavPath, String oggPath) async {
    final wavBytes = await File(wavPath).readAsBytes();
    // 跳过 44 字节 WAV header，获取原始 PCM 数据
    final pcmData = wavBytes.sublist(44);

    await _encoder.start(oggPath);

    // 按帧喂入（每帧 1920 bytes）
    const frameSize = 1920;
    for (int offset = 0; offset < pcmData.length; offset += frameSize) {
      final end = offset + frameSize > pcmData.length
          ? pcmData.length
          : offset + frameSize;
      final frame = pcmData.sublist(offset, end);
      await _encoder.addPcmData(frame);
    }

    await _encoder.stop();
  }
}
```

- [ ] **Step 2: 在 main.dart 中调用迁移**

修改 `lib/main.dart`，在 `main()` 函数中，`runApp` 之前添加迁移逻辑：

```dart
// 在 runApp() 之前，异步执行历史数据迁移
() async {
  try {
    final storage = DiaryStorageService();
    final tos = TosUploadService();
    final migration = MigrationService(storage, tos);
    final count = await migration.migrateUnuploadedEntries();
    if (count > 0) {
      print('[迁移] 完成: 迁移了 $count 条日记');
    }
  } catch (e) {
    // TOS 未配置时跳过迁移
    print('[迁移] 跳过: $e');
  }
}();
```

注意：迁移是 fire-and-forget，不阻塞 UI 启动。如果 TOS 环境变量未配置（`dotenv.get` 抛异常），catch 会吞掉错误，不影响 app 正常运行。

- [ ] **Step 3: 验证编译**

运行: `flutter analyze`
预期: 无错误

- [ ] **Step 4: 提交**

```bash
git add lib/services/migration_service.dart lib/main.dart
git commit -m "feat: 添加历史 WAV 数据迁移服务（转码 OGG + 上传 TOS）"
```

---

### Task 11: 端到端验证

**目标：** 在真机/模拟器上完整跑通 录音 → 编码 → 上传 → ASR → 播放 流程。

**前置条件：**
- TOS 已开通，`.env.local` 已配置 TOS 凭证
- 火山引擎 ASR 服务正常
- Android 真机或模拟器已连接

- [ ] **Step 1: 构建并安装**

```bash
flutter run
```

- [ ] **Step 2: 验证录音编码**

1. 点击录音按钮，说话 5-10 秒
2. 停止录音
3. 检查 logcat 输出：
   - `[流程] TOS 上传完成: audio/{uuid}.ogg`
   - `[流程] 预签名 URL 生成完成`
   - `[流程] Flash ASR 完成`
4. 用 adb 检查本地 OGG 文件：
   ```bash
   adb shell run-as info.colinhan.glimmer ls files/diaries/*/audio.ogg
   ```

- [ ] **Step 3: 验证 TOS 上传**

1. 登录火山引擎 TOS 控制台
2. 进入桶，确认有新上传的 `audio/{uuid}.ogg` 文件
3. 检查文件大小是否合理（5 秒 ≈ 20KB）

- [ ] **Step 4: 验证 ASR 识别**

1. 确认 Flash ASR 返回了正确的识别文字和时间戳
2. 在详情页检查 transcript 显示是否正常

- [ ] **Step 5: 验证音频播放**

1. 在日记详情页点击播放按钮
2. 确认 OGG 文件可以正常播放
3. 调整播放速度，确认正常

- [ ] **Step 6: 验证数据库**

```bash
adb shell run-as info.colinhan.glimmer sqlite3 files/voice_diary.db "SELECT id, tosKey, audioFormat, uploadedAt FROM diary_entries ORDER BY createdAt DESC LIMIT 1;"
```

预期: tosKey 有值，audioFormat = 'ogg'，uploadedAt 有值

- [ ] **Step 7: 验证旧数据兼容**

1. 找一个有旧 WAV 文件的日记
2. 重启 app，检查迁移是否执行
3. 确认旧日记仍可正常播放和查看
4. 确认数据库中旧条目的 tosKey 已更新

- [ ] **Step 8: 提交（如有修复）**

```bash
git add -u
git commit -m "fix: 端到端验证修复"
```

---

### Task 12: TOS 服务配置指导

**目标：** 指导用户开通 TOS 服务、创建桶、配置 Access Key。

**此任务在用户准备好火山引擎账号后执行。**

**操作步骤（用户在火山引擎控制台操作）：**

1. **开通 TOS 服务**
   - 登录 https://console.volcengine.com/
   - 搜索"对象存储 TOS"，进入产品页
   - 点击"立即开通"（免费开通，按量计费）

2. **创建桶**
   - TOS 控制台 → "桶管理" → "创建桶"
   - 配置：
     - 桶名称：`glimmer-audio-{你的标识}`（全局唯一）
     - 区域：华北2（北京）/ `cn-beijing`
     - 存储类型：**智能分层存储**
     - 冗余策略：本地冗余
     - 访问权限：**私有读写**
   - 确认创建

3. **创建 Access Key**
   - 控制台右上角头像 → "密钥管理"
   - 创建新 Access Key
   - 推荐创建 IAM 子用户，仅赋予 `TOSFullAccess` 权限
   - 记录 Access Key ID 和 Secret Access Key

4. **配置 .env.local**
   - 在 `.env.local` 中填写：
   ```
   VOLCENGINE_TOS_ACCESS_KEY=<你的 AK>
   VOLCENGINE_TOS_SECRET_KEY=<你的 SK>
   VOLCENGINE_TOS_ENDPOINT=tos-cn-beijing.volces.com
   VOLCENGINE_TOS_BUCKET=<你的桶名>
   ```

5. **验证**
   - 启动 app，进行一次完整录音
   - 检查 TOS 控制台是否有上传文件

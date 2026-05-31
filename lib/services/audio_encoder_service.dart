import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_opus/flutter_opus.dart';

import 'ogg_muxer.dart';

/// PCM → OGG/Opus 实时编码服务。
/// 录音期间将 PCM 帧逐帧编码为 Opus，封装到 OGG 容器并写入文件。
///
/// 输入规格：16kHz, 16-bit LE, mono
/// 每帧 960 samples = 1920 bytes = 20ms
class AudioEncoderService {
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _frameSize = 960; // 20ms at 16kHz
  static const int _bytesPerFrame = _frameSize * _channels * 2; // 1920 bytes

  OpusEncoder? _encoder;
  OggMuxer? _muxer;
  RandomAccessFile? _file;
  int _granulePosition = 0;
  final Uint8List _buffer = Uint8List(_bytesPerFrame * 2);
  int _bufferOffset = 0;

  /// 开始编码，打开输出文件并写入 Opus 头部。
  Future<void> start(String outputPath) async {
    _encoder = OpusEncoder.create(
      sampleRate: _sampleRate,
      channels: _channels,
      application: 2048, // OPUS_APPLICATION_VOIP
    );
    if (_encoder == null) {
      throw StateError('创建 Opus 编码器失败');
    }
    _encoder!.setBitrate(32000);

    _muxer = OggMuxer(serialNumber: DateTime.now().microsecondsSinceEpoch);
    _granulePosition = 0;
    _bufferOffset = 0;

    _file = await File(outputPath).open(mode: FileMode.write);

    // 写入 Opus ID header 页（BOS）
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
      _buffer.setRange(
          _bufferOffset, _bufferOffset + copyLen, pcmData, srcOffset);
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

    // 写入 EOS 页（空数据，标记流结束）
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
    _encoder?.dispose();
    _encoder = null;
    _muxer = null;
  }

  void _encodeFrame(Uint8List pcmFrame) {
    // PCM bytes → Int16List for Opus encoder
    final pcmSamples = Int16List.view(
        pcmFrame.buffer, pcmFrame.offsetInBytes, _frameSize);
    final opusPacket = _encoder!.encode(pcmSamples, _frameSize);
    if (opusPacket == null) {
      throw StateError('Opus 编码失败');
    }

    final pages = _muxer!.writePage(
      data: opusPacket,
      granulePosition: _granulePosition + _frameSize,
    );
    for (final page in pages) {
      _file!.writeFromSync(page);
    }

    _granulePosition += _frameSize;
  }

  /// 构建 Opus ID Header（19 字节）。
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

  /// 构建 Opus Comment Header。
  Uint8List _buildOpusCommentHeader() {
    const vendor = 'voice_diary_opus_encoder';
    final vendorBytes = vendor.codeUnits;
    // "OpusTags" (8) + vendor_length (4) + vendor (N) + comment_count (4)
    final header = Uint8List(8 + 4 + vendorBytes.length + 4);
    final bd = ByteData.sublistView(header);
    // Magic "OpusTags"
    bd.setUint8(0, 0x4F);
    bd.setUint8(1, 0x70);
    bd.setUint8(2, 0x75);
    bd.setUint8(3, 0x73);
    bd.setUint8(4, 0x54);
    bd.setUint8(5, 0x61);
    bd.setUint8(6, 0x67);
    bd.setUint8(7, 0x73);
    // Vendor string length
    bd.setUint32(8, vendorBytes.length, Endian.little);
    // Vendor string
    for (int i = 0; i < vendorBytes.length; i++) {
      header[12 + i] = vendorBytes[i];
    }
    // User comment list length = 0
    bd.setUint32(12 + vendorBytes.length, 0, Endian.little);
    return header;
  }

  /// 释放资源（等同 stop，可安全重复调用）。
  Future<void> dispose() async {
    await stop();
  }
}

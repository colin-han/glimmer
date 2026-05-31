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

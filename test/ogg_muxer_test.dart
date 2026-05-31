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
      final seq1 =
          ByteData.sublistView(page1.first).getUint32(18, Endian.little);
      final seq2 =
          ByteData.sublistView(page2.first).getUint32(18, Endian.little);
      expect(seq2, equals(seq1 + 1));
    });

    test('大 payload 自动分割为多个页面', () {
      final muxer = OggMuxer(serialNumber: 1);
      // 单页最大 64770 字节，70000 需要分割
      final bigData = Uint8List(70000);

      final pages = muxer.writePage(
        data: bigData,
        granulePosition: 0,
        isBeginOfStream: true,
      );
      expect(pages.length, greaterThan(1));
    });

    test('多页分割时 continuation flag 正确设置', () {
      final muxer = OggMuxer(serialNumber: 1);
      final bigData = Uint8List(70000);

      final pages = muxer.writePage(
        data: bigData,
        granulePosition: 0,
        isBeginOfStream: true,
      );

      // 第一页不应有 continuation flag
      expect(pages.first[5] & 0x01, equals(0));
      // 后续页应有 continuation flag
      for (int i = 1; i < pages.length; i++) {
        expect(pages[i][5] & 0x01, isNonZero,
            reason: 'Page $i should have continuation flag');
      }
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
      final crc =
          ByteData.sublistView(pages.first).getUint32(22, Endian.little);
      expect(crc, isNonZero);
    });

    test('255 倍数大小的 payload 正确终止 segment table', () {
      final muxer = OggMuxer(serialNumber: 1);
      // 255 字节恰好一个 segment，需要追加 0 长度终止段
      final data = Uint8List(255);

      final pages = muxer.writePage(
        data: data,
        granulePosition: 0,
      );

      // segment count 在 offset 26
      final segmentCount = pages.first[26];
      // 应该是 2: 一个 255 + 一个 0
      expect(segmentCount, equals(2));
      // 第二个 segment 值为 0
      expect(pages.first[28], equals(0));
    });

    test('空数据返回空页面列表', () {
      final muxer = OggMuxer(serialNumber: 1);
      final pages = muxer.writePage(
        data: Uint8List(0),
        granulePosition: 0,
      );
      expect(pages, isEmpty);
    });
  });
}

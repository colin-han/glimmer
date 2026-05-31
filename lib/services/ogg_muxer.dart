import 'dart:math';
import 'dart:typed_data';

/// OGG 容器封装器，将 Opus 数据包封装为 OGG 页面流。
/// 参考: https://www.xiph.org/ogg/doc/framing.html
class OggMuxer {
  final int serialNumber;
  int _pageSequenceNumber = 0;

  static const int _maxSegmentsPerPage = 255;
  static const int _maxSegmentSize = 255;
  static const int _maxPageSize =
      _maxSegmentsPerPage * _maxSegmentSize; // 65025
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
      crc =
          ((crc << 8) ^ _crcTable[((crc >> 24) ^ byte) & 0xFF]) & 0xFFFFFFFF;
    }
    return crc;
  }
}

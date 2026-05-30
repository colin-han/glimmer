import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordingStartTime;

  IOSink? _fileSink;
  String? _filePath;
  int _dataSize = 0;
  static const _sampleRate = 16000;
  static const _bitsPerSample = 16;
  static const _channels = 1;
  static const _byteRate = _sampleRate * _channels * _bitsPerSample ~/ 8;
  static const _blockAlign = _channels * _bitsPerSample ~/ 8;

  final _audioStreamController = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _recorderSubscription;

  /// PCM 音频流，供外部（如实时 ASR）消费
  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  /// 开始录音，返回 WAV 文件路径
  /// 同时通过 audioStream 输出 PCM 数据
  Future<String> startRecording(String folderPath) async {
    final hasPerms = await _recorder.hasPermission();
    if (!hasPerms) {
      throw Exception('没有麦克风权限');
    }

    _filePath = p.join(folderPath, 'audio.wav');
    _dataSize = 0;

    // 创建 WAV 文件，写入 header（先写占位，结束时回写大小）
    final file = File(_filePath!);
    final raf = file.openSync(mode: FileMode.write);
    _writeWavHeader(raf, 0);
    await raf.close();

    _fileSink = file.openWrite(mode: FileMode.append);

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _channels,
      ),
    );

    _recordingStartTime = DateTime.now();

    _recorderSubscription = audioStream.listen((data) {
      // 写入本地 WAV 文件
      _fileSink!.add(data);
      _dataSize += data.length;

      // 输出给外部消费
      _audioStreamController.add(data);
    });

    return _filePath!;
  }

  Future<RecordingResult> stopRecording() async {
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;

    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;

    // 回写 WAV header 中的文件大小
    if (_filePath != null) {
      final file = File(_filePath!);
      if (await file.exists()) {
        final raf = await file.open(mode: FileMode.writeOnlyAppend);
        await raf.setPosition(4);
        await raf.writeFrom(_uint32Bytes(36 + _dataSize));
        await raf.setPosition(40);
        await raf.writeFrom(_uint32Bytes(_dataSize));
        await raf.close();
      }
    }

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
    await _fileSink?.close();
    await _audioStreamController.close();
    await _recorder.dispose();
  }

  void _writeWavHeader(RandomAccessFile raf, int dataSize) {
    final header = ByteData(44);
    // RIFF
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataSize, Endian.little); // file size - 8
    // WAVE
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, _channels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _byteRate, Endian.little);
    header.setUint16(32, _blockAlign, Endian.little);
    header.setUint16(34, _bitsPerSample, Endian.little);
    // data
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    raf.writeFromSync(header.buffer.asUint8List());
  }

  Uint8List _uint32Bytes(int value) {
    final bd = ByteData(4);
    bd.setUint32(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }
}

class RecordingResult {
  final String filePath;
  final int durationSeconds;

  RecordingResult({required this.filePath, required this.durationSeconds});
}

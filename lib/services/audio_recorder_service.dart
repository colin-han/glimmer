import 'dart:async';
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

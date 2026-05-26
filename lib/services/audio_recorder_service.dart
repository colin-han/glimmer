import 'package:path/path.dart' as p;
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordingStartTime;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<String> startRecording(String folderPath) async {
    final hasPerms = await hasPermission();
    if (!hasPerms) {
      throw Exception('没有麦克风权限');
    }

    final filePath = p.join(folderPath, 'audio.m4a');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: filePath,
    );
    _recordingStartTime = DateTime.now();
    return filePath;
  }

  Future<RecordingResult> stopRecording() async {
    final filePath = await _recorder.stop();
    if (filePath == null) {
      throw Exception('录音失败');
    }
    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;
    _recordingStartTime = null;
    return RecordingResult(
      filePath: filePath,
      durationSeconds: duration,
    );
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

class RecordingResult {
  final String filePath;
  final int durationSeconds;

  RecordingResult({required this.filePath, required this.durationSeconds});
}

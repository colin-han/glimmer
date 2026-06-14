# 实时语音识别改造实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将语音日记 App 从离线 Flash ASR 改造为录音时实时展示识别文本（WebSocket 流式 ASR + Flash 兜底）。

**Architecture:** 新建 RealtimeAsrService 封装火山引擎 v3 大模型双向流式 WebSocket 协议。改造 AudioRecorderService 使用 `startStream()` 同时输出 PCM 流给 ASR 和写入本地 WAV 文件。RecordingPage 增加实时文本展示区域。

**Tech Stack:** Flutter, Dart web_socket_channel, record 7.x (startStream), dio

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/services/realtime_asr_service.dart` | 新建 | WebSocket 连接、二进制帧协议、音频发送、结果解析 |
| `lib/services/audio_recorder_service.dart` | 改造 | `startStream()` 替换 `start()`，PCM 流分流给 ASR + 写 WAV |
| `lib/pages/recording_page.dart` | 改造 | 集成实时 ASR，增加实时文本 UI，处理步骤 3→4 |
| `lib/widgets/step_progress_indicator.dart` | 改造 | 步骤标签从 3 步改为 4 步 |
| `pubspec.yaml` | 改造 | 添加 web_socket_channel 依赖 |
| `.env.local.example` | 改造 | 更新环境变量说明 |

---

### Task 1: 添加 WebSocket 依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 添加 web_socket_channel 依赖**

在 `pubspec.yaml` 的 `dependencies` 中，`dio: ^5.7.0` 下方添加：

```yaml
  web_socket_channel: ^3.0.1
```

- [ ] **Step 2: 安装依赖**

Run: `flutter pub get`
Expected: 依赖安装成功，无报错

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "添加 web_socket_channel 依赖"
```

---

### Task 2: 实现 RealtimeAsrService

**Files:**
- Create: `lib/services/realtime_asr_service.dart`

这个服务封装火山引擎 v3 大模型双向流式 WebSocket 协议。协议使用自定义二进制帧格式（4 字节帧头 + payload），音频为 PCM 16kHz 16bit 单声道。

帧头格式：
```
Byte 0: [Protocol version=0b0001 (4bit)] [Header size=0b0001 (4bit)]
Byte 1: [Message type (4bit)] [Message type flags (4bit)]
Byte 2: [Serialization=0b0001 for JSON, 0b0000 for raw (4bit)] [Compression=0b0000 (4bit)]
Byte 3: [Reserved=0]
```

Message types:
- `0b0001` = 完整客户端请求（配置 JSON）
- `0b0010` = 仅音频客户端请求
- `0b1001` = 服务端响应（识别结果）
- `0b1111` = 服务端错误

Message flags:
- `0b0001` = 带正序列号
- `0b0010` = 最后一包（无序列号）

- [ ] **Step 1: 创建 RealtimeAsrService 文件**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeAsrService {
  static const _wsUrl =
      'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async';

  WebSocketChannel? _channel;
  final _uuid = const Uuid();
  int _sequence = 0;

  final _partialResultsController = StreamController<String>.broadcast();
  final _completer = Completer<String>();
  String _accumulatedText = '';
  bool _connected = false;

  /// 实时中间结果流
  Stream<String> get onPartialResult => _partialResultsController.stream;

  /// 是否已连接
  bool get isConnected => _connected;

  /// 建立 WebSocket 连接并发送配置帧
  Future<void> connect() async {
    final appid = dotenv.get('VOLCENGINE_SPEECH_APPID');
    final token = dotenv.get('VOLCENGINE_SPEECH_TOKEN');
    final connectId = _uuid.v4();

    final uri = Uri.parse(_wsUrl);
    _channel = WebSocketChannel.connect(
      uri,
      protocols: [],
    );

    // 等待连接 ready
    await _channel!.ready;

    // 发送配置帧
    final configPayload = jsonEncode({
      'user': {'uid': appid},
      'audio': {
        'format': 'pcm',
        'codec': 'raw',
        'rate': 16000,
        'bits': 16,
        'channel': 1,
      },
      'request': {
        'model_name': 'bigmodel',
        'enable_itn': true,
        'enable_punc': true,
        'show_utterances': true,
      },
    });

    final configFrame = _buildFrame(
      messageType: 0x0001, // 完整客户端请求
      flags: 0x0001, // 带序列号
      serialization: 0x0001, // JSON
      sequence: 1,
      payload: utf8.encode(configPayload),
    );
    _channel!.sink.add(configFrame);
    _sequence = 1;

    // 监听响应
    _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );

    _connected = true;
  }

  /// 发送一帧音频数据
  void sendAudio(Uint8List pcmData) {
    if (!_connected || _channel == null) return;
    _sequence++;
    final frame = _buildFrame(
      messageType: 0x0002, // 仅音频
      flags: 0x0001, // 带正序列号
      serialization: 0x0000, // 无序列化（原始字节）
      sequence: _sequence,
      payload: pcmData,
    );
    _channel!.sink.add(frame);
  }

  /// 发送最后一帧，标记结束
  void sendLastFrame() {
    if (!_connected || _channel == null) return;
    final frame = _buildFrame(
      messageType: 0x0002, // 仅音频
      flags: 0x0002, // 最后一包，无序列号
      serialization: 0x0000,
      sequence: 0,
      payload: Uint8List(0),
    );
    _channel!.sink.add(frame);
  }

  /// 获取最终识别结果的 Future
  Future<String> get finalResult => _completer.future;

  /// 断开连接
  void disconnect() {
    _connected = false;
    _channel?.sink.close();
    _channel = null;
    if (!_completer.isCompleted) {
      _completer.complete(_accumulatedText);
    }
  }

  void _onData(dynamic data) {
    if (data is! List<int>) return;
    final bytes = Uint8List.fromList(data);
    if (bytes.length < 4) return;

    final byte0 = bytes[0];
    final messageType = (byte0 >> 0) & 0x0F;
    // byte0 高 4 位是 protocol version，低 4 位是 header size

    // 忽略：byte1 是 message type + flags, byte2 是 serialization + compression

    if (messageType == 0x0009) {
      // 服务端响应
      _handleServerResponse(bytes);
    } else if (messageType == 0x000F) {
      // 服务端错误
      _handleServerError(bytes);
    }
  }

  void _handleServerResponse(Uint8List bytes) {
    // 服务端响应帧格式：[4字节帧头] [4字节序列号] [4字节payload长度] [payload]
    if (bytes.length < 12) return;

    // 读取 payload
    final payloadLength = _readUint32(bytes, 8);
    if (bytes.length < 12 + payloadLength) return;

    final payloadBytes = bytes.sublist(12, 12 + payloadLength);
    final payloadJson = jsonDecode(utf8.decode(payloadBytes))
        as Map<String, dynamic>;

    final result = payloadJson['result'] as Map<String, dynamic>?;
    if (result == null) return;

    final text = result['text'] as String? ?? '';
    _accumulatedText = text;

    final utterances = result['utterances'] as List<dynamic>?;
    if (utterances != null && utterances.isNotEmpty) {
      final lastUtterance = utterances.last as Map<String, dynamic>;
      final definite = lastUtterance['definite'] as bool? ?? false;
      if (!definite) {
        // 中间结果
        _partialResultsController.add(text);
      }
    } else {
      // 没有 utterances 时也推送
      _partialResultsController.add(text);
    }
  }

  void _handleServerError(Uint8List bytes) {
    if (bytes.length < 8) return;
    final errorCode = _readUint32(bytes, 4);
    String message = '未知错误';
    if (bytes.length > 8) {
      final msgLen = bytes.length - 8;
      message = utf8.decode(bytes.sublist(8, 8 + msgLen));
    }
    if (!_completer.isCompleted) {
      _completer.completeError(Exception('ASR 错误 ($errorCode): $message'));
    }
    disconnect();
  }

  void _onError(Object error) {
    _connected = false;
    if (!_completer.isCompleted) {
      _completer.completeError(error);
    }
  }

  void _onDone() {
    _connected = false;
    if (!_completer.isCompleted) {
      _completer.complete(_accumulatedText);
    }
  }

  Uint8List _buildFrame({
    required int messageType,
    required int flags,
    required int serialization,
    required int sequence,
    required List<int> payload,
  }) {
    // 客户端请求帧：[4字节帧头] [4字节序列号] [4字节payload长度] [payload]
    final header = ByteData(4);
    header.setUint8(0, 0x11); // version=1, headerSize=1 (4 bytes)
    header.setUint8(
      1,
      (messageType << 4) | flags,
    );
    header.setUint8(
      2,
      (serialization << 4) | 0x00, // 无压缩
    );
    header.setUint8(3, 0x00); // reserved

    final buf = BytesBuilder();
    buf.add(header.buffer.asUint8List());

    if (flags == 0x0002) {
      // 最后一包，无序列号
      buf.add(_uint32Bytes(0)); // sequence = 0
    } else {
      buf.add(_uint32Bytes(sequence));
    }

    buf.add(_uint32Bytes(payload.length));
    buf.add(payload);

    return buf.toBytes();
  }

  int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  Uint8List _uint32Bytes(int value) {
    final bd = ByteData(4);
    bd.setUint32(0, value);
    return bd.buffer.asUint8List();
  }
}
```

- [ ] **Step 2: 运行代码分析确认无语法错误**

Run: `flutter analyze lib/services/realtime_asr_service.dart`
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/services/realtime_asr_service.dart
git commit -m "添加 RealtimeAsrService（WebSocket 实时 ASR）"
```

---

### Task 3: 改造 AudioRecorderService

**Files:**
- Modify: `lib/services/audio_recorder_service.dart`

核心改动：`start()` → `startStream()`，PCM 流同时写入 WAV 文件和输出给外部消费。

`startStream()` 返回 `Future<Stream<Uint8List>>`，是广播流。`stop()` 不再返回文件路径（返回 null），需要自行跟踪。

WAV 文件 header 为 44 字节，结构：
```
RIFF (4B) | file_size-8 (4B) | WAVE (4B)
fmt  (4B) | 16 (4B) | format=1 (2B) | channels (2B) | sampleRate (4B) | byteRate (4B) | blockAlign (2B) | bitsPerSample (2B)
data (4B) | data_size (4B) | [PCM data...]
```

录音结束时需要回写文件大小字段（offset 4 的 file_size 和 offset 40 的 data_size）。

- [ ] **Step 1: 重写 AudioRecorderService**

将 `lib/services/audio_recorder_service.dart` 完整替换为：

```dart
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
```

- [ ] **Step 2: 运行代码分析确认无语法错误**

Run: `flutter analyze lib/services/audio_recorder_service.dart`
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/services/audio_recorder_service.dart
git commit -m "改造 AudioRecorderService 使用 startStream 双轨输出"
```

---

### Task 4: 改造 StepProgressIndicator（3 步 → 4 步）

**Files:**
- Modify: `lib/widgets/step_progress_indicator.dart`

处理步骤从 3 步改为 4 步：语音识别 → 保存原文 → AI 总结 → 完成。

- [ ] **Step 1: 更新步骤标签**

将 `step_progress_indicator.dart` 第 13 行：

```dart
  static const _steps = ['语音识别', 'AI 总结', '保存'];
```

改为：

```dart
  static const _steps = ['语音识别', '保存原文', 'AI 总结', '完成'];
```

- [ ] **Step 2: 运行代码分析**

Run: `flutter analyze lib/widgets/step_progress_indicator.dart`
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/step_progress_indicator.dart
git commit -m "StepProgressIndicator 步骤从 3 步改为 4 步"
```

---

### Task 5: 改造 RecordingPage

**Files:**
- Modify: `lib/pages/recording_page.dart`

核心改动：
1. 引入 RealtimeAsrService，录音时连接 WebSocket
2. PCM 流同时送给 RealtimeAsrService
3. 实时文本显示在波形图下方
4. 停止后走 Flash ASR 兜底 → LLM → 保存（4 步）
5. 错误处理：WebSocket 失败不阻塞录音

- [ ] **Step 1: 重写 RecordingPage**

将 `lib/pages/recording_page.dart` 完整替换为：

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/diary_entry.dart';
import '../services/asr_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';
import '../services/realtime_asr_service.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/recording_button.dart';
import '../widgets/step_progress_indicator.dart';
import 'diary_detail_page.dart';
import 'diary_list_page.dart';

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final _recorderService = AudioRecorderService();
  final _storageService = DiaryStorageService();
  final _asrService = AsrService();
  final _llmService = LlmService();
  final _realtimeAsr = RealtimeAsrService();
  final _uuid = const Uuid();

  RecordingState _state = RecordingState.idle;
  int _recordingSeconds = 0;
  Timer? _timer;
  String? _currentFolderId;
  String? _currentFolderPath;
  Stream<Amplitude>? _amplitudeStream;
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  StreamSubscription<String>? _partialResultSubscription;

  int _processingStep = 0;
  bool _hasError = false;
  String _errorMessage = '';

  String _realtimeText = '';

  @override
  void dispose() {
    _timer?.cancel();
    _audioStreamSubscription?.cancel();
    _partialResultSubscription?.cancel();
    _recorderService.dispose();
    _realtimeAsr.disconnect();
    super.dispose();
  }

  void _startTimer() {
    _recordingSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= 300) {
        _stopAndProcess();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _onTap() async {
    switch (_state) {
      case RecordingState.idle:
        await _startRecording();
      case RecordingState.recording:
        await _stopAndProcess();
      case RecordingState.processing:
        break;
    }
  }

  Future<void> _startRecording() async {
    try {
      _currentFolderId = _uuid.v4();
      _currentFolderPath =
          await _storageService.createDiaryFolder(_currentFolderId!);

      final filePath =
          await _recorderService.startRecording(_currentFolderPath!);
      _amplitudeStream =
          _recorderService.onAmplitudeChanged(const Duration(milliseconds: 80));

      // 连接实时 ASR（失败不阻塞录音）
      _connectRealtimeAsr();

      // 监听 PCM 流，发送给实时 ASR
      _audioStreamSubscription =
          _recorderService.audioStream.listen((pcmData) {
        if (_realtimeAsr.isConnected) {
          _realtimeAsr.sendAudio(pcmData);
        }
      });

      setState(() => _state = RecordingState.recording);
      _startTimer();
    } catch (e) {
      _showError('录音启动失败：$e');
    }
  }

  void _connectRealtimeAsr() {
    _realtimeAsr.connect().catchError((e) {
      // WebSocket 连接失败，不阻塞录音
      debugPrint('实时 ASR 连接失败: $e');
    });

    _partialResultSubscription =
        _realtimeAsr.onPartialResult.listen((text) {
      if (mounted) {
        setState(() => _realtimeText = text);
      }
    });
  }

  Future<void> _stopAndProcess() async {
    _stopTimer();
    _amplitudeStream = null;

    // 停止实时 ASR
    _realtimeAsr.sendLastFrame();
    _realtimeAsr.disconnect();
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _partialResultSubscription?.cancel();
    _partialResultSubscription = null;

    final duration = _recordingSeconds;

    setState(() {
      _state = RecordingState.processing;
      _processingStep = 0;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final recordingResult = await _recorderService.stopRecording();

      // 步骤 1: Flash ASR 兜底识别
      setState(() => _processingStep = 1);
      final transcript =
          await _asrService.transcribe(recordingResult.filePath);
      await _storageService.writeTranscript(
          _currentFolderPath!, transcript);

      // 步骤 2: LLM 润色
      setState(() => _processingStep = 2);
      final llmResult = await _llmService.summarize(transcript);
      await _storageService.writeSummary(
          _currentFolderPath!, llmResult.content);

      // 步骤 3: 保存元数据
      setState(() => _processingStep = 3);
      final entry = DiaryEntry(
        id: _currentFolderId!,
        title: llmResult.title,
        folderPath: _currentFolderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
      );
      await _storageService.createEntry(entry);

      if (mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => DiaryDetailPage(entry: entry),
            ))
            .then((_) {
          setState(() {
            _state = RecordingState.idle;
            _hasError = false;
            _processingStep = 0;
            _recordingSeconds = 0;
            _realtimeText = '';
          });
        });
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语音日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DiaryListPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_state == RecordingState.processing) ...[
                StepProgressIndicator(
                  currentStep: _processingStep,
                  hasError: _hasError,
                ),
                const SizedBox(height: 32),
                if (_hasError)
                  Text(_errorMessage,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center)
                else
                  const Text('正在处理中...'),
                const SizedBox(height: 24),
              ],
              AudioWaveform(
                amplitudeStream: _amplitudeStream,
                color: _state == RecordingState.recording
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
              ),
              if (_realtimeText.isNotEmpty &&
                  _state == RecordingState.recording) ...[
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      _realtimeText,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              RecordingButton(
                state: _state,
                onTap: _onTap,
                recordingSeconds: _recordingSeconds,
              ),
              if (_hasError) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _state = RecordingState.idle;
                      _hasError = false;
                      _processingStep = 0;
                      _realtimeText = '';
                    });
                  },
                  child: const Text('重新开始'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 运行代码分析**

Run: `flutter analyze lib/pages/recording_page.dart`
Expected: 无错误

- [ ] **Step 3: 运行全量分析**

Run: `flutter analyze`
Expected: 无错误

- [ ] **Step 4: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "改造 RecordingPage 集成实时 ASR 和实时文本展示"
```

---

### Task 6: 更新 .env.local.example

**Files:**
- Modify: `.env.local.example`

现有环境变量 `VOLCENGINE_SPEECH_APPID` 和 `VOLCENGINE_SPEECH_TOKEN` 在实时 ASR 中复用（作为 `X-Api-App-Key` 和 `X-Api-Access-Key`），无需新增变量。但需要更新 example 文件的说明使其更清晰。

- [ ] **Step 1: 更新环境变量示例**

将 `.env.local.example` 内容更新为：

```
# ASR 语音识别（Flash ASR + 实时流式 ASR 共用）
VOLCENGINE_SPEECH_APPID=your_appid_here
VOLCENGINE_SPEECH_TOKEN=your_token_here

# LLM（豆包 Doubao）
VOLCENGINE_ARK_API_KEY=your_ark_api_key_here
VOLCENGINE_ARK_ENDPOINT_ID=your_endpoint_id_here
```

- [ ] **Step 2: 提交**

```bash
git add .env.local.example
git commit -m "更新 .env.local.example 环境变量说明"
```

---

### Task 7: 验证与清理

**Files:**
- 无新文件

- [ ] **Step 1: 运行全量代码分析**

Run: `flutter analyze`
Expected: 无错误、无警告

- [ ] **Step 2: 运行测试**

Run: `flutter test`
Expected: 所有测试通过

- [ ] **Step 3: 构建验证**

Run: `flutter build apk --debug`
Expected: 构建成功

- [ ] **Step 4: 最终提交**

如果没有需要修复的问题，此步骤无需操作。如果有修复，提交所有修改：

```bash
git add -A
git commit -m "修复实时 ASR 集成问题"
```

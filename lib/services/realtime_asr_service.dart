import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeAsrService {
  static const _wsUrl =
      'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async';

  WebSocketChannel? _channel;
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

/// 应用自定义异常体系。
///
/// 规范：需要抛出异常时，应按"用途"实现对应的派生类，
/// 禁止直接 `throw Exception('...')`，更不允许基于异常字符串内容
/// （如 `e.toString().contains(...)`）做判断——捕获方应按类型（on XxxException）区分。
library;

/// 所有自定义异常的基类。
class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

/// ASR 语音识别相关异常（接口失败、响应非法等）。
class AsrException extends AppException {
  /// ASR 服务返回的状态码（如 '20000004'），便于分类处理。
  final String? statusCode;
  const AsrException(super.message, {this.statusCode});

  @override
  String toString() =>
      statusCode != null ? 'ASR 识别失败 ($statusCode): $message' : message;
}

/// ASR 识别轮询超时。
class AsrTimeoutException extends AsrException {
  const AsrTimeoutException() : super('ASR 识别超时');
}

/// TTS 语音合成相关异常。
class TtsException extends AppException {
  /// TTS 服务返回的业务码（如 3000 表示成功）。
  final int? code;
  const TtsException(super.message, {this.code});

  @override
  String toString() => code != null ? 'TTS 错误 ($code): $message' : message;
}

/// 录音相关异常（启动失败、停止失败等）。
class RecordingException extends AppException {
  const RecordingException(super.message);
}

/// 日记处理流程中的内部异常（前置条件缺失、数据问题等）。
class ProcessingException extends AppException {
  const ProcessingException(super.message);
}

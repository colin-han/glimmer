/// main isolate 感知的 FGS 当前模式，用于「重新分析」等操作的并发判断
///（避免中断正在进行的录音）。
///
/// 注意：仅服务 main isolate；FGS isolate 有自己独立的 static，不共享
///（这正是所需的——drift 连接和 FGS callback 都不能跨 isolate）。
enum FgsMode { none, recording, processing }

class FgsRuntime {
  FgsRuntime._();

  static FgsMode mode = FgsMode.none;

  static void setRecording() => mode = FgsMode.recording;
  static void setProcessing() => mode = FgsMode.processing;
  static void setNone() => mode = FgsMode.none;
}

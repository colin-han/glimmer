/// 日记条目的处理阶段，表示"当前/下一个要执行的处理阶段"。
///
/// 含义是：当恢复处理时，应该从这个阶段开始执行。
/// 录制阶段不创建 DB 条目，因此没有 recording 值。
enum ProcessingStage {
  uploading('uploading'),
  asr('asr'),
  llm('llm'),
  tagging('tagging'),
  completed('completed');

  const ProcessingStage(this.value);
  final String value;

  static ProcessingStage fromString(String? value) {
    return ProcessingStage.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ProcessingStage.uploading,
    );
  }
}

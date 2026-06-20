/// 录音输入设备类型。
enum AudioInputType { builtin, bluetooth, wired }

/// 当前录音输入设备（由 Android native 通过 MethodChannel 返回）。
class AudioInputDevice {
  /// 设备类型（决定 emoji）。
  final AudioInputType type;

  /// 显示文本，如「内置麦克风」/「蓝牙耳机（AirPods）」/「有线耳机」。
  /// 由 native 端拼好（已含蓝牙设备名），Dart 透传。
  final String label;

  const AudioInputDevice({required this.type, required this.label});

  /// 设备对应 emoji。
  String get emoji => switch (type) {
    AudioInputType.builtin => '🎙',
    AudioInputType.bluetooth => '🎧',
    AudioInputType.wired => '🎧',
  };

  factory AudioInputDevice.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'builtin';
    final type = AudioInputType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => AudioInputType.builtin,
    );
    return AudioInputDevice(
      type: type,
      label: map['label'] as String? ?? '内置麦克风',
    );
  }
}

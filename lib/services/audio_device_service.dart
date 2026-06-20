import 'package:flutter/services.dart';

import '../models/audio_input_device.dart';

/// 查询当前录音输入设备（通过 MethodChannel 调 Android native）。
///
/// native 端（MainActivity.kt）注册同名的 MethodChannel
/// `info.colinhan.glimmer/audio_device`，处理 `getCurrentInputDevice`。
class AudioDeviceService {
  static const _channel = MethodChannel('info.colinhan.glimmer/audio_device');

  /// 返回当前录音输入设备；查询失败/不支持/未注册 handler 返回 null。
  Future<AudioInputDevice?> getCurrentInputDevice() async {
    try {
      final result = await _channel.invokeMethod<Map>('getCurrentInputDevice');
      if (result == null) return null;
      return AudioInputDevice.fromMap(result);
    } catch (_) {
      // MissingPluginException（非 Android）/ 平台错误 → 安静失败，不显示 pill
      return null;
    }
  }
}

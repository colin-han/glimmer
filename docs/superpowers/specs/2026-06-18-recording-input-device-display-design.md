# 录音时显示当前输入设备 — 设计

> 日期：2026-06-18
> 状态：设计中

## 1. 背景与目标

录音时让用户在界面上看到当前用的是哪个输入设备（麦克风），尤其蓝牙/有线耳机连接时确认录音源正确，避免「以为在用蓝牙耳机、其实在用手机麦」的情况。

**目标**：录音开始时，在录音按钮下方常驻显示当前输入设备（内置麦克风 / 蓝牙耳机（含设备名）/ 有线耳机），停止录音后消失。

## 2. 技术约束

- **record 插件限制**：`record` 7.1.0 的 `AudioRecorder` 有 `listInputDevices()`（列所有设备），但**没有** `getRecordingInputDevice`（当前录音设备）。
- **Android 路由限制**：录音设备由系统自动路由；`AudioRecord.getRoutedDevice()` 需要 AudioRecord 实例——record 插件的实例藏在内部不暴露，自建一个又会与正在录音的抢占麦克风冲突。故纯 `getRoutedDevice` 不可行。
- **精度上限**：能精确到「内置 / 蓝牙（含设备名）/ 有线」三类，到不了型号级路由（Android 系统限制，录音路由由 OS 管理）。

## 3. 方案：native MethodChannel

Kotlin 端（`MainActivity.kt`）注册 MethodChannel `info.colinhan.glimmer/audio_device`，用 `AudioManager` + 蓝牙状态判断当前录音源，返回给 Dart。

**为什么 native**：record 插件拿不到当前设备；Android 系统 API（AudioManager）在 Kotlin 调用最可靠，且能拿到蓝牙设备名。纯 Dart（`listInputDevices`）只能列所有设备，无法判断「当前正用的」。

## 4. native 判断逻辑（Kotlin，MainActivity.kt）

`configureFlutterEngine` 中注册 MethodChannel，handler 处理 `getCurrentInputDevice` 调用，按优先级判断：

1. **蓝牙耳机**：
   - `AudioManager.isBluetoothScoOn` 为 true，或 `BluetoothManager` 查到已连接 HEADSET/A2DP 设备 → type `bluetooth`。
   - 设备名：尝试取 `BluetoothDevice.name`；取不到则 label 不含名。
2. **有线耳机**：
   - `AudioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)` 含 `TYPE_WIRED_HEADSET` 或 `TYPE_WIRED_HEADPHONES` → type `wired`。
3. **内置麦克风**：兜底 type `builtin`。

返回 `Map<String, Any>`：
```json
{ "type": "builtin" | "bluetooth" | "wired", "label": "...", "name": "..." }
```
- `label`：`内置麦克风` / `蓝牙耳机` / `蓝牙耳机（AirPods）` / `有线耳机`。
- `name`：蓝牙设备名（仅 bluetooth，可空字符串）。

**权限策略**：
- 蓝牙状态优先用 `AudioManager.isBluetoothScoOn`（不需蓝牙权限）。
- 蓝牙设备名用 `BluetoothManager.getConnectedDevices(BluetoothProfile.HEADSET)` 取——API 31+ 需 `BLUETOOTH_CONNECT` 权限。若无该权限或调用失败，省略设备名（label 仅「蓝牙耳机」），不阻塞。
- 不新增 AndroidManifest 权限（避免为次要功能索取权限）；设备名是 nice-to-have，取不到就用无名版。

## 5. Dart model 与 service

### `lib/models/audio_input_device.dart`

```dart
enum AudioInputType { builtin, bluetooth, wired }

class AudioInputDevice {
  final AudioInputType type;
  final String label; // 内置麦克风 / 蓝牙耳机（AirPods） / 有线耳机

  const AudioInputDevice({required this.type, required this.label});

  String get emoji => switch (type) {
        AudioInputType.builtin => '🎙',
        AudioInputType.bluetooth => '🎧',
        AudioInputType.wired => '🎧',
      };

  factory AudioInputDevice.fromMap(Map map) {
    // type 字符串 → enum；label 直接用 native 返回（已含蓝牙名拼接）
    ...
  }
}
```

### `lib/services/audio_device_service.dart`

```dart
class AudioDeviceService {
  static const _channel = MethodChannel('info.colinhan.glimmer/audio_device');

  /// 查询当前录音输入设备。失败/不支持返回 null（UI 不显示）。
  Future<AudioInputDevice?> getCurrentInputDevice() async {
    try {
      final result = await _channel.invokeMethod<Map>('getCurrentInputDevice');
      if (result == null) return null;
      return AudioInputDevice.fromMap(result);
    } catch (_) {
      return null;
    }
  }
}
```

## 6. UI（`lib/pages/recording_page.dart`）

- State 加字段 `AudioInputDevice? _currentInputDevice`。
- `_doStartRecording` 成功后（setState `_state = recording` 之后）：调 `AudioDeviceService().getCurrentInputDevice()` → 成功则 setState 设置 `_currentInputDevice`。
- 在 `RecordingButton` **下方**新增设备 pill，仅当 `_state == recording && _currentInputDevice != null` 显示：
  - 文案：`${emoji} ${label}`，如 `🎙 内置麦克风`、`🎧 蓝牙耳机（AirPods）`、`🎧 有线耳机`。
  - 样式与现有天气 pill 一致（`warmSurface` 背景 + `warmMuted` 文字 + 圆角 border）。
- `_stopRecording` 的 setState 中清除 `_currentInputDevice = null`。

## 7. 边界与错误处理

- 查询失败/超时/返回 null：不显示 pill（安静失败，不打扰录音）。
- 蓝牙设备名取不到：显示 `🎧 蓝牙耳机`（无名）。
- 录音中途插拔耳机：**不监听**（YAGNI；录音通常不长，下次录音开始时刷新即可）。
- 非 Android 平台：MethodChannel 无 handler，`invokeMethod` 抛 `MissingPluginException` → catch 返回 null → 不显示 pill（项目仅 Android，此为防御）。

## 8. 测试策略

- **AudioInputDevice**：emoji 映射（builtin/bluetooth/wired）、fromMap（含 type 解析、label 透传）—— 单测。
- **AudioDeviceService**：mock MethodChannel，验证正常返回 AudioInputDevice、返回 null 时为 null、异常时为 null —— 单测。
- **Kotlin native + 真实设备路由**：手动验证（蓝牙耳机连接 / 有线耳机 / 仅内置 三场景），含蓝牙设备名有无 —— 需物理设备。
- **UI**：手动验证 pill 显示/清除、与天气 pill 视觉一致。

## 9. 不做（YAGNI）

- 不监听录音中途设备变化。
- 不支持设备选择（只显示，不让用户选）。
- 不区分多个同类型设备（多个蓝牙时取第一个名）。
- 不新增 AndroidManifest 权限（蓝牙设备名是 nice-to-have，取不到就用无名版）。

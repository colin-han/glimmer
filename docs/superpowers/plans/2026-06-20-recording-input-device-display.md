# 录音时显示当前输入设备 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 录音开始时在录音按钮下方常驻显示当前输入设备（内置麦克风 / 蓝牙耳机（含设备名）/ 有线耳机），停止录音后消失。

**Architecture:** Kotlin 端在 `MainActivity.kt` 注册 MethodChannel `info.colinhan.glimmer/audio_device`，用 `AudioManager.getDevices(GET_DEVICES_INPUTS)` + `AudioDeviceInfo.type/name` 判断当前录音源（**不需蓝牙权限**）。Dart 端 `AudioDeviceService` 封装 MethodChannel，`AudioInputDevice` model 表示结果。`RecordingPage` 录音开始时查询并在录音按钮下方显示 pill。

**Tech Stack:** Flutter/Dart、Kotlin（Android native）、MethodChannel（flutter/services）、AudioManager（Android API 23+）。

---

## 与 spec 的技术优化（必读）

spec §4 的 native 逻辑用 `AudioManager.isBluetoothScoOn` + `BluetoothManager.getConnectedDevices`。本计划改用 **`AudioManager.getDevices(GET_DEVICES_INPUTS)` + `AudioDeviceInfo`**，原因：
- **不需任何蓝牙权限**（`AudioDeviceInfo.type`/`name` 是系统 API，不要求 `BLUETOOTH_CONNECT`）。spec 的 `BluetoothManager` 路线需 `BLUETOOTH_CONNECT`（API 31+），与 spec「不加权限」冲突；本方案彻底避免。
- **无异步**：`getDevices` 同步返回，不需 `getProfileProxy` 的 callback + CountDownLatch。
- **更准**：`getDevices` 返回当前系统可用的输入设备列表，蓝牙耳机连接时含 `TYPE_BLUETOOTH_SCO` 设备。`isBluetoothScoOn` 只在 app 主动 `startBluetoothSco` 后才 true，被动路由时误判。

设备名通过 `AudioDeviceInfo.name`（API 23+，无权限）获取。完全满足 spec「蓝牙含设备名、不加权限」的要求。

---

## 文件结构

| 文件 | 职责 | 动作 |
|---|---|---|
| `lib/models/audio_input_device.dart` | `AudioInputType` enum + `AudioInputDevice` model（type/label/emoji/fromMap） | 新建 |
| `lib/services/audio_device_service.dart` | `AudioDeviceService.getCurrentInputDevice()` 封装 MethodChannel | 新建 |
| `android/app/src/main/kotlin/info/colinhan/glimmer/MainActivity.kt` | 注册 MethodChannel + `detectInputDevice()`（AudioManager 判断） | 修改 |
| `lib/pages/recording_page.dart` | 录音开始查询 + 录音按钮下方 pill 显示 | 修改 |
| `test/audio_input_device_test.dart` | model 单测（emoji/fromMap/容错） | 新建 |
| `test/audio_device_service_test.dart` | service 单测（mock MethodChannel） | 新建 |

---

## 任务总览

1. **AudioInputDevice model**（Dart 纯 model + 单测）
2. **AudioDeviceService**（MethodChannel 封装 + 单测）
3. **Kotlin native**（MainActivity MethodChannel + AudioManager 判断）
4. **UI 集成**（RecordingPage 录音按钮下方 pill）
5. **收尾**（analyze + format + 手动验证清单）

> 全程遵循 CLAUDE.md：中文注释/commit、英文标识符；提交前 `dart format` + `flutter analyze` 清零。

---

## Task 1: AudioInputDevice model

**Files:**
- Create: `lib/models/audio_input_device.dart`
- Test: `test/audio_input_device_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/audio_input_device_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/audio_input_device.dart';

void main() {
  group('AudioInputDevice emoji', () {
    test('builtin → 🎙', () {
      const d = AudioInputDevice(type: AudioInputType.builtin, label: '');
      expect(d.emoji, '🎙');
    });
    test('bluetooth → 🎧', () {
      const d = AudioInputDevice(type: AudioInputType.bluetooth, label: '');
      expect(d.emoji, '🎧');
    });
    test('wired → 🎧', () {
      const d = AudioInputDevice(type: AudioInputType.wired, label: '');
      expect(d.emoji, '🎧');
    });
  });

  group('AudioInputDevice.fromMap', () {
    test('解析 type + 透传 label（含蓝牙设备名）', () {
      final d = AudioInputDevice.fromMap({
        'type': 'bluetooth',
        'label': '蓝牙耳机（AirPods）',
      });
      expect(d.type, AudioInputType.bluetooth);
      expect(d.label, '蓝牙耳机（AirPods）');
    });

    test('wired 类型', () {
      final d = AudioInputDevice.fromMap({'type': 'wired', 'label': '有线耳机'});
      expect(d.type, AudioInputType.wired);
    });

    test('容错：未知 type → builtin', () {
      final d = AudioInputDevice.fromMap({'type': 'unknown', 'label': 'x'});
      expect(d.type, AudioInputType.builtin);
    });

    test('容错：缺字段 → 默认内置麦克风', () {
      final d = AudioInputDevice.fromMap({});
      expect(d.type, AudioInputType.builtin);
      expect(d.label, '内置麦克风');
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/audio_input_device_test.dart`
Expected: FAIL，报 `audio_input_device.dart` 不存在 / `AudioInputDevice` 未定义。

- [ ] **Step 3: 实现 lib/models/audio_input_device.dart**

```dart
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
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/audio_input_device_test.dart`
Expected: PASS（7 个测试全过）。

- [ ] **Step 5: 提交**

```bash
dart format lib/models/audio_input_device.dart test/audio_input_device_test.dart
git add lib/models/audio_input_device.dart test/audio_input_device_test.dart
git commit -m "feat: 新增 AudioInputDevice model（录音输入设备）"
```

---

## Task 2: AudioDeviceService（MethodChannel 封装）

**Files:**
- Create: `lib/services/audio_device_service.dart`
- Test: `test/audio_device_service_test.dart`

- [ ] **Step 1: 写失败测试（mock MethodChannel）**

创建 `test/audio_device_service_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diard/models/audio_input_device.dart';
import 'package:voice_diard/services/audio_device_service.dart';

void main() {
  const channel = MethodChannel('info.colinhan.glimmer/audio_device');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getCurrentInputDevice') {
            return {'type': 'bluetooth', 'label': '蓝牙耳机（AirPods）'};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('正常返回 AudioInputDevice', () async {
    final d = await AudioDeviceService().getCurrentInputDevice();
    expect(d, isNotNull);
    expect(d!.type, AudioInputType.bluetooth);
    expect(d.label, '蓝牙耳机（AirPods）');
  });

  test('native 返回 null → 返回 null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    expect(await AudioDeviceService().getCurrentInputDevice(), isNull);
  });

  test('native 抛异常 → 返回 null（安静失败）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'error', message: 'boom');
        });
    expect(await AudioDeviceService().getCurrentInputDevice(), isNull);
  });
}
```

> ⚠️ 上面 import 里的 `voice_diard` 是 package 名笔误，正确是 `voice_diary`。请把所有 `voice_diard` 改为 `voice_diary`（package name = `voice_diary`）。

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/audio_device_service_test.dart`
Expected: FAIL，报 `audio_device_service.dart` 不存在。

- [ ] **Step 3: 实现 lib/services/audio_device_service.dart**

```dart
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
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/audio_device_service_test.dart`
Expected: PASS（3 个测试全过）。

- [ ] **Step 5: analyze + 提交**

Run: `flutter analyze lib/services/audio_device_service.dart` → `No issues found!`

```bash
dart format lib/services/audio_device_service.dart test/audio_device_service_test.dart
git add lib/services/audio_device_service.dart test/audio_device_service_test.dart
git commit -m "feat: 新增 AudioDeviceService（MethodChannel 封装）"
```

---

## Task 3: Kotlin native（MainActivity MethodChannel + AudioManager 判断）

> **无自动化测试**（native + 真实设备路由需物理设备）。本任务靠编译通过 + `flutter analyze` + Task 5 手动验证。先确认 `minSdk >= 23`（`AudioManager.getDevices` / `AudioDeviceInfo.name` 均为 API 23+）：检查 `android/app/build.gradle*` 的 `minSdk = flutter.minSdkVersion`（Flutter 默认 24，满足）。

**Files:**
- Modify: `android/app/src/main/kotlin/info/colinhan/glimmer/MainActivity.kt`（替换整个文件）

- [ ] **Step 1: 用以下完整内容替换 MainActivity.kt**

现有文件是裸 `class MainActivity : FlutterActivity()`（无 body）。替换为：

```kotlin
package info.colinhan.glimmer

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "info.colinhan.glimmer/audio_device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentInputDevice" -> result.success(detectInputDevice())
                    else -> result.notImplemented()
                }
            }
    }

    /// 判断当前录音输入设备：蓝牙耳机 > 有线耳机 > 内置麦克风。
    /// 用 AudioManager.getDevices（API 23+），不需蓝牙权限；
    /// 设备名通过 AudioDeviceInfo.name（系统提供，无权限）。
    private fun detectInputDevice(): Map<String, String> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val inputs = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)

        // 1. 蓝牙耳机（SCO 输入）
        val bluetooth = inputs.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
        if (bluetooth != null) {
            val name = bluetooth.name?.takeIf { it.isNotBlank() }
            val label = if (name != null) "蓝牙耳机（$name）" else "蓝牙耳机"
            return mapOf("type" to "bluetooth", "label" to label)
        }

        // 2. 有线耳机
        val wired = inputs.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
        }
        if (wired != null) {
            return mapOf("type" to "wired", "label" to "有线耳机")
        }

        // 3. 内置麦克风
        return mapOf("type" to "builtin", "label" to "内置麦克风")
    }
}
```

> 说明：`AudioDeviceInfo.TYPE_BLUETOOTH_SCO` 是蓝牙耳机作为输入设备时的类型（HFP/SCO 通话麦克风走此）。蓝牙耳机连接录音时，系统在输入设备列表中暴露此类型。`getDevices(GET_DEVICES_INPUTS)` 不需任何蓝牙权限，`AudioDeviceInfo.name`（getter，API 23+）返回设备显示名也不需权限——故整个判断零蓝牙权限依赖。

- [ ] **Step 2: 确认能编译（debug build，dev flavor）**

Run: `flutter build apk --flavor dev --debug --no-pub 2>&1 | tail -5`（或直接 `./scripts/run_dev.sh` 触发首次编译）
Expected: `BUILD SUCCESSFUL`（Kotlin 编译通过，无 unresolved reference）。若报 `AudioDeviceInfo`/`AudioManager` 未解析，确认 import 正确。

> 注：`flutter analyze` 不分析 Kotlin，故编译是 native 正确性的唯一自动检查。

- [ ] **Step 3: 提交**

```bash
git add android/app/src/main/kotlin/info/colinhan/glimmer/MainActivity.kt
git commit -m "feat: MainActivity 注册 audio_device MethodChannel，判断录音输入设备"
```

---

## Task 4: UI 集成（RecordingPage 录音按钮下方 pill）

**Files:**
- Modify: `lib/pages/recording_page.dart`

- [ ] **Step 1: 加 import 与 State 字段**

1a. 顶部 import 区（在现有 import 之后）加：

```dart
import '../models/audio_input_device.dart';
import '../services/audio_device_service.dart';
```

1b. `_RecordingPageState` 的字段区（在 `WeatherLocation? _currentWeatherLocation;` 之后）加：

```dart
  AudioInputDevice? _currentInputDevice;
```

- [ ] **Step 2: 录音开始成功后查询设备**

找到 `_doStartRecording` 方法，在 `setState(() => _state = RecordingState.recording);` 之后、`FgsRuntime.setRecording();` 之前（约第 229-230 行）插入设备查询：

```dart
      setState(() => _state = RecordingState.recording);
      FgsRuntime.setRecording();
      WakelockPlus.enable();
```

改为：

```dart
      setState(() => _state = RecordingState.recording);
      FgsRuntime.setRecording();
      WakelockPlus.enable();

      // 查询当前录音输入设备（失败/为 null 则不显示 pill）
      final device = await AudioDeviceService().getCurrentInputDevice();
      if (mounted && device != null && _state == RecordingState.recording) {
        setState(() => _currentInputDevice = device);
      }
```

- [ ] **Step 3: 停止录音时清除**

找到 `_stopRecording` 的 `setState(() { ... })`（含 `_currentWeatherLocation = null;` 那段，约第 242-247 行），在 `_currentWeatherLocation = null;` 之后加一行：

```dart
    setState(() {
      _state = RecordingState.idle;
      _recordingSeconds = 0;
      _realtimeText = '';
      _currentWeatherLocation = null;
      _currentInputDevice = null;
    });
```

- [ ] **Step 4: 在录音按钮下方加设备 pill**

找到 `build` 方法里 `RecordingButton(...)` 之后的位置（约第 423-427 行，Column children 末尾）。在 `RecordingButton` 之后追加设备 pill：

```dart
                // 录音按钮
                RecordingButton(
                  state: _state,
                  onTap: _onTap,
                  recordingSeconds: _recordingSeconds,
                ),

                // 当前录音输入设备 pill（录音按钮下方）
                if (_state == RecordingState.recording &&
                    _currentInputDevice != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: WarmTokens.warmSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: WarmTokens.warmDivider.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      '${_currentInputDevice!.emoji} ${_currentInputDevice!.label}',
                      style: TextStyle(
                        fontSize: 12,
                        color: WarmTokens.warmMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
```

> 样式与现有天气 pill 完全一致（warmSurface 背景 + warmMuted 文字 + 圆角 border），仅位置在录音按钮下方。

- [ ] **Step 5: analyze + 提交**

Run: `flutter analyze lib/pages/recording_page.dart` → `No issues found!`

```bash
dart format lib/pages/recording_page.dart
git add lib/pages/recording_page.dart
git commit -m "feat: 录音按钮下方显示当前输入设备 pill"
```

---

## Task 5: 收尾（analyze + format + 手动验证）

**Files:** 无新增，仅验证。

- [ ] **Step 1: 全量 dart format + analyze**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`。若有 info/warning/error 逐个修。

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 全部测试通过（既有 + 本功能新增 audio_input_device_test / audio_device_service_test）。

- [ ] **Step 3: 若 Step 1-2 有修复，提交**

```bash
git add -u lib/ test/
git commit -m "chore: 录音设备显示收尾（format + analyze 清零）"
```
（无改动则跳过。）

- [ ] **Step 4: 手动集成验证（物理设备，./scripts/run_dev.sh）**

> native 设备路由无法自动化测试，必须在真机上验证三场景：

- [ ] **内置麦克风**：不连任何耳机，点录音 → 录音按钮下方显示 `🎙 内置麦克风`
- [ ] **蓝牙耳机**：连接蓝牙耳机（如 AirPods），点录音 → 显示 `🎧 蓝牙耳机（设备名）`（设备名取不到时显示 `🎧 蓝牙耳机`）
- [ ] **有线耳机**：插有线耳机，点录音 → 显示 `🎧 有线耳机`
- [ ] **停止录音**：停止后 pill 消失
- [ ] **查询失败容错**：观察无崩溃（MethodChannel 异常被 catch，不显示 pill，不阻塞录音）

---

## Self-Review

**1. Spec 覆盖**：
- spec §1-2（目标/约束）→ 计划开头说明 + 技术优化
- spec §3-4（native MethodChannel + 判断逻辑）→ Task 3（用 getDevices 优化版，覆盖 spec 需求）
- spec §5（Dart model + service）→ Task 1 + Task 2
- spec §6（UI pill）→ Task 4
- spec §7（边界：失败不显示、蓝牙名取不到、非 Android 防御）→ Task 2 catch + Task 4 null 检查 + Task 3
- spec §8（测试）→ Task 1/2 单测 + Task 5 手动
- spec §9（YAGNI）→ 计划不监听中途变化/不支持选择

**2. 占位符扫描**：无 TBD/TODO。Task 2 测试 import 的 `voice_diard` 已标注修正为 `voice_diary`。

**3. 类型一致性**：
- `AudioInputType { builtin, bluetooth, wired }`、`AudioInputDevice { type, label, emoji, fromMap }`、`AudioDeviceService.getCurrentInputDevice()`、MethodChannel 名 `info.colinhan.glimmer/audio_device`、method `getCurrentInputDevice`、native 返回 `{type, label}` map —— Task 1/2/3/4 全部一致。
- Kotlin 返回的 `type` 字符串（`builtin`/`bluetooth`/`wired`）与 Dart enum `name` 一致（fromMap 用 `t.name == typeStr` 匹配）。

结论：计划与 spec 对齐（含合理技术优化）、无占位符、类型一致，可交付执行。

# 语音日记 App 支持数小时长录音 -- 工程挑战深度调研报告

## 一、问题定义

当前 App 基于 Flutter + record 插件，使用 PCM16 流式录音写入 WAV 文件，最长限制 300 秒。录音期间 App 必须保持前台运行（无 Foreground Service），无后台保活机制。需要扩展至支持数小时连续录音，同时在录音质量、电池消耗、系统稳定性之间取得平衡。

**核心矛盾：** Android 系统版本迭代持续收紧后台执行能力，而长时间录音恰恰需要后台持续运行。

---

## 二、Android 系统限制分析

### 2.1 Foreground Service 演进与限制

| Android 版本 | 关键变化 | 对录音的影响 |
|---|---|---|
| Android 8.0 (API 26) | 后台执行限制，后台 App 几分钟后进入 idle | 长录音必须使用 Foreground Service |
| Android 11 (API 30) | 麦克风为 "while-in-use" 权限，FGS 必须在 App 可见时启动 | 不能从后台启动录音 FGS |
| Android 13 (API 33) | 需要 `POST_NOTIFICATIONS` 权限 | FGS 通知需要用户授权 |
| Android 14 (API 34) | 必须声明 FGS 类型（如 `microphone`）| Manifest 需增加 `foregroundServiceType="microphone"` |
| Android 15 (API 35) | `dataSync` 和 `mediaProcessing` 类型 FGS 有 6 小时/24小时上限 | **但 `microphone` 类型不受此 6 小时限制** |
| Android 17 | 背景音频加固，更严格的 "while-in-use" 要求 | 需持续关注 |

**关键结论：** 使用 `foregroundServiceType="microphone"` 的 FGS **没有 6 小时超时限制**（该限制仅适用于 `dataSync` 和 `mediaProcessing` 类型）。这为长时间录音提供了可行的系统级方案。

### 2.2 Doze 模式与 App Standby

根据官方文档和社区验证：
- **Foreground Service 在 Doze 模式下不会被杀死**，这是绕过 Doze 的推荐方案
- 但需要配合 `PARTIAL_WAKE_LOCK`，防止 CPU 进入深度休眠
- **App Standby Buckets** 会影响后台网络访问，但不影响 FGS

### 2.3 OEM 定制系统的额外限制

这是最大的不确定性来源。根据 [dontkillmyapp.com](https://dontkillmyapp.com/) 的数据：

| OEM | 问题严重程度 | 典型行为 |
|---|---|---|
| **Xiaomi (MIUI)** | 极高 | 即使 FGS 也会被杀，尤其是夜间；需要手动关闭 MIUI 的「省电策略」和开启「自启动」 |
| **Samsung** | 高 | Device Care 会自动「将 App 置于休眠」，需手动排除 |
| **Huawei (EMUI)** | 高 | 「手机管家 > 受保护应用」需手动添加 |
| **OPPO/Realme** | 高 | 类似小米的激进省电管理 |
| **Google Pixel** | 低 | 接近原生 Android 行为 |

**没有纯编程解决方案**，只能引导用户手动设置。推荐使用 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` Intent 请求白名单，并提供 OEM 特定的设置指引。

### 2.4 当前项目缺失的配置

当前 `AndroidManifest.xml` 缺少：
- `FOREGROUND_SERVICE` 权限
- `FOREGROUND_SERVICE_MICROPHONE` 权限（Android 14+）
- `POST_NOTIFICATIONS` 权限（Android 13+）
- `WAKE_LOCK` 权限
- Service 声明及 `foregroundServiceType="microphone"`

---

## 三、录音稳定性分析

### 3.1 内存占用

**当前方案（WAV/PCM16 流式写入）：**
- 采样率 16kHz, 16-bit, 单声道
- 数据速率 = 16000 * 2 * 1 = 32,000 bytes/s = ~31.25 KB/s
- 当前代码使用 `StreamController` + `IOSink` 流式写入，数据不会在内存中累积
- **内存占用恒定，不随录音时长增长**，当前架构已正确处理

### 3.2 中断恢复策略

**来电中断是最常见的场景：**

1. **检测来电**：使用 `TelephonyManager` + `CallStateListener` 监听 `CALL_STATE_RINGING` / `CALL_STATE_OFFHOOK` / `CALL_STATE_IDLE`
2. **暂停录音**：收到 `CALL_STATE_RINGING` 时暂停 `AudioRecord`
3. **恢复录音**：收到 `CALL_STATE_IDLE` 后，不能立即恢复。必须先确认 Audio Focus 已重新获取
4. **Audio Focus 管理**：使用 `AudioManager.OnAudioFocusChangeListener` 正确处理焦点变化

**其他中断源：**
- 闹钟/定时器
- 其他录音 App 抢占麦克风
- 系统级通知音
- 蓝牙设备连接/断开

**record 插件支持 pause/resume**，可以利用这一特性实现中断恢复。

### 3.3 录音被系统回收后的数据保护

**关键策略：**
- 流式写入 + 定期 `flush()`/`sync()`：当前代码已使用 `IOSink` 流式写入，但缺少定期 flush
- WAV header 回写：当前在 `stopRecording()` 时回写文件大小。如果录音被异常终止，WAV header 中的大小为 0
- **需要增加保护机制**：定时更新 WAV header 或采用冗余恢复策略
- 预留存储空间：录音前检查可用空间，录音中监控空间变化

---

## 四、音频格式与存储

### 4.1 文件大小估算（16kHz, 单声道）

| 格式 | 比特率 | 1小时 | 3小时 | 6小时 |
|---|---|---|---|---|
| **WAV/PCM16** | 256 kbps | ~115 MB | ~345 MB | ~690 MB |
| **AAC 128kbps** | 128 kbps | ~58 MB | ~173 MB | ~345 MB |
| **AAC 64kbps** | 64 kbps | ~29 MB | ~86 MB | ~173 MB |
| **Opus 64kbps** | 64 kbps | ~29 MB | ~86 MB | ~173 MB |
| **Opus 32kbps** | 32 kbps | ~14 MB | ~43 MB | ~86 MB |

语音场景下，Opus 32-64kbps 或 AAC 64-128kbps 已能提供足够的可懂度用于 ASR 识别。

### 4.2 格式选择的关键考量

**当前录音同时需要两路输出：**
1. 本地文件存储（用于保存和回放）
2. PCM 流（用于实时 ASR WebSocket 传输）

**record 插件的限制：**
- `startStream()` 仅支持 `pcm16bits` 和 `aacLc` 两种编码器
- 如果使用 `pcm16bits` 流模式，本地文件需要自行管理写入（当前方案）
- 如果使用 `aacLc` 流模式，AAC 数据带 ADTS header，可直接写入文件

**推荐方案（双轨制）：**
- 保持 PCM16 流用于实时 ASR（火山引擎 ASR 要求 PCM 输入）
- 本地文件可选 WAV 或 AAC/Opus
- 由于当前架构已经正确流式写入 WAV，最简单的路径是保持 WAV 格式，仅优化存储空间监控

### 4.3 存储空间不足处理

- 录音前检查：预估录音时长所需空间，提前警告
- 录音中监控：定时检查剩余空间，低于阈值（如 100MB）时自动停止录音并保存
- 优雅停止：停止时确保正确写入文件头/尾信息，防止文件损坏

---

## 五、电池与性能

### 5.1 录音本身功耗

根据技术调研数据：
- 连续录音约消耗 80mA 电流
- 典型手机电池（3000-5000mAh）可支持 **4-8 小时**连续录音
- 录音本身不是主要功耗来源

### 5.2 实时 ASR WebSocket 的额外开销

长时间运行面临的问题：
1. **网络连接稳定性**：WiFi/蜂窝切换、信号波动导致连接中断
2. **心跳保活**：需要实现 ping/pong 心跳机制
3. **断线重连**：需要指数退避重连策略
4. **服务端限制**：火山引擎 ASR WebSocket 单次连接可能有最大时长限制

**优化策略：**
- **分段 ASR 方案**：不持续保持 WebSocket 连接，而是每 N 分钟发送一段音频
- **录音完成后 ASR**：完全断开实时 ASR，仅保留录音功能
- **混合方案**：保持 WebSocket 连接但实现健壮的重连机制

### 5.3 降功耗策略

| 策略 | 效果 | 实现难度 |
|---|---|---|
| 录音时关闭屏幕 | 节省 30-50% 功耗 | 低 |
| 降低采样率（8kHz）| 降低数据量和 CPU 负载 | 低，但影响 ASR 质量 |
| 使用压缩格式 | 减少磁盘 I/O | 中 |
| 断开实时 ASR | 大幅降低网络和 CPU 开销 | 中，需要改动流程 |
| `PARTIAL_WAKE_LOCK` | 防止 CPU 休眠（必要开销）| 低 |

---

## 六、竞品方案

### 6.1 主要竞品对比

| 竞品 | 录音方案 | 后台录音 | 长录音策略 |
|---|---|---|---|
| **Otter.ai** | 软件录音，线上会议直接接入 | Android FGS | 主要面向会议场景（1-3小时）|
| **Plaud** | 硬件录音设备 + App 蓝牙同步 | 不依赖 App 后台运行 | 硬件独立录音数小时，App 仅同步和转写 |
| **讯飞语记/听见** | 软件 FGS 录音 | Android FGS + 电量白名单 | 会员支持长时间录音，实时转写 |
| **录音宝** | 专注长时间录音 | FGS | 云端转写，减轻端侧压力 |
| **Google Recorder** | 原生 Android FGS | 系统级优先级 | 实时设备端转写，不受第三方 App 限制 |
| **Smart Voice Recorder** | 优化的 FGS | FGS | 专为长录音优化，低功耗 |

### 6.2 竞品的共同模式

1. **都使用 Foreground Service**，无一例外
2. **都引导用户设置电池优化白名单**
3. **分段文件策略**：长时间录音分多个文件存储，避免单文件过大
4. **录音中断保护**：来电时自动暂停，结束后恢复

---

## 七、Flutter 生态方案

### 7.1 主要插件选项

| 插件 | 用途 | 适用性 |
|---|---|---|
| **flutter_background_service** | 提供长期运行的 Dart isolate 作为 FGS | 适合，但需要额外配置 AndroidManifest |
| **flutter_foreground_task** | 类似，更侧重任务型 FGS | 适合，文档更友好 |
| **flutter_background** | 简单的后台运行方案 | 功能较简单，可能不够健壮 |
| **Platform Channel 原生实现** | 自己写 Kotlin FGS + 录音逻辑 | 最灵活，但开发成本最高 |

### 7.2 推荐方案

**方案 A：flutter_background_service + record 插件（推荐）**
- 在 `flutter_background_service` 的 isolate 中运行 record 插件
- 优点：保持 Flutter 全栈，开发效率高
- 缺点：isolate 中的录音和主 UI 通信需要通过端口

**方案 B：Platform Channel 原生 FGS + 原生录音**
- 用 Kotlin 实现原生 FGS，内部使用 Android `AudioRecord` + `MediaCodec`
- 通过 Platform Channel 与 Flutter UI 通信
- 优点：最大控制力，可以直接处理来电中断、Audio Focus 等
- 缺点：开发成本高，需要维护原生代码

**方案 C：flutter_foreground_task + record 插件**
- 类似方案 A，但使用 `flutter_foreground_task` 替代 `flutter_background_service`
- 优点：API 更简洁，文档更清晰

---

## 八、推荐策略

### 8.1 分阶段实施路径

**第一阶段（必须）：基础长录音支持**
1. 增加 Android Foreground Service 声明和权限
2. 使用 `flutter_background_service` 或 `flutter_foreground_task` 实现录音 FGS
3. 移除 300 秒限制，改为基于存储空间的安全上限
4. 增加录音计时和文件大小显示
5. 实现锁屏/后台持续录音

**第二阶段（重要）：健壮性增强**
1. 实现来电检测和自动暂停/恢复
2. 定期 flush + WAV header 更新，防止异常终止导致数据丢失
3. 存储空间预检查和录音中监控
4. 电池优化白名单引导（通用 + OEM 特定指引）
5. `PARTIAL_WAKE_LOCK` 确保 CPU 不休眠

**第三阶段（优化）：性能与体验**
1. 评估是否将实时 ASR 改为录音后处理，降低长时间录音的网络/电池开销
2. 考虑分段文件策略（每 30 分钟一个文件）
3. 压缩格式选项（AAC/Opus）减少存储占用
4. 录音波形可视化适配长时间录音

### 8.2 架构建议

```
录音流程改造：
┌─────────────────────────────────────────────────┐
│  Flutter UI（主 Isolate）                         │
│  - 录音控制界面                                    │
│  - 实时波形显示                                    │
│  - 计时器显示                                      │
│  ↕ (SendPort/ReceivePort)                         │
│  Background Service Isolate                       │
│  - record 插件录音                                │
│  - PCM 流 → 文件写入（WAV/AAC）                    │
│  - PCM 流 → 实时 ASR WebSocket                    │
│  - 来电检测 → 暂停/恢复                            │
│  - 存储空间监控                                    │
│  - WakeLock 保持                                   │
└─────────────────────────────────────────────────┘
```

### 8.3 风险点

1. **OEM 兼容性**：小米/华为等设备的激进省电策略可能导致录音中断，需要充分的用户引导
2. **火山引擎 ASR WebSocket 连接时长限制**：需确认单次 WebSocket 连接的最大持续时长，可能需要实现分段重连
3. **record 插件在 background isolate 中的行为**：需要验证 record 插件在非主 Isolate 中是否正常工作
4. **WAV 超大文件兼容性**：部分播放器可能不支持超大 WAV 文件（>2GB，即约 16 小时），可通过分段文件规避

---

## 来源

- [Android FGS Types Required - Android 14](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- [Android FGS Timeout - Android 15](https://developer.android.com/develop/background-work/services/fgs/timeout)
- [Foreground Service Restrictions from Background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Background Audio Hardening - Android 17](https://developer.android.com/about/versions/17/changes/bg-audio)
- [Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Manage Audio Focus](https://developer.android.com/media/optimize/audio-focus)
- [Foreground Service Best Practices - Wake Lock](https://developer.android.com/develop/background-work/background-tasks/awake/wakelock/best-practices)
- [Don't Kill My App](https://dontkillmyapp.com/)
- [Fighting with Doze, App Standby and Audio Streaming (Spreaker)](https://medium.com/spreaker-developers/fighting-with-doze-app-standby-and-audio-streaming-234249197241)
- [Beyond Doze: Building Reliable Background Execution (ProAndroidDev)](https://proandroiddev.com/beyond-doze-building-reliable-background-execution-on-modern-android-including-oem-realities-5fa0a6e05672)
- [Everything That Can Interrupt Your Microphone on Android](https://dev.to/agnihotripushkar/everything-that-can-interrupt-your-microphone-on-android-and-how-to-handle-it-68b)
- [How to Properly Handle Audio Interruptions (Google Developers)](https://medium.com/google-developers/how-to-properly-handle-audio-interruptions-3a13540d18fa)
- [Flutter record plugin (GitHub)](https://github.com/llfbandit/record)
- [flutter_background_service](https://pub.dev/packages/flutter_background_service)
- [flutter_foreground_task](https://pub.dev/packages/flutter_foreground_task)
- [Background Audio in Flutter (Suragch)](https://suragch.medium.com/background-audio-in-flutter-with-audio-service-and-just-audio-3cce17b4a7d)
- [Record Audio in ForegroundService Issue](https://github.com/ekasetiawans/flutter_background_service/issues/455)
- [Android Vitals Wake Lock](https://android-developers.googleblog.com/2025/09/guide-to-excessive-wake-lock-usage.html)
- [Audio File Size Calculator](https://www.colincrawley.com/audio-file-size-calculator/)
- [Flutter Foreground Service Gets Killed on Xiaomi (GitHub)](https://github.com/Dev-hwang/flutter_foreground_task/issues/343)
- [Xiaomi Kills FGS During Night Time (B4X Forum)](https://www.b4x.com/android/forum/threads/xiaomi-and-others-killing-foreground-services-during-night-time.135757/)

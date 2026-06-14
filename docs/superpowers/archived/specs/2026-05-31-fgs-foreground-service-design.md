# FGS 前台服务设计：锁屏录音与网络保活

> **目标**: 实现 Android Foreground Service，确保锁屏时录音和网络请求不断开。

## 背景

当前录音和处理流程全在 UI isolate 中运行。锁屏后 Android 会挂起 UI 进程，导致：
- WebSocket 连接断开（"software caused connection abort"）
- HTTP 请求中断（TOS 上传、ASR、LLM）
- Opus 编码中断（PCM → OGG 实时编码需要持续 CPU）

虽然已实现重试功能（保存数据后可从详情页重试），但根本解决方案是使用 FGS 保持进程活跃。

## 当前处理流程

录音停止后的管线需要 FGS 保护：

1. **上传 OGG 到 TOS**（1-5s，网络上传）
2. **生成预签名 URL + Flash ASR**（1-5s，网络请求）
3. **LLM 润色**（5-15s，网络请求）
4. **保存元数据**（本地 DB 写入）
5. **自动打标签**（1-3s，可选网络请求）

加上录音阶段本身（PCM → Opus 实时编码 + WebSocket ASR），整个过程都需要保护。

## 方案选择

**选定方案**: `flutter_foreground_task` + 全 TaskHandler

- 全部录音和处理逻辑运行在 TaskHandler 的独立 isolate 中
- 纯 Dart 实现，无需维护原生 Kotlin 代码
- `foregroundServiceType="microphone"` 不受 Android 15 的 6 小时超时限制
- 内置 WakeLock + WiFiLock 支持

## 架构

### 文件结构

```
lib/
  services/
    recording_service.dart     # 新增：FGS TaskHandler
  pages/
    recording_page.dart        # 重构：变为 UI 壳
```

### 职责划分

**`RecordingService`（TaskHandler isolate）**:
- 管理 AudioRecorder + AudioEncoderService 完整生命周期
- PCM 流双路分发：Opus 编码写文件 + WebSocket ASR 实时转写
- 录音停止后执行：TOS 上传 → Flash ASR(URL) → LLM → 自动打标签 → 保存
- 通过 sendDataToMain() 发送状态给 UI

**`RecordingPage`（UI isolate）**:
- 启动/停止 FGS
- 监听状态消息更新 UI
- 处理完成后导航到详情页
- 触发 TTS 播报（在 UI isolate 中，因为涉及 just_audio 和系统音频焦点）

## 通信协议

### TaskHandler → UI

| event | 数据 | 说明 |
|-------|------|------|
| `recording` | `{duration, amplitude}` | 每秒发送录音状态 |
| `partial` | `{text}` | 实时转写片段 |
| `processing` | `{step}` | 步骤：1=上传+ASR, 2=LLM, 3=保存, 4=打标签 |
| `completed` | `{entryId}` | 全部完成 |
| `failed` | `{entryId, step, error}` | 失败但数据已保存，可重试 |
| `error` | `{message}` | 录音出错，无数据 |

### UI → TaskHandler

| action | 说明 |
|--------|------|
| `stop` | 停止录音，进入处理阶段 |
| `cancel` | 取消整个流程 |

## TaskHandler 内部流程

### 录音阶段

1. 创建 UUID + 文件夹
2. 初始化 AudioRecorder（PCM 16kHz, 16bit, mono）
3. 初始化 AudioEncoderService（PCM → Opus/OGG 实时编码）
4. 初始化 RealtimeAsrService WebSocket
5. 录音循环：PCM 帧双路分发
   - 路径 A：喂入 AudioEncoderService → 写入 audio.ogg
   - 路径 B：发送到 WebSocket ASR
   - 接收转写结果，发送 partial 给 UI
   - 每秒发送录音状态（时长、音量）给 UI
6. 收到 stop 或 5 分钟超时 → 停止

### 处理阶段

7. 关闭 WebSocket，停止 AudioEncoderService（flush 剩余数据 + EOS 页）
8. 上传 OGG 到 TOS，获取 tosKey
9. 生成预签名 URL
10. Flash ASR（URL 模式，OGG/Opus 格式）→ 发送 step=1
11. LLM 润色（保留时间戳）→ 发送 step=2
12. 保存 transcript.json + llm_result.json + SQLite 元数据（含 tosKey、audioFormat='ogg'、uploadedAt）→ 发送 step=3
13. 自动打标签 → 发送 step=4
14. 发送 completed + entryId

### 错误处理

- **WebSocket ASR 断开**: 不中断录音，继续 Opus 编码写文件，完成后用 Flash ASR 兜底
- **TOS 上传失败**: 保存本地 OGG 文件，发送 failed(step=1)。详情页重试时可重新上传
- **Flash ASR 失败**: 保存 OGG 文件 + 空 transcript，发送 failed(step=1)
- **LLM 失败**: 保存 OGG + transcript，发送 failed(step=2)
- **任何步骤**: 确保已生成文件写入磁盘，entryId 传回 UI

## Android 配置

### AndroidManifest.xml 新增

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="microphone"
    android:exported="false"
    android:stopWithTask="true" />
```

### 运行时权限

1. `RECORD_AUDIO`（已有）
2. `POST_NOTIFICATIONS`（Android 13+，新增）
3. 权限就绪后启动 FGS

### 通知

- 录音中: "Glimmer — 正在录音..."
- 处理中: "Glimmer — 正在处理日记..."
- 通知渠道: `recording_channel`，低优先级

## RecordingPage UI 变更

- 录音按钮 → 检查权限 → 启动 FGS → TaskHandler 开始录音
- 停止按钮 → sendDataToTask({"action": "stop"})
- 返回键 → 录音中弹窗确认
- 监听消息更新：录音时长、音量动画、实时转写文本、处理步骤进度
- 收到 completed/failed → 停止 FGS → 导航详情页 → 触发 TTS

## 新增依赖

```yaml
flutter_foreground_task: ^9.2.2
```

## 成功标准

1. 锁屏后录音不中断（PCM → Opus 编码持续）
2. 锁屏后 TOS 上传、ASR、LLM 网络请求完成
3. 任何步骤失败时 OGG 音频文件和已有数据不丢失
4. 通知正确显示录音/处理状态
5. Android 14+ 兼容（FGS 类型权限）

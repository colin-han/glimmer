# 实时语音识别改造设计

## 背景

当前应用使用火山引擎 Flash ASR（HTTP POST）做离线识别，用户录完音后才能看到转写结果。改造为使用火山引擎 v3 大模型双向流式 ASR（WebSocket），实现录音时实时展示识别文本。

## 方案

**实时流驱动 + Flash 兜底**：录音时通过 WebSocket 实时获取中间结果并展示；停止后用 Flash ASR 做一次完整识别作为最终文本，再走 LLM 润色。

## 架构

### 新增 RealtimeAsrService

文件：`lib/services/realtime_asr_service.dart`

封装 v3 bigmodel_async WebSocket 协议：

- 端点：`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`
- 认证：`X-Api-App-Key`（复用 `VOLCENGINE_SPEECH_APPID`）、`X-Api-Access-Key`（复用 `VOLCENGINE_SPEECH_TOKEN`）
- Resource-Id：`volc.bigasr.sauc.duration`
- 音频参数：PCM, 16kHz, 16bit, 单声道
- 每 200ms 发送一帧音频（6400 字节），带正序列号
- 最后一帧 flag=`0b0010`（无序列号，最后一包）

协议帧格式（4 字节帧头）：

```
Byte 0: [Protocol version (4 bits)] [Header size (4 bits)]
Byte 1: [Message type (4 bits)] [Message type flags (4 bits)]
Byte 2: [Serialization (4 bits)] [Compression (4 bits)]
Byte 3: [Reserved]
```

- 第一帧：message type=`0b0001`（完整客户端请求），payload 为配置 JSON
- 后续帧：message type=`0b0010`（仅音频），flags=`0b0001`（带正序列号）
- 最后一帧：flags=`0b0010`（最后一包）

对外暴露：
- `Stream<String>` 中间结果（`definite=false` 的 utterances 文本）
- `Future<String>` 最终累积文本
- `connect()` / `sendAudio(Uint8List)` / `stop()` 生命周期方法

### 改造 AudioRecorderService

文件：`lib/services/audio_recorder_service.dart`

将 `record` 插件的 `start()` 替换为 `startStream()`，同时满足实时流传输和本地文件存档：

- `startStream()` 返回 PCM 音频流
- PCM 数据同时写入本地 WAV 文件（手动拼接 44 字节 WAV header + PCM data）
- PCM 数据同时输出给 RealtimeAsrService
- `RecordConfig`：`encoder: AudioEncoder.pcm16bits`, `sampleRate: 16000`, `numChannels: 1`
- 新增 `Stream<Uint8List>` 暴露给外部

### 改造 RecordingPage

文件：`lib/pages/recording_page.dart`

UI 变化：
- 录音状态下，波形图下方增加文本区域，实时显示 ASR 中间结果
- 中间结果使用灰色/半透明样式
- 停止后中间结果替换为 Flash ASR 最终结果

状态机不变（idle → recording → processing），处理步骤从 3 步改为 4 步：
1. 录音结束 + Flash ASR 识别
2. 写入原始文本
3. LLM 润色
4. 保存完成

### 不变的部分

- `AsrService`：Flash ASR 继续用作兜底，代码不变
- `LlmService`：不变
- `DiaryStorageService`：不变
- 数据模型：不变

## 数据流

```
点击录音
  ├─ AudioRecorder.startStream() → PCM 流
  │   ├─ 写入本地 WAV 文件（拼 header + data）
  │   └─ 发送到 WebSocket → 实时中间文本 → 显示在屏幕上
  └─ 计时器启动

点击停止
  ├─ 关闭 WebSocket，停止录音流
  ├─ 完成 WAV 文件写入
  ├─ Flash ASR 识别 WAV 文件 → 最终文本（兜底）
  ├─ LLM 润色最终文本
  └─ 保存文件 + SQLite 元数据 → 跳转详情页
```

## 错误处理

- WebSocket 连接失败：不阻塞录音，屏幕上不显示实时文本，停止后仍走 Flash ASR
- Flash ASR 失败：保持现有错误展示逻辑，显示"重新开始"按钮
- 网络中断导致实时流断开：录音继续，实时文本停留在最后收到的内容，停止后走 Flash 兜底

## 文件变更清单

| 文件 | 操作 |
|------|------|
| `lib/services/realtime_asr_service.dart` | 新建 |
| `lib/services/audio_recorder_service.dart` | 改造 |
| `lib/pages/recording_page.dart` | 改造 |
| `.env.local.example` | 更新（如 Resource-Id 不同） |

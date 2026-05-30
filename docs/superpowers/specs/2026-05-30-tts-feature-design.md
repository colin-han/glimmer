# TTS 语音播报功能设计

## 背景

为语音日记 App 增加 TTS 语音播报功能，在录音结束和 AI 整理完成两个时机通过语音与用户交互。

## 方案

使用火山引擎 TTS HTTP API（V1 非流式一次性合成），复用现有豆包大模型生成播报内容，用 `just_audio` 播放合成音频。

## 触发点

### 触发点 1：停止录音后 — 甜美女声应答

**时机**：用户点击停止录音后，立即触发（与 Flash ASR 并行执行）。

**流程**：
1. 拿到实时 ASR 的 `_realtimeText`（用户刚说的话）
2. 调用 LLM 生成一句应景的回复（20 字以内，语气亲切温暖）
3. 调用 TTS 合成音频（甜美女声）
4. 播放音频

**LLM prompt**：给定用户的实时识别文本，生成一句简短的应答（不超过 20 字），语气温暖亲切，就像朋友在回应。

### 触发点 2：LLM 整理完成后 — 低沉男声播报

**时机**：LLM 润色完成、保存元数据后。

**流程**：
1. 现有 LLM summarize 已返回正文和标题
2. 改造 summarize，额外返回 `oneLineSummary`（一句话总结）
3. 调用 LLM 生成播报文本（语义类似"日记整理完成，一句话总结是 xxx"，但不限模板）
4. 调用 TTS 合成音频（低沉男声）
5. 播放音频

## 新增组件

### TtsService

文件：`lib/services/tts_service.dart`

封装火山引擎 TTS HTTP API（V1 非流式）：

- 端点：`https://openspeech.bytedance.com/api/v1/tts`
- 认证：`Authorization: Bearer;{token}`（header）
- 请求 payload：
  ```json
  {
    "app": {"appid": "...", "token": "...", "cluster": "volcano_tts"},
    "user": {"uid": "..."},
    "audio": {"voice_type": "BV700_V2_streaming", "encoding": "mp3", "speed_ratio": 1.0},
    "request": {"reqid": "uuid", "text": "...", "text_type": "plain", "operation": "query"}
  }
  ```
- 响应：JSON，`code: 3000` 表示成功，`data` 字段为 base64 编码的音频
- 音色参数 `voice_type`：
  - 甜美女声：`BV700_V2_streaming`（灿灿 2.0）
  - 低沉男声：`BV406_V2_streaming`（梓梓 2.0）
- 音频格式：`mp3`（体积小，just_audio 直接支持）
- 用 `just_audio` 播放（项目已有此依赖）

对外暴露：
- `Future<void> speak(String text, VoiceType voiceType)` — 合成并播放
- `void stop()` — 停止播放

### LlmService 改造

文件：`lib/services/llm_service.dart`

1. 新增 `generateReply(String realtimeText)` 方法：基于实时识别文本生成一句应景回复
2. 改造 `summarize()` 方法：prompt 增加 `oneLineSummary` 字段要求，`LlmResult` 新增 `oneLineSummary` 字段

### RecordingPage 改造

文件：`lib/pages/recording_page.dart`

- `_stopAndProcess()` 中，停止录音后调用 LLM 生成应答 → TTS 播放（甜美女声），与 Flash ASR 并行
- 保存完成后，调用 LLM 生成播报文本 → TTS 播放（低沉男声）
- 播放时不阻塞 UI（TTS 播放在后台异步执行）

## 数据流

```
停止录音
  ├─ TTS 触发点 1（并行）：
  │   LLM.generateReply(realtimeText) → TTS 合成（甜美女声）→ just_audio 播放
  ├─ Flash ASR → LLM.summarize()（含 oneLineSummary）→ 保存
  └─ TTS 触发点 2：
      LLM 生成播报文本 → TTS 合成（低沉男声）→ just_audio 播放
```

## 错误处理

- LLM 生成失败：跳过 TTS，不阻塞主流程
- TTS 合成失败：跳过播放，不阻塞主流程
- 音频播放被打断（如用户快速返回）：正常处理，不报错

## 文件变更清单

| 文件 | 操作 |
|------|------|
| `lib/services/tts_service.dart` | 新建 |
| `lib/services/llm_service.dart` | 改造：新增 generateReply，summarize 增加 oneLineSummary |
| `lib/pages/recording_page.dart` | 改造：集成两个 TTS 触发点 |
| `.env.local.example` | 更新：TTS 相关变量说明 |

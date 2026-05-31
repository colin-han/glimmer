# 语音日记 App 支持数小时级长录音 ASR 深度调研报告

## 一、问题定义

当前 App 使用火山引擎 ASR，录音格式为 WAV（16kHz 16-bit mono）。扩展到数小时录音面临以下核心挑战：

- **文件体积**：16kHz 16-bit mono WAV 每小时约 115MB，3小时约 345MB，5小时约 575MB
- **现有 ASR 通道限制**：当前使用的 Flash ASR（同步接口）和实时 WebSocket ASR 均不适合数小时级音频
- **移动端资源约束**：长时间录音的内存、存储、电量消耗

## 二、主流 ASR 服务长音频支持能力对比

### 2.1 国内服务

| 服务商 | 产品 | 单文件时长上限 | 文件大小上限 | 调用方式 | 说话人分离 |
|--------|------|--------------|------------|---------|-----------|
| **火山引擎** | 语音转字幕 ASR | **3 小时** | 未明确 | 异步 submit/query | 支持 |
| **火山引擎** | 数据智能体音频处理 | **5 小时** | 未明确 | 异步 | 支持 |
| **火山引擎** | 大模型录音文件识别标准版 | 单文件约 5 小时，半小时窗口最多提交 500h | 未明确 | 异步 submit/query | 支持 |
| **阿里云** | 非实时语音识别（千问） | **12 小时** | **2GB** | 异步三步（提交/轮询/获取） | 支持，但建议不超过 2h |
| **腾讯云** | 录音文件识别（URL方式） | **5 小时** | **512MB** | 异步 | 支持 |
| **腾讯云** | 实时音视频录音文件识别 | **12 小时** | **1GB** | 异步 | 支持 |
| **讯飞** | 录音文件转写（LFASR） | **5 小时** | **500MB** | 异步 | 支持 |
| **讯飞** | 录音文件转写大模型版 | **5 小时** | **500MB** | 异步 | 支持 |
| **讯飞** | 实时语音转写大模型版 | **8 小时**（单次） | — | 实时 WebSocket | 不限时长 |

### 2.2 海外服务

| 服务商 | 产品 | 时长/文件上限 | 调用方式 | 特点 |
|--------|------|-------------|---------|------|
| **OpenAI** | Whisper API (whisper-1) | **25MB** 文件大小（无显式时长限制） | 同步 | WAV 约 3-4 分钟，MP3 可更长 |
| **OpenAI** | GPT-4o Transcribe | 25MB（可能有不同限制） | 同步 | 更新路由 |
| **Google Cloud** | Batch Recognize (v2) | **480 分钟 (8小时)** | 异步，需 Cloud Storage | 480h/天 项目配额 |
| **Google Cloud** | 流式识别 | ~1 分钟 | 实时 Streaming | 需实时发送 |
| **Azure** | Batch Transcription | **240 分钟（4小时，含说话人分离）** | 异步 | 批量最短 6h、最长 31天 |
| **AssemblyAI** | Async Transcription | **10 小时** | **5GB** | 异步 | 自带 PII 脱敏，1000 词自定义词表 |
| **Deepgram** | Pre-recorded | 未显式限制 | **2GB** | 异步 | 40x 实时速度 |

### 2.3 关键发现

1. **火山引擎当前能力**：语音转字幕 ASR 单文件 3 小时，数据智能体场景 5 小时。对于语音日记场景（通常 1-5 小时），火山引擎的异步录音文件识别 API 可以覆盖大部分需求。
2. **阿里云千问能力最强**：12 小时 / 2GB，是国内服务中对长音频支持最好的。
3. **所有长音频方案均为异步模式**：提交任务 -> 轮询状态 -> 获取结果，不支持实时流式。
4. **WAV 格式是瓶颈**：115MB/小时的体积使得 5 小时录音达 575MB，超过多家服务的文件大小限制（如讯飞 500MB）。考虑转码压缩是必要的。

## 三、长音频 ASR 的技术挑战

### 3.1 音频分段与拼接策略

**核心问题**：ASR 服务有单次请求的时长/文件大小限制，超长音频必须分段。

**主流分段方案**：

| 方案 | 原理 | 优点 | 缺点 |
|------|------|------|------|
| **固定时长分段** | 每 N 分钟切割一段 | 简单可靠 | 可能在句子中间截断，破坏上下文 |
| **VAD（语音活动检测）分段** | 检测静音/停顿处切割 | 保持语义完整性，在自然停顿处切分 | 长时间无停顿的独白难以分段 |
| **静音检测分段** | 能量低于阈值处切割 | 实现简单 | 噪声环境误判率高 |

**推荐方案**：VAD 分段 + 重叠窗口（overlap）
- 使用 Silero VAD 或 WebRTC VAD（轻量、可在移动端运行）检测语音段
- 相邻段之间保留 1-2 秒重叠，避免截断词语
- 拼接时去除重叠部分的重复文本
- 参考实现：[Whisper + Pyannote + FFmpeg pipeline](https://medium.com/@rafaelgalle1/building-a-custom-scalable-audio-transcription-pipeline-whisper-pyannote-ffmpeg-d0f03f884330)

### 3.2 说话人分离（Diarization）

**在语音日记场景的必要性**：
- 个人日记：**不需要**。单人独白是主要场景。
- 访谈/会议场景：**需要**。多人对话需要区分发言者。

**当前最佳方案**：
- [pyannote speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)：开源最佳，DER ~11-19%
- 大多数云端 ASR 服务已内置说话人分离（但时长限制更严格，如阿里云建议不超过 2 小时）

**建议**：语音日记核心场景（个人独白）暂不引入说话人分离，但保留扩展接口。未来如需多人场景，可通过云端 ASR 内置的说话人分离功能实现。

### 3.3 上下文一致性

**问题**：分段识别后，同一专有名词/术语在不同段落可能被识别为不同文字。

**解决方案**：

| 方案 | 说明 | 适用性 |
|------|------|-------|
| **自定义词表/热词** | 提交识别任务时附带术语列表 | 火山引擎、阿里云等均支持 |
| **LLM 后处理统一** | 全文识别后，用 LLM 统一术语 | 当前 App 已有 LLM 管线，成本低 |
| **上下文传递** | 将前一段结果作为上下文传给下一段 | 需要服务端支持 |

**推荐**：LLM 后处理统一（与现有管线自然结合）+ 热词机制（如火山引擎支持）。

### 3.4 时间戳精度

**问题**：分段后，每段时间戳从 0 开始，需要全局对齐。

**解决方案**：
- 记录每段的起始偏移量（字节偏移 -> 时间偏移）
- 拼接时给每段 utterance 的时间戳加上全局偏移
- 现有代码中 `Utterance` 模型已有 `startTime` / `endTime`，扩展为全局时间戳只需在拼接层加偏移

## 四、边缘方案与开源替代

### 4.1 Whisper 本地模型在 Android 端的可行性

| 模型 | 大小 | 内存占用 | 推理速度（Android 旗舰） | 可行性 |
|------|------|---------|----------------------|--------|
| Whisper tiny | ~40MB（量化后） | ~100MB | ~2s / 30s 音频（Pixel 7） | 可行 |
| Whisper base | ~75MB | ~200MB | 实时或接近实时 | 可行 |
| Whisper medium | ~1.5GB | ~2GB | 慢于实时 | 旗舰机勉强 |
| Whisper large-v3 | ~3GB+ (FP16) | ~3GB+ | 远慢于实时 | 不可行 |
| Whisper large-v3-turbo（INT8 量化） | ~400-600MB | ~600MB | 接近实时 | 旗舰机可行 |
| Whisper large-v3-turbo（Qualcomm NPU 优化） | — | — | 可能实时 | 最有前景 |

**关键信息**：
- [Qualcomm AI Hub](https://aihub.qualcomm.com/mobile/models/whisper_large_v3_turbo) 提供了针对 Snapdragon NPU 优化的 Whisper Large V3 Turbo 模型
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) 支持 Android，batch 模式下 ~5s 音频 ~1-2s 推理，但 streaming 模式每 chunk 需要 5-7s
- [WhisperKit（arXiv 2507.10860）](https://arxiv.org/html/2507.10860v1) 证明了量化 + chunked inference 可以在端侧实现实时 ASR

**结论**：Whisper large-v3-turbo INT8 量化模型在 2025 年旗舰 Android 设备上已具备实时或接近实时的推理能力。但对于数小时录音，云端异步方案仍更可靠。

### 4.2 流式 ASR 的长时稳定性

**当前架构**：使用火山引擎实时 WebSocket ASR（`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`）

**挑战**：
- WebSocket 连接长时间保持（数小时）面临网络波动、超时断连风险
- 移动端网络切换（Wi-Fi <-> 4G/5G）导致连接中断

**稳定性策略**：

| 策略 | 说明 |
|------|------|
| **心跳保活** | 定时发送 ping/pong 帧保持连接 |
| **指数退避重连** | 断连后按 1s, 2s, 4s, 8s... 间隔重连 |
| **本地音频缓冲** | 重连期间继续录音到本地，重连后补发 |
| **分段连接** | 每 30 分钟主动断开重连，避免单次连接过长 |

**注意**：火山引擎实时 ASR 的 WebSocket 连接虽然没有显式的最大时长限制，但长时间连接的稳定性需要客户端自行保障。

### 4.3 混合方案（本地 + 云端）

**架构**：

```
录音中：
  本地 VAD 检测 → 本地小模型（Whisper tiny/base）实时预览
  同时完整录音到本地文件

录音结束：
  本地文件 → 压缩转码（WAV→MP3/FLAC）→ 云端异步 ASR 全文识别
  → LLM 后处理 → 最终结果
```

**优势**：
- 录音中提供实时文字预览（用户体验）
- 录音后用云端大模型获取高质量全文（识别质量）
- 本地备份确保数据不丢失

## 五、竞品分析

### 5.1 长录音处理方式对比

| 产品 | 目标场景 | 长录音策略 | ASR 引擎 | 特色 |
|------|---------|-----------|---------|------|
| **Otter.ai** | 会议记录 | 云端实时转写 + 后处理 | 自研云端 ASR | 实时转录优秀，但长音频处理速度一般 |
| **讯飞听见** | 会议/采访 | 云端异步转写 | 讯飞自研 ASR + 星火大模型 | 中文准确率 98%，1h 录音约 8min 处理，已发布长语音大模型 |
| **通义听悟** | 会议/课程 | 阿里云异步 ASR + LLM 摘要 | 阿里千问 ASR | 免费用户每日 2h，异步转写 |
| **Plaud** | 个人录音笔 | 设备端录音 → 蓝牙传手机 → 云端 ASR → LLM | 云端 ASR + ChatGPT | 骨传导麦克风，端到端加密，SOC2/HIPAA 认证 |
| **Riverside.fm** | 播客录制 | 分轨录制 + 云端 AI 转写 | 自研/合作 ASR | 48kHz WAV 高质量，100+ 语言，99% 准确率宣称 |

### 5.2 竞品关键启示

1. **Otter.ai**：实时转写体验好，但处理速度是短板。说明实时方案在超长音频上的处理效率不够。
2. **讯飞听见**：1h 录音 8min 处理，已经相当快。其"长语音大模型"方向值得跟踪。
3. **Plaud**：硬件录音 + 云端后处理的"异步架构"是成熟商业模式。录音时不需要实时 ASR，录音完成后上传处理。
4. **通义听悟**：每日限额模式（免费 2h/天），说明长音频 ASR 的成本是需要控制的。

## 六、推荐策略

### 6.1 推荐方案：实时预览 + 异步全文（双层架构）

```
┌─────────────────────────────────────────────────┐
│                   录音阶段                        │
│                                                   │
│  麦克风 → WAV 录音（完整保存到本地）                  │
│       ↓                                           │
│  实时 WebSocket ASR（火山引擎大模型流式）             │
│  - 提供实时文字预览                                 │
│  - 每 30 分钟主动重连一次                           │
│  - 断连时本地缓冲，重连后补发                         │
│  - 实时结果仅用于预览，不作为最终结果                   │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│                  后处理阶段                        │
│                                                   │
│  1. WAV → 压缩转码（16kHz mono → FLAC 或 MP3）     │
│     5h WAV (~575MB) → FLAC (~200MB) 或            │
│     MP3 64kbps (~23MB)                            │
│                                                   │
│  2. 根据音频时长选择 ASR 通道：                      │
│     ≤ 3h: 火山引擎录音文件识别（异步，已有服务）       │
│     3-5h: 火山引擎数据智能体音频处理                  │
│     > 5h: 需要分段处理（VAD 分段 → 多次提交）         │
│     或切换到阿里云千问（12h/2GB）                     │
│                                                   │
│  3. LLM 后处理（已有管线）：                        │
│     - 统一专有名词/术语                             │
│     - 生成润色正文/提炼/播报大纲/标题                  │
│                                                   │
│  4. 保存最终结果到本地文件 + SQLite 元数据            │
└─────────────────────────────────────────────────┘
```

### 6.2 关键技术要点

1. **录音格式优化**：录音阶段保持 WAV（保证质量），后处理阶段转 FLAC（无损压缩，节省 40-60% 空间）或 MP3 64kbps（有损但极小，适合仅语音场景）。这能让 5 小时音频从 575MB 降到 23MB（MP3 64kbps），轻松通过所有服务的文件大小限制。

2. **ASR 通道选择优先级**：
   - 首选火山引擎异步录音文件识别（现有服务，无需新签约）
   - 备选阿里云千问非实时语音识别（12h 上限，最强长音频能力）
   - 超长音频（>5h）需客户端 VAD 分段后多次提交

3. **实时 ASR 稳定性**：
   - 录音阶段实时 ASR 仅作预览用途，结果不持久化
   - 每 30 分钟主动断开重连 WebSocket
   - 断连期间音频写入环形缓冲区，重连后补发
   - 实现指数退避重连策略

4. **VAD 分段方案（>5h 场景）**：
   - 使用 Silero VAD（轻量，Dart/Flutter 可通过 FFI 或平台通道调用）
   - 分段粒度：每 10-15 分钟一段，在静音处切割
   - 段间重叠 1-2 秒
   - 拼接时根据重叠区域去重

5. **文件存储优化**：
   - 长录音 WAV 文件体积大，考虑录音结束后自动转码 FLAC 存储
   - 或直接录音为 FLAC/MP3 格式（需评估 `record` 插件是否支持）

### 6.3 实施优先级

| 阶段 | 内容 | 工作量 | 价值 |
|------|------|--------|------|
| **P0** | 接入火山引擎异步录音文件识别 API，替换 Flash ASR | 中 | 核心能力，覆盖 3-5h 场景 |
| **P0** | WAV → FLAC/MP3 转码（录音完成后） | 小 | 解决文件体积问题 |
| **P1** | 实时 WebSocket 断线重连 + 本地缓冲 | 中 | 录音体验保障 |
| **P1** | 实时 ASR 结果降级为预览模式，全文以异步结果为准 | 小 | 识别质量保障 |
| **P2** | VAD 分段 + 多次提交（>5h 场景） | 大 | 极端场景兜底 |
| **P2** | 接入阿里云千问 ASR 作为备选通道 | 中 | 增强长音频能力上限 |
| **P3** | 本地 Whisper 小模型实时预览 | 大 | 离线能力，优化用户体验 |

---

## 来源

- [火山引擎语音转字幕 ASR 文档](https://www.volcengine.com/docs/6448/2381968)
- [火山引擎大模型录音文件识别标准版 API](https://www.volcengine.com/docs/6561/1354868?lang=en)
- [火山引擎数据智能体音频处理](https://www.volcengine.com/docs/85637/2477587)
- [阿里云非实时语音识别文档](https://help.aliyun.com/zh/model-studio/non-realtime-speech-recognition-user-guide)
- [阿里云 Fun-ASR 录音文件识别（12h/2GB）](https://www.alibabacloud.com/help/zh/model-studio/funauidio-asr-recorded-speech-recognition-python-sdk)
- [腾讯云语音识别功能相关](https://cloud.tencent.com/document/product/1093/35802)
- [腾讯云实时音视频录音文件识别（12h/1GB）](https://cloud.tencent.com/document/product/647/131299)
- [讯飞录音文件转写 API（5h/500MB）](https://www.xfyun.cn/doc/asr/ifasr_new/API.html)
- [讯飞录音文件转写大模型版](https://www.xfyun.cn/doc/spark/asr_llm/Ifasr_llm.html)
- [讯飞实时语音转写大模型版（8h/不限时长）](https://www.xfyun.cn/doc/spark/asr_llm/rtasr_llm.html)
- [Google Cloud Speech-to-Text Batch Recognize（8h）](https://docs.cloud.google.com/speech-to-text/docs/batch-recognize)
- [Google Cloud Speech-to-Text Quotas and Limits](https://docs.cloud.google.com/speech-to-text/docs/quotas)
- [Azure Speech Service Quotas and Limits](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits)
- [Azure Batch Transcription](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/batch-transcription)
- [OpenAI Whisper API 25MB 限制讨论](https://community.openai.com/t/whisper-api-increase-file-limit-25-mb/566754)
- [OpenAI Audio API FAQ](https://help.openai.com/en/articles/7031512-audio-api-faq)
- [AssemblyAI FAQ（10h/5GB）](https://assemblyai.com/docs/faq/are-there-any-limits-on-file-size-or-file-duration-for-files-submitted-to-the-api)
- [Deepgram Pre-recorded Audio（2GB）](https://developers.deepgram.com/docs/pre-recorded-audio)
- [Qualcomm AI Hub - Whisper Large V3 Turbo](https://aihub.qualcomm.com/mobile/models/whisper_large_v3_turbo)
- [whisper.cpp - Android Streaming Discussion](https://github.com/ggml-org/whisper.cpp/discussions/3567)
- [whisper.cpp GitHub Repository](https://github.com/ggml-org/whisper.cpp)
- [WhisperKit: On-device Real-time ASR (arXiv)](https://arxiv.org/html/2507.10860v1)
- [pyannote speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)
- [Whisper + Pyannote + FFmpeg Pipeline](https://medium.com/@rafaelgalle1/building-a-custom-scalable-audio-transcription-pipeline-whisper-pyannote-ffmpeg-d0f03f884330)
- [LLM-generated contextual information for domain-specific ASR (arXiv)](https://arxiv.org/html/2407.17874v1)
- [Switchboard Audio SDK - Local-First Hybrid Architecture](https://switchboard.audio/hub/ai-needs-to-run-on-device/)
- [Plaud AI - InfoQ 技术方案分析](https://www.infoq.cn/article/u9mtm5rtlcqhivbjs3ly)
- [通义听悟常见错误码](https://help.aliyun.com/zh/tingwu/support/)
- [AssemblyAI - WebSocket reconnection strategies](https://www.assemblyai.com/blog/best-api-models-for-real-time-speech-recognition-and-transcription)
- [Otter.ai 长录音处理速度分析（CSDN 评测）](https://www.cnblogs.com/ljbguanli/p/19105906)
- [讯飞听见 2025 横评（知乎）](https://zhuanlan.zhihu.com/p/1971634145772954503)
- [Riverside.fm Transcription](https://riverside.com/transcription)

---

## 七、异步 ASR 网络中断恢复机制（补充调研）

### 7.1 异步模式不存在"识别到一半"的概念

异步录音文件识别采用 **submit → query** 两步模式：
1. **Submit**：提交音频文件 URL（非上传音频数据流），服务端返回 `task_id`
2. **Query**：用 `task_id` 轮询结果，服务端独立处理，结果保留一段时间

**关键结论：不支持断点续识别，但也不需要。**

| 场景 | 影响 | 恢复方案 |
|------|------|---------|
| Submit 阶段网络中断 | 任务未成功提交，服务端无状态 | 重新提交即可，无副作用 |
| Query 阶段网络中断 | 服务端照常处理，任务不受影响 | 持久化 `task_id`，网络恢复后继续轮询 |
| 服务端处理自身失败 | 任务标记为 failed | 根据 error_code 决定重试或重新 submit |

### 7.2 客户端恢复策略

```
1. 提交任务后立即将 task_id 持久化到 SQLite
2. App 每次启动时检查未完成的 task_id，继续轮询
3. 网络中断不影响服务端处理，task_id 结果保留数小时
4. 对错误码 3030/3031/429/500 采用指数退避重试
```

---

## 八、音频文件上传对执行效率的影响（补充调研）

### 8.1 为什么需要对象存储

异步 ASR 要求提交音频文件的 **URL**（非直接上传），因此需要先将音频上传到对象存储（阿里云 OSS / 火山引擎 TOS），获取可公网访问的 URL。

### 8.2 上传耗时估算

| 录音时长 | WAV 大小 | MP3 64kbps | FLAC |
|---------|----------|------------|------|
| 5 分钟 | ~10MB | ~2.4MB | ~4MB |
| 30 分钟 | ~58MB | ~14MB | ~25MB |
| 1 小时 | ~115MB | ~29MB | ~50MB |
| 3 小时 | ~345MB | ~86MB | ~150MB |

上传耗时（国内网络，对象存储国内节点）：

| 网络环境 | 上行速度 | 3h WAV | 3h MP3 | 1h MP3 |
|---------|---------|--------|--------|--------|
| WiFi 家庭宽带 | ~30 Mbps | ~92s | **~23s** | **~8s** |
| 4G | ~10 Mbps | ~276s | **~69s** | **~23s** |
| 5G | ~50 Mbps | ~55s | **~14s** | **~5s** |

### 8.3 对流程的影响

**当前流程**（短录音）：
```
录音 → Flash ASR（直接发送文件，秒级） → LLM → 保存
```

**长录音流程**（新增上传步骤）：
```
录音 → 压缩转码 → 上传 OSS → submit 异步 ASR → 轮询等待 → LLM → 保存
```

新增总耗时（3h 录音 MP3）：

| 步骤 | 耗时 |
|------|------|
| WAV→MP3 转码（手机端） | ~10-30s |
| 上传 OSS（WiFi） | ~23s |
| ASR 异步处理等待 | ~3-10min（服务端排队） |
| **新增总耗时** | **~4-11min** |

### 8.4 优化策略：压缩 + 并行预览

**关键优化：实时 ASR 预览与后台上传并行**

```
录音结束
  ├── 实时 ASR 结果已可用（预览级质量）→ 立即展示给用户
  │
  └── 后台：压缩 → 上传 → 异步 ASR → 替换为高质量结果 → LLM
```

用户在录音结束时就能看到实时 ASR 的文字预览，**体感等待时间接近零**。异步 ASR 返回后再替换为高质量版本并触发 LLM 处理。

### 8.5 对象存储选型建议

| 维度 | 阿里云 OSS | 火山引擎 TOS |
|------|-----------|-------------|
| 与 ASR 服务同域 | 否（跨域下载） | 是（同域，更快） |
| 新增依赖 | 新开一个云服务 | 与现有火山引擎统一 |
| 分片上传/断点续传 | 支持 | 支持 |
| 移动端 SDK | 成熟 | 较新 |
| 带宽上限 | 10 Gbps/地域 | 类似 |

**建议**：优先评估火山引擎 TOS（与 ASR 服务同域，减少跨域延迟，统一账户管理），如 TOS 功能不足再考虑阿里云 OSS。

### 8.6 结论

| 场景 | 实际影响 | 用户体验 |
|------|---------|---------|
| <30 分钟录音 | 增加约 30-60s | 配合实时预览，体感影响小 |
| 1-3 小时录音 | 增加约 2-10min | 实时预览兜底，后台静默替换 |
| 3h+ 录音 | 增加约 5-15min | 同上，ASR 排队时间更长 |

**核心结论**：如果做好「压缩 + 并行预览」，上传阶段对用户体感的影响很小。真正的时间开销在 ASR 服务端异步处理，但用户此时已在看实时预览结果。

---

### 补充来源

- [OSS 使用限制及性能指标](https://help.aliyun.com/zh/oss/user-guide/limits)
- [OSS 分片上传](https://help.aliyun.com/zh/oss/user-guide/multipart-upload)
- [OSS 性能最佳实践](https://help.aliyun.com/zh/oss/user-guide/oss-performance-best-practices/)
- [OSS 上传下载速度慢排查](https://help.aliyun.com/zh/oss/the-speed-is-slow-when-you-upload-objects-to-or-download-objects-from-oss)

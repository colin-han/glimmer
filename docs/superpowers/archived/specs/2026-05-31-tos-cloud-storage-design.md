# TOS 云端录音存储设计方案

## 概述

将录音文件从纯本地存储升级为本地 + 火山引擎 TOS 云端存储。录音过程中实时编码为 OGG/Opus 格式，录音结束后上传至 TOS 智能分层存储桶，Flash ASR 改为从 TOS 预签名 URL 拉取音频识别。同时提供历史 WAV 文件的迁移能力。

## 背景

- 当前所有数据（audio.wav、transcript.json、llm_result.json）纯本地存储
- WAV 格式体积大（10 分钟 ≈ 19MB），上传和存储成本高
- 未来需要支持长录音、多人语音识别等场景，云端存储是基础
- 项目已深度绑定火山引擎生态（ASR + Doubao LLM），TOS 是同平台最优选择

## 决策记录

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 云存储平台 | 火山引擎 TOS | 与 ASR/LLM 同平台，内网互通免费，生态协同 |
| 存储类型 | 智能分层存储 | 录音上传后访问频率极低，自动在标准/低频层间迁移 |
| 上传方式 | 客户端直传（Access Key） | sideload APK，安全级别与现有 ASR/LLM 密钥一致 |
| 访问方式 | 预签名 URL | 安全性高，桶不公开，URL 有时效 |
| 音频格式 | OGG/Opus（32kbps） | 语音编码最优，10 分钟仅 ~2.4MB，ASR 完全支持 |
| 压缩方式 | PCM 实时双路编码 | 录音期间 PCM 同时送 ASR + Opus 编码器，录音结束即有 OGG 文件 |
| ASR 流程 | 串行：上传 → URL → ASR | 为长录音场景做好准备，一步到位 |
| 本地存储 | 新录音统一 OGG | 一份文件同时服务本地播放和云端上传 |

## 架构

### 改造后主流程

```
录音 (PCM stream, 16kHz/16bit/mono)
  ├─ 路径1: PCM → 实时 ASR (WebSocket) → 实时文字展示
  └─ 路径2: PCM → Opus 编码器 → audio.ogg 文件
                                         ↓
                                   录音结束
                                         ↓
                                   上传 audio.ogg 到 TOS
                                         ↓
                                   生成预签名 URL
                                         ↓
                                   Flash ASR 用 URL 识别
                                         ↓
                                   LLM 润色 → 本地保存 JSON + SQLite
```

### 文件变更清单

**新增文件**：
- `lib/services/tos_upload_service.dart` — TOS 上传、预签名 URL 生成
- `lib/services/audio_encoder_service.dart` — PCM → OGG/Opus 实时编码

**修改文件**：
- `lib/services/audio_recorder_service.dart` — PCM 流分流到编码器
- `lib/services/asr_service.dart` — Flash ASR 改为 URL 输入模式
- `lib/services/diary_storage_service.dart` — 音频播放兼容 OGG/WAV，迁移逻辑
- `lib/services/database/tables.dart` — 新增 tosKey、audioFormat、uploadedAt 字段
- `lib/services/database/app_database.dart` — Schema version 升级 + migration
- `lib/pages/recording_page.dart` — 主流程调整（上传 → ASR）
- `lib/models/diary_entry.dart` — 新增 TOS 相关字段
- `.env.local.example` — 新增 TOS 凭证变量

### 环境变量新增

```
VOLCENGINE_TOS_ACCESS_KEY=
VOLCENGINE_TOS_SECRET_KEY=
VOLCENGINE_TOS_ENDPOINT=tos-cn-beijing.volces.com
VOLCENGINE_TOS_BUCKET=your-bucket-name
```

## 关键服务设计

### AudioEncoderService

PCM → OGG/Opus 实时编码服务。

- **输入**：来自 `audioStream` 的 PCM 帧（16kHz, 16-bit, mono）
- **处理**：通过 `flutter_opus` FFI 逐帧编码为 Opus，封装到 OGG 容器
- **输出**：`audio.ogg` 文件
- **生命周期**：`start(outputPath)` 在录音开始时调用，`addPcmData(Uint8List)` 逐帧喂入，`stop()` 在录音结束时 flush 并关闭文件
- **编码参数**：Opus 应用类型 VOIP，码率 32kbps，单声道

### TosUploadService

TOS 上传与预签名 URL 生成。

- `uploadAudio(String localPath, String diaryId) → String tosKey`
  - 上传 `audio/{diaryId}.ogg` 到 TOS
  - 存储类型继承桶的智能分层策略
  - 返回 TOS 对象 key
- `getPresignedUrl(String tosKey, {int expiresSeconds = 3600}) → String url`
  - 生成预签名 URL，默认 1 小时有效
  - 用于 ASR 读取和未来音频播放

### AsrService 改造

Flash ASR 从本地文件模式切换为 URL 模式。

- **当前**：读取本地 WAV → base64 → POST 到 ASR API
- **改为**：接收预签名 URL → 发送 URL 给 ASR API
- **API 变更**：`codec` 参数设为 `ogg_opus`，音频通过 URL 字段传递而非 base64 body
- **需要验证**：Flash ASR API 的 URL 输入参数格式（可能需要调用"录音文件识别标准版"API 而非 Flash 版本）

### RecordingPage 主流程

```
1. 开始录音
   - 创建 PCM stream
   - 路径1: PCM → 实时 ASR (WebSocket, 显示中间结果)
   - 路径2: PCM → AudioEncoderService → audio.ogg
2. 录音结束
   - 编码器 flush，audio.ogg 完成
   - 上传 audio.ogg 到 TOS → 获得 tosKey
   - 生成预签名 URL
   - 用 URL 调 Flash ASR（精确识别，带时间戳）
   - 实时 ASR 中间结果与 Flash ASR 结果合并显示
3. LLM 润色（不变）
4. 保存结果
   - 写入 transcript.json + llm_result.json
   - 写入 SQLite 元数据（含 tosKey、audioFormat=ogg、uploadedAt）
5. TTS 播报 + 跳转详情页（不变）
```

## 数据模型变更

### DiaryEntries 表新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `tosKey` | Text | null | TOS 对象路径，如 `audio/uuid.ogg` |
| `audioFormat` | Text | `wav` | 音频格式：`ogg` 或 `wav` |
| `uploadedAt` | Int | null | 上传到 TOS 的时间戳（毫秒） |

### Migration

Schema version +1，通过 drift migration 添加三个新列。新字段均为 nullable 或有默认值，确保向后兼容。

## 数据迁移

### 已有 WAV 文件迁移

App 启动时检测并执行迁移：

1. 查询所有 `tosKey` 为 null 的日记条目
2. 对每个条目：
   a. 读取本地 `audio.wav` → 编码为 `audio.ogg`
   b. 上传 `audio.ogg` 到 TOS
   c. 更新 SQLite：`tosKey = 'audio/{id}.ogg'`, `audioFormat = 'wav'`（保留原格式标记）, `uploadedAt = now`
   d. 保留本地 `audio.wav`（不删除，待未来"释放空间"功能处理）
3. 迁移可中断恢复：通过 `tosKey` 是否为 null 判断进度

### 文件兼容读取

- 音频播放：优先找 `audio.ogg`，不存在则回退 `audio.wav`
- TOS URL 生成：根据 `tosKey` 字段生成，`tosKey` 为 null 表示未上传

## TOS 服务配置指南

以下步骤需要用户在火山引擎控制台操作：

### 1. 开通 TOS 服务

1. 登录 [火山引擎控制台](https://console.volcengine.com/)
2. 搜索"对象存储 TOS"或直接访问产品页
3. 点击"立即开通"（开通免费，按量计费）

### 2. 创建桶（Bucket）

1. 进入 TOS 控制台 → "桶管理" → "创建桶"
2. 配置：
   - **桶名称**：自定义（全局唯一，如 `glimmer-audio-{your-identifier}`）
   - **区域**：选择与 ASR 同区域（推荐 `华北2（北京）` / `cn-beijing`）
   - **存储类型**：**智能分层存储**
   - **冗余策略**：本地冗余（单 AZ）
   - **访问权限**：**私有读写**
3. 确认创建

### 3. 创建 Access Key

1. 火山引擎控制台 → 右上角头像 → "密钥管理"（或搜索 IAM）
2. 创建新的 Access Key
3. 权限配置：只授予 TOS 相关权限（最小权限原则）
   - 推荐创建 IAM 子用户，仅赋予 `TOSFullAccess` 或自定义策略限制到指定桶
4. 记录 Access Key ID 和 Secret Access Key

### 4. 配置环境变量

在 `.env.local` 中添加：

```
VOLCENGINE_TOS_ACCESS_KEY=your_access_key_id
VOLCENGINE_TOS_SECRET_KEY=your_secret_access_key
VOLCENGINE_TOS_ENDPOINT=tos-cn-beijing.volces.com
VOLCENGINE_TOS_BUCKET=your-bucket-name
```

### 5. 验证

配置完成后，启动 app 进行一次完整录音流程，确认：
- TOS 控制台能看到上传的 OGG 文件
- Flash ASR 成功从 URL 识别音频
- 本地 OGG 文件可以正常播放

## 风险与待验证项

1. **flutter_opus + OGG 容器封装**：flutter_opus 只提供 Opus 编解码，OGG 容器封装需要额外处理。实现时需验证是否有可用的 OGG muxing 库，或者需要自行实现 OGG 封装逻辑。若复杂度过高，备选方案为 `ffmpeg_kit_flutter`
2. **Flash ASR URL 输入模式**：需验证 Flash ASR API 是否支持直接传 URL，如果不支持，可能需要切换到"录音文件识别标准版"API（该版本明确支持 URL 输入）
3. **实时编码性能**：在低端 Android 设备上，双路处理（实时 ASR + Opus 编码）的 CPU 占用需实测
4. **TOS Flutter SDK 成熟度**：TOS Flutter SDK 为社区维护，如遇问题可能需要通过 HTTP API 直接调用

# V1 设计文档：录音 → ASR → LLM 总结

> 日期：2026-05-27
> 状态：已确认

## 目标

实现语音日记 App 的第一个可用版本。用户录音后，App 自动完成语音识别和大模型总结，生成结构化的日记条目。包含数据持久化和三页 UI。

## 范围

**包含**：录音、ASR 识别、LLM 单轮总结、数据持久化（SQLite + 文件）、三页 UI、音频播放

**不包含**：TTS 朗读、多轮反思式对话、标签/分类、搜索、备份（OSS）、后台录音、通知

## 项目结构

```
lib/
  main.dart                       — App 入口，路由定义
  models/
    diary_entry.dart              — 日记数据模型
  services/
    audio_recorder_service.dart   — 录音控制
    audio_player_service.dart     — 音频播放
    asr_service.dart              — 豆包 ASR 异步文件识别
    llm_service.dart              — 豆包 LLM 单轮总结
    diary_storage_service.dart    — SQLite 元数据 + 文件读写
  pages/
    recording_page.dart           — 录音页
    diary_list_page.dart          — 日记列表页
    diary_detail_page.dart        — 日记详情页
  widgets/
    recording_button.dart         — 录音按钮组件（含状态动画）
```

架构方案：按层分包。pages → services → models，依赖方向单一。

## 数据模型

### DiaryEntry

```dart
class DiaryEntry {
  final String id;            // UUID
  final String title;         // LLM 生成的标题（取正文前 20 字）
  final String folderPath;    // 该条日记的文件夹相对路径
  final int durationSeconds;  // 录音时长
  final DateTime createdAt;   // 创建时间
}
```

### SQLite Schema

```sql
CREATE TABLE diary_entries (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  folder_path TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  created_at INTEGER NOT NULL  -- Unix timestamp
);
```

SQLite 仅存索引和元数据，不存正文内容。

### 文件存储结构

```
应用文档目录/
  diaries/
    {uuid}/
      summary.md       — LLM 总结后的正文
      transcript.txt   — ASR 原始识别文本
      audio.m4a        — 录音原始文件
```

每条日记一个文件夹，所有相关文件集中管理。

## Service 层

### AudioRecorderService

- 插件：`record`
- 格式：AAC（m4a 容器）
- 方法：`startRecording(folderPath)`、`stopRecording()`、`isRecording`（状态流）
- 录音文件直接写入 `{uuid}/audio.m4a`
- 最大录音时长 5 分钟，到时自动停止
- 需请求 Android `RECORD_AUDIO` 权限

### AudioPlayerService

- 插件：`just_audio`
- 方法：`play(path)`、`pause()`、`stop()`、`seek(position)`、`setSpeed(rate)`
- 状态流：`isPlaying`、`position`、`duration`、`speed`
- 播放速度支持 1x / 1.5x / 2x
- 页面销毁时自动释放资源

### AsrService

- 接口：豆包「录音文件识别」（异步）
- 流程：
  1. 上传音频文件 → 获取任务 ID
  2. 轮询任务状态（间隔 2 秒）直到完成
  3. 取回识别文本
- 结果写入 `{uuid}/transcript.txt`
- HTTP 客户端：`dio`
- 认证：火山引擎 Access Key / Secret Key 签名

### LlmService

- 接口：豆包 Doubao（火山方舟）文本生成
- Prompt：将 transcript.txt 内容整理为通顺的日记正文，并生成标题
- 返回结构：`{ title: string, content: string }`
- HTTP 客户端：`dio`，使用火山方舟 OpenAI 兼容格式
- 认证：火山方舟 API Key + Endpoint ID
- 结果写入 `{uuid}/summary.md`

### DiaryStorageService

- 数据库：`drift` + `sqlite3_flutter_libs`
- 文件路径：`path_provider` 获取应用文档目录
- 方法：
  - `create(entry)` — 写 SQLite 元数据 + 确保 `{uuid}/` 文件夹存在
  - `getAll()` — 查全部日记（列表页用，按时间倒序）
  - `getById(id)` — 查单条（详情页用）
  - `writeSummary(id, content)` — 将 LLM 结果写入 `summary.md`
  - `writeTranscript(id, text)` — 将 ASR 结果写入 `transcript.txt`
  - `readSummary(id)` — 读取 `summary.md`
  - `readTranscript(id)` — 读取 `transcript.txt`
  - `delete(id)` — 删 SQLite 行 + 删整个 `{uuid}/` 文件夹

## 主流程

```
用户点击录音按钮
  → AudioRecorderService.startRecording()
  → 录音中（显示时长计时、波形动画）
  → 用户点击停止（或 5 分钟到时自动停止）
  → AudioRecorderService.stopRecording()
  → 状态：处理中（显示进度）

  → AsrService.transcribe(audioPath)  → 写 transcript.txt
  → LlmService.summarize(transcript)  → 写 summary.md + 更新 title
  → DiaryStorageService.create(entry)

  → 状态：完成 → 自动跳转详情页
```

链路顺序执行，每步失败明确提示用户。

## 页面设计

### 录音页 RecordingPage（首页 /）

- 居中大录音按钮（`RecordingButton` 组件）
- 按钮状态：
  - 待录音：麦克风图标
  - 录音中：红色脉冲动画 + 时长显示
  - 处理中：加载动画 + 三步进度指示（① ASR ② LLM ③ 保存）
- 处理中显示当前步骤文字："识别中..."、"总结中..."、"保存中..."
- 失败时显示错误信息 + 重试按钮
- 右上角"历史"按钮跳转列表页

### 日记列表页 DiaryListPage（/diary-list）

- 顶部标题"我的日记"
- 按时间倒序显示日记卡片：标题、创建日期、录音时长
- 右下角浮动"+"按钮跳转录音页
- 点击卡片跳转详情页
- 空状态提示："还没有日记，点击 + 开始录音"

### 日记详情页 DiaryDetailPage（/diary/:id）

- 标题区域：标题、创建时间、录音时长
- 音频播放条：播放/暂停按钮 + 进度条 + 时长 + 播放速度切换（1x / 1.5x / 2x）
- 正文区域：LLM 总结内容（Markdown 渲染，使用 `flutter_markdown`）
- 底部可展开区域：原始识别文本（transcript.txt）
- 右上角"删除"按钮（确认对话框）

## API Key 管理

- 密钥存储在 `.env.local` 文件，加入 `.gitignore`
- 项目提供 `.env.local.example`（仅含字段名，不含真实值）
- 使用 `flutter_dotenv` 在 App 启动时加载
- 配置项：

```
VOLCENGINE_ACCESS_KEY=xxx
VOLCENGINE_SECRET_KEY=xxx
VOLCENGINE_ARK_API_KEY=xxx
VOLCENGINE_ARK_ENDPOINT_ID=xxx
```

Service 层通过 `dotenv.get('KEY')` 读取。

## 错误处理

v1 不做自动重试，每步失败明确告知用户：

| 步骤 | 失败场景 | 用户提示 |
|---|---|---|
| 录音 | 无麦克风权限 | 引导去系统设置开启权限 |
| 录音 | 录音器初始化失败 | "录音启动失败，请重试" |
| ASR | 网络错误 / API 限流 | "语音识别失败，请检查网络" + 重试按钮 |
| ASR | 识别结果为空 | "未能识别语音内容" + 重试按钮 |
| LLM | 网络错误 / API 限流 | "AI 总结失败，请检查网络" + 重试按钮 |
| 存储 | 文件写入失败 | "保存失败" |
| 播放 | 音频文件不存在 | "音频文件不存在" |

可恢复的错误（ASR、LLM）提供重试按钮，从失败步骤重新开始，不丢弃已完成的步骤。

## 依赖清单

| 包 | 用途 |
|---|---|
| `record` | 录音（m4a/AAC） |
| `just_audio` | 音频播放 |
| `dio` | HTTP 请求（ASR、LLM） |
| `drift` + `sqlite3_flutter_libs` | SQLite ORM |
| `path_provider` | 应用文档目录 |
| `flutter_dotenv` | 加载 `.env.local` |
| `uuid` | 生成日记 ID |
| `flutter_markdown` | 渲染 Markdown 正文 |
| `intl` | 日期格式化 |

## 路由

```
/                → RecordingPage（首页）
/diary-list      → DiaryListPage
/diary/:id       → DiaryDetailPage
```

录音完成并处理成功后自动跳转到 `/diary/{id}`。从详情页返回时回到列表页。

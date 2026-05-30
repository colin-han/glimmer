# 带时间戳的语音识别与播放同步

## 背景

当前 ASR 返回纯文本，播放录音时无法同步显示对应文字。需要 ASR 返回句子级时间戳，LLM 润色时保留时间戳，播放时做句子级同步高亮。

## ASR 服务改动

**文件**：`lib/services/asr_service.dart`

- Flash ASR 请求中加入 `show_utterances: true`
- 返回值从 `String` 改为 `AsrResult`，包含：
  - `text`：完整文本
  - `utterances`：句子列表 `[{text, startTime, endTime}]`
- 如果返回不包含 utterances 字段，抛出异常（后续需切换到录音文件识别 API）

## 数据格式

### transcript.json（替代 transcript.txt）

```json
{
  "version": 1,
  "utterances": [
    {"text": "今天天气很好，", "startTime": 0, "endTime": 1705},
    {"text": "我想出去走走。", "startTime": 2110, "endTime": 3696}
  ]
}
```

时间单位为毫秒。

### summary_utterances.json（LLM 润色后的带时间戳文本）

```json
{
  "version": 1,
  "utterances": [
    {"text": "今天天气很好，", "startTime": 0, "endTime": 1705},
    {"text": "我想出去走走。", "startTime": 2110, "endTime": 3696}
  ]
}
```

### summary.md

保持不变，仍为 Markdown 格式的润色后正文。

## 系统存储版本管理

- 使用 SharedPreferences 存储系统存储版本号
- 当前版本：`storage_version = 1`（无版本号视为 0）
- 0→1 migration：清除所有现有日记数据（数据库 + 文件）
- 启动时检查版本号，自动运行 migration

## LLM 润色保留时间戳

**文件**：`lib/services/llm_service.dart`

- 输入：带 utterances 的结构化数据（不再传纯文本）
- prompt 规则：
  - 润色文本内容但保留时间戳
  - 合并多个片段时取第一个的 startTime 和最后一个的 endTime
  - 拆分片段时保持原始时间戳不变
- 输出格式改为：
```json
{
  "title": "标题",
  "content": "Markdown 正文",
  "utterances": [
    {"text": "润色后的句子", "startTime": 0, "endTime": 1705},
    ...
  ]
}
```

## 存储服务改动

**文件**：`lib/services/diary_storage_service.dart`

- 新增 `writeTranscriptJson` / `readTranscriptJson` 方法
- 新增 `writeSummaryUtterances` / `readSummaryUtterances` 方法
- 移除 `writeTranscript` / `readTranscript` 方法

## 录音页面改动

**文件**：`lib/pages/recording_page.dart`

- `_stopAndProcess` 中使用新的 `AsrResult` 返回类型
- 保存 `transcript.json` 替代 `transcript.txt`
- 保存 `summary_utterances.json`

## 播放同步 UI

**文件**：`lib/pages/diary_detail_page.dart`、新增 `lib/widgets/timestamped_text_view.dart`

- 读取 `summary_utterances.json` 中的 utterances
- 监听播放器的 `positionStream`
- 当前播放位置匹配 `startTime <= position < endTime` 的句子高亮
- 已播放句子变灰，当前句子高亮，未播放句子正常显示
- 点击句子跳转到对应播放位置

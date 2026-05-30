# LLM 四段输出改造设计

## 背景

当前 LLM 返回 `{title, content, oneLineSummary}`，其中 `oneLineSummary` 用于 TTS 播报。需要扩展为更丰富的四段输出，提升日记的提炼质量和 TTS 播报体验。

## LLM 输出结构

从 3 字段改为 4 字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `title` | String | 标题，≤20字，保持现有逻辑 |
| `content` | String | 润色正文，Markdown 格式，保持现有提示词 |
| `summary` | String | 日记体提炼，Markdown 格式，**新增** |
| `outline` | String | 口语化播报文本，**替换 oneLineSummary** |

### content 提示词（保持现有）

保留原文句子结构和用词，去口语填充词，适当书面化，按语义分段。

### summary 提示词（新增）

- 以第一人称「我」为视角，写一篇精炼版日记
- 保留原文中的情感、感受、思考
- 合并相似内容，省略无关紧要的细节
- 自然流畅，300-500字，不要分条列举
- Markdown 格式

### outline 提示词（替换 oneLineSummary）

- 输出一段完整的口语化播报文本，不是条目列表
- 从原文中提炼最重要的前5个主题/事件
- 口语化、适合 TTS 朗读
- 超过5个主题时，末尾补充「还有其他几条，就不一一念了」类的收尾
- 示例：「日记整理完成，今天讨论了很多事情：首先是工作上的项目进展；然后是关于周末旅行的计划；还提到了最近在读的一本书；另外聊了聊和朋友聚餐的事。此外还有一些其他内容，就不一一念了。」

## 存储变更

- 新增 `llm_result.json`，存储 `{title, content, summary, outline}`
- 废弃 `summary.md`，不再生成
- `transcript.txt` 保持不变

每个日记文件夹结构变为：

```
<uuid>/
  audio.wav
  transcript.txt
  llm_result.json    ← 新（替换 summary.md）
```

## 详情页调整

`diary_detail_page.dart` 展示优先级调整：

1. **主视图**：展示 `summary`（日记体提炼），Markdown 渲染
2. **折叠区 1**：「润色正文」ExpansionTile，展示 `content`
3. **折叠区 2**：「原始识别文本」ExpansionTile，展示 `transcript`（保持不变）

## TTS 播报调整

- 废弃 `generateSummaryAnnouncement` 方法 — 不再需要第二轮 LLM 调用
- `_speakSummary` 直接使用 `llmResult.outline` 播报，无需拼接
- 播报语音保持 `VoiceType.maleDeep`

## 涉及文件

| 文件 | 变更 |
|------|------|
| `lib/services/llm_service.dart` | LlmResult 改 4 字段，提示词重写，解析逻辑调整，删除 `generateSummaryAnnouncement` |
| `lib/services/diary_storage_service.dart` | 新增 `writeLlmResult`/`readLlmResult`，废弃 `writeSummary`/`readSummary` |
| `lib/pages/diary_detail_page.dart` | 展示逻辑调整：summary 为主，content 折叠 |
| `lib/pages/recording_page.dart` | TTS 播报逻辑：用 outline 替换 oneLineSummary |

## 向后兼容

- 旧日记仍持有 `summary.md` 而无 `llm_result.json`
- `diary_detail_page.dart` 读取时需兼容：优先读 `llm_result.json`，不存在则回退读 `summary.md`
- 回退时 summary 和 content 都展示为 `summary.md` 的内容

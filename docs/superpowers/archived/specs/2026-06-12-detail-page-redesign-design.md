# 日记详情页重构设计

## 目标

重新设计日记详情页布局，分为四个从上到下的区块：标题栏、信息栏、播放器区域、润色正文。移除「原始识别文本」展示。

## 方案

拆分为独立子组件，每个组件放在 `lib/widgets/detail/` 目录下。

## 组件拆分

| 文件 | 职责 |
|------|------|
| `lib/widgets/detail/detail_info_bar.dart` | 信息栏 |
| `lib/widgets/detail/detail_player_section.dart` | 播放器区域 |
| `lib/widgets/detail/detail_content_section.dart` | 润色正文 |
| `lib/pages/diary_detail_page.dart` | 组装层，负责数据加载和传递 |

子组件自身无数据加载逻辑，通过 props 接收数据。

---

## 1. AppBar（原地修改）

保持现有结构：返回按钮 + 标题（Flexible + ellipsis）+ dev badge + 删除按钮。

## 2. DetailInfoBar

**Props:** `entry: DiaryEntry`

**布局：** 横向排列，空格分隔：

```
📅 2026年6月12日 14:30  ⏰ 3:25  📍 北京  ☀️ 晴 25°C
```

**数据映射：**
- 日期：`entry.formattedDate`
- 时间：从 `entry.createdAt` 格式化为 `HH:mm`
- 时长：`entry.durationDisplay`
- 位置：`entry.locationName`（图标 📍）
- 天气：`entry.weatherText`（图标取自 `entry.weatherIcon`）
- 温度：`entry.temperature`

**规则：**
- 所有可选字段（位置、天气、温度）为空时整块不渲染
- 样式：`bodySmall`，灰色调

## 3. DetailPlayerSection

**Props:**
- `playerService: AudioPlayerService`
- `audioFilePath: String`
- `utterances: List<Utterance>` — 优先 LLM 结果，无则回退 TranscriptData.utterances
- `hasTranscript: bool` — 是否有识别文本

**收起状态布局：**

```
┌─────────────────────────────────────┐
│  [AudioPlayerBar 现有播放器]          │
├─────────────────────────────────────┤
│  当前播放的那句话（单行，截断）      │  ← 字幕行（无复制按钮）
│  ▼ 展开识别文本                      │  ← 下箭头按钮
└─────────────────────────────────────┘
```

**展开状态布局：**

```
┌─────────────────────────────────────┐
│  [AudioPlayerBar 现有播放器]          │
├─────────────────────────────────────┤
│  当前播放的那句话（单行，截断）      │  ← 字幕行
│  ▲ 收起识别文本                      │
├─────────────────────────────────────┤
│  全部识别文本（固定高度 ~200px，  📋│  ← 展开区域 + 右上角复制按钮
│  可滚动，当前句高亮，点击可跳转）    │
└─────────────────────────────────────┘
```

**字幕行行为：**
- 监听 `positionStream`，找到 `startTime ≤ position < endTime` 的 utterance
- 单行 `Text`，`overflow: TextOverflow.ellipsis`
- 点击字幕跳转到对应 utterance 的 `startTime`

**展开区域行为：**
- 固定高度容器（约 200px）+ `SingleChildScrollView`
- 当前句高亮，点击任意句跳转播放位置
- 右上角复制按钮：复制全部 utterances 的 `text` 拼接（纯文本，无时间戳）

**无识别文本时：**
- 不显示字幕行
- 不显示展开按钮
- 只显示 `AudioPlayerBar`

## 4. DetailContentSection

**Props:** `content: String`（Markdown 格式）

**布局：**

```
┌─────────────────────────────────────┐
│  润色正文                        📋  │  ← 右上角复制按钮
│  ─────────────────────────────────  │
│  MarkdownBody 渲染后的正文内容      │
└─────────────────────────────────────┘
```

**行为：**
- 点击复制按钮：复制 `content` 原始文本到剪贴板，弹出 SnackBar "已复制"
- 无 LLM 结果时整个组件不渲染

## 5. 页面组装（diary_detail_page.dart）

**build 布局（从上到下）：**
1. AppBar（返回 + 标题 + dev + 删除）
2. `DetailInfoBar`
3. 标签行（复用现有标签逻辑）
4. `DetailPlayerSection`
5. `_buildStatusBanner()` 处理中/失败横幅
6. `DetailContentSection`

**数据传递：**
- `utterances`：优先取 `LlmResultData.utterances`，无则回退 `TranscriptData.utterances`
- `hasTranscript`：`_transcriptExists || _hasLlm`

## 移除项

- 「原始识别文本」ExpansionTile
- 详情页中对 `TimestampedTextView` 的直接使用（其逻辑内化到 `DetailPlayerSection`）
- 对 `_summary` 的 `MarkdownBody` 直接渲染

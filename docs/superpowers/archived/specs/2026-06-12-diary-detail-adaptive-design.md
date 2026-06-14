# 日记详情页自适应展示设计

## Context

当前日记详情页只允许 `status=completed` 的条目进入。`processing` 条目在列表页不可点击，`failed` 条目点击直接重试。

**目标**：只要日记条目有本地音频文件，就可以从列表页点击进入详情页。详情页根据数据文件的实际完整性渐进展示内容。

## 设计决策

- **方案**：基于文件探测的渐进展示（方案 A）。检测 `audio.*` → `transcript.json` → `llm_result.json` 的存在性决定展示层级。
- **理由**：`processingStage` 字段可能与实际文件不同步（进程崩溃时），文件是数据真实状态的唯一可靠来源。

## 数据层级

| 层级 | 文件 | 展示内容 |
|------|------|----------|
| 0 | 无音频 | 不应进入详情页（列表页不展示点击） |
| 1 | 仅音频 | 音频播放器 + 处理状态横幅 |
| 2 | 音频 + transcript.json | + 原始识别文本（ExpansionTile） |
| 3 | 音频 + transcript.json + llm_result.json | + 播报大纲 + 润色正文 + 标签 |

## 页面结构

```
┌─────────────────────────────────┐
│ AppBar: 标题 + 删除按钮          │
├─────────────────────────────────┤
│ 元信息行: 日期 时长 天气          │  ← 始终显示
│ 标签行 / 处理中占位              │  ← LLM 完成前显示「⏳ 处理中...」
├─────────────────────────────────┤
│ 🔊 音频播放器                    │  ← audio.* 存在时显示
├─────────────────────────────────┤
│ 处理状态横幅                     │  ← processing/failed 时显示
├─────────────────────────────────┤
│ 原始识别文本 (ExpansionTile)     │  ← transcript.json 存在时
├─────────────────────────────────┤
│ 播报大纲 / 润色正文 (ExpansionTile) │ ← llm_result.json 存在时
└─────────────────────────────────┘
```

## 各区域详细设计

### 元信息行

始终显示：日期时间、时长、天气。与现有行为一致。

### 标签行

- **LLM 未完成**（`llm_result.json` 不存在）：显示灰色文本 `⏳ 处理中...`
- **LLM 已完成**：显示标签 Chip 列表 + 添加标签按钮。与现有行为一致。

### 音频播放器

- 音频文件存在：显示 `AudioPlayerBar`。与现有行为一致。
- 音频文件不存在：不显示（不应出现此情况，因为有音频才允许进入）。

### 处理状态横幅

仅在 `status=processing` 或 `status=failed` 时显示。`completed` 时不显示。

**processing 状态**：
```
┌──────────────────────────────────────┐
│ 🔄 正在处理: 语音识别中...            │
│ ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░  35%  │
└──────────────────────────────────────┘
```
- 显示当前阶段文字：`上传中...` → `语音识别中...` → `AI 总结中...` → `自动归类中...`
- 使用 `LinearProgressIndicator`（indeterminate 模式，因为无法获取精确进度）
- 详情页监听 FGS 消息，收到 `completed` 后自动重新加载内容，横幅消失

**failed 状态**：
```
┌──────────────────────────────────────┐
│ ❌ 处理失败: 语音识别失败              │
│                          [重新处理]    │
└──────────────────────────────────────┘
```
- 显示红色背景的失败提示
- 「重新处理」按钮点击后触发重试流程，切换为 processing 展示

### 内容区域

- **transcript.json 存在**：显示「原始识别文本」ExpansionTile（默认折叠）
- **llm_result.json 存在**：
  - 显示「播报大纲」（summary）+ 时间戳关联
  - 显示「润色正文」ExpansionTile（content，默认折叠）
  - 与现有详情页内容展示逻辑一致

## 列表页改动

**`_buildEntryCard`**：
- `processing` 条目：可点击，右侧保留转圈指示器
- `failed` 条目：可点击，右侧改为 chevron 图标（移除重试按钮）
- `completed` 条目：行为不变

所有可点击条目统一跳转到 `DiaryDetailPage(entry: entry)`。

## 关键文件

- `lib/pages/diary_detail_page.dart` — 主要改动，重写 `_loadContent()` 和 `build()`
- `lib/pages/diary_list_page.dart` — `_buildEntryCard()` 改为统一可点击

## 实现要点

1. `_loadContent()` 改为基于文件探测，不依赖 `status` 字段
2. 新增 `_buildStatusBanner()` 渲染 processing/failed 横幅
3. 详情页注册 `FlutterForegroundTask.addTaskDataCallback` 监听处理完成
4. 收到 `completed` 消息后自动重新加载内容
5. 列表页 `_buildEntryCard` 中 `isProcessing`/`isFailed` 不再拦截点击

## 验证

1. 录音 → 停止 → 在 processing 状态点击列表项 → 进入详情页，看到进度横幅 + 音频播放器
2. 等待处理完成 → 详情页自动刷新，进度横幅消失，内容渐次出现
3. 手动制造 failed 条目 → 列表点击进入 → 看到失败横幅 + 重试按钮
4. 点击重试 → 切换为 processing 展示 → 完成后自动刷新
5. completed 条目 → 与现有行为一致

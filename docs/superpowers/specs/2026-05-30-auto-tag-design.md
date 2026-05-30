# 自动归类功能设计文档

## 概述

为语音日记 App 增加 tag（标签）系统，支持多标签、自动归类、手动管理、搜索和分组展示。

## 1. 数据模型

### 1.1 数据库 Schema（v1 → v2 迁移）

新增两张表：

**Tags 表**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT (UUID) | 主键 |
| name | TEXT | tag 名称，唯一约束 |
| matchPrompt | TEXT | LLM 匹配提示词，可为空字符串 |
| color | TEXT | 显示颜色（hex 字符串），可为空 |
| createdAt | INTEGER | 创建时间戳（毫秒） |

**DiaryTagRelations 表**

| 字段 | 类型 | 说明 |
|------|------|------|
| diaryId | TEXT | 外键 → DiaryEntries.id |
| tagId | TEXT | 外键 → Tags.id |
| source | TEXT | 来源标记：`auto`（LLM 自动）/ `manual`（手动） |
| createdAt | INTEGER | 关联时间戳（毫秒） |

联合主键：(diaryId, tagId)

### 1.2 LLM 自动打 Tag 机制

录音完成后，在 LLM 润色正文之后发起第二次 LLM 调用：

- **输入**：润色后的正文 + 所有含 matchPrompt 的 tag（id, name, matchPrompt）
- **输出**：匹配的 tag ID 列表
- source 标记为 `auto`

如果没有 tag 有 matchPrompt，跳过此步。

## 2. Tag 管理页面

**入口**：日记列表页 AppBar 上的管理图标。

### 2.1 功能

- 展示所有 tag 列表（名称 + 匹配的日记数量）
- 新增 tag
- 编辑 tag（名称、匹配提示词、颜色）
- 删除 tag（同时解除所有日记关联）

### 2.2 新建 Tag 流程

1. 用户输入 tag 名称
2. **LLM 调用 1 — 推荐日记**：发送 tag 名称 + 所有日记的 (id, title, summary 前 200 字)，LLM 返回推荐的 diaryId 列表 + 理由
3. 展示推荐列表，用户勾选确认
4. **LLM 调用 2 — 生成提示词**：基于 tag 名称 + 用户确认的日记摘要，生成匹配提示词
5. 用户可编辑提示词，保存

## 3. 日记列表页改造

### 3.1 搜索框

顶部搜索栏，搜索范围：**标题 + 正文**（不含原始转写）。搜索时保持分组显示。

实现方式：标题用 SQLite LIKE 匹配，正文在搜索时读取 llm_result.json 中的 content 字段做文本匹配。

### 3.2 Tag Chip 过滤条

搜索框下方，横向可滚动的 chip 列表。Tag chip 过多时折行显示。行末右侧固定放置 📅/🏷️ 分组切换图标（始终右对齐）。

- 「全部」chip + 各 tag chip
- 点击 chip 过滤该 tag 的日记，再点取消过滤

### 3.3 分组模式

右侧末尾的 📅/🏷️ 图标按钮切换分组模式：

- **按日期**（默认）：今天（5月30日）、昨天（x月x日）、周x（x月x日），超过两周直接显示日期
- **按标签**：每个 tag 是一个分组，显示该 tag 下的日记数量和条目列表

### 3.4 日记卡片

标题下方显示 tag chip（小号、紧凑样式）。

### 3.5 AppBar

增加 tag 管理图标入口。

## 4. 日记详情页改动

### 4.1 显示 Tag

标题区域下方展示当前日记的 tag chip。

### 4.2 手动管理 Tag

- 点击 + 按钮弹出 tag 选择（已创建的 tag 列表，多选）
- 可移除已有 tag
- 支持内联创建新 tag（输入名称快速创建，后续可在管理页编辑提示词）

### 4.3 匹配提示词编辑

手动添加/删除 tag 后，自动弹出 BottomSheet：

- 显示该 tag 当前的 matchPrompt
- 用户可编辑并保存，或点击跳过
- 移除 tag 时也弹出，提示"是否调整匹配规则以避免误匹配"

## 5. 录音流程改动

### 5.1 流程步骤

**原流程（4 步）**：语音识别 → 保存原文 → AI 总结 → 完成

**新流程（5 步）**：语音识别 → 保存原文 → AI 总结 → **自动归类** → 完成

### 5.2 防御性保存策略

| 步骤 | 完成后立即保存 | 说明 |
|------|---------------|------|
| 1. ASR 识别 | transcript.json | 音频转写结果持久化 |
| 2. LLM 润色 | llm_result.json + 写入 DiaryEntries（标题/元数据） | 关键保存点：LLM 结果 + 元数据入库 |
| 3. 自动打 Tag | 写入 DiaryTagRelations | 在 LLM 已保存基础上追加 tag 关联，失败不回滚 |
| 4. 导航 | 跳转详情页 | - |

步骤 2 完成后立即保存元数据，防止步骤 3 执行中进程被杀导致 LLM 结果丢失。

### 5.3 重试机制兼容

详情页的 `_retry()` 方法需要调整，在 LLM 重试成功后追加自动打 tag 步骤：

- **检测逻辑不变**：`_needsRetry` 仍检测 transcript/llm_result 是否缺失
- **重试流程扩展**：LLM 成功 → 保存 llm_result + 更新标题 → **执行自动打 tag**（同录音流程步骤 3）
- 步骤 2 之前被杀 → 详情页走 ASR/LLM 重试 → 成功后自动打 tag
- 步骤 2 完成、步骤 3 被杀 → 详情页正常展示（无 `_needsRetry`），只是没有自动 tag

### 5.4 步骤进度指示器

更新为 5 步：语音识别 → 保存原文 → AI 总结 → 自动归类 → 完成

## 6. 涉及的文件

### 新增文件

- `lib/models/tag.dart` — Tag 和 DiaryTagRelation 数据模型
- `lib/pages/tag_management_page.dart` — Tag 管理页面
- `lib/widgets/tag_chip_bar.dart` — Tag Chip 过滤条组件
- `lib/widgets/tag_editor_sheet.dart` — 匹配提示词编辑 BottomSheet
- `lib/widgets/tag_selector_sheet.dart` — Tag 选择/内联创建 BottomSheet

### 修改文件

- `lib/services/database/tables.dart` — 新增 Tags、DiaryTagRelations 表定义
- `lib/services/database/app_database.dart` — Schema v2 迁移，新增 DAO 方法
- `lib/services/diary_storage_service.dart` — 新增 tag 相关 CRUD 方法
- `lib/services/llm_service.dart` — 新增自动打 tag 和新建 tag 推荐的 LLM 调用
- `lib/pages/recording_page.dart` — 新增步骤 3 自动打 tag，更新步骤指示器
- `lib/pages/diary_list_page.dart` — 搜索、分组、tag chip 过滤、管理入口
- `lib/pages/diary_detail_page.dart` — Tag 显示、手动管理、提示词编辑
- `lib/widgets/step_progress_indicator.dart` — 步骤从 4 步更新为 5 步

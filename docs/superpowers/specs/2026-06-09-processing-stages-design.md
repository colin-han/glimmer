# 录音处理阶段设计文档

## 概述

一条日记从录音到最终完成，经历 6 个阶段。每个阶段有明确的输入/输出和失败恢复策略。
阶段信息持久化到数据库，确保进程被中断后能从正确的阶段恢复，避免重复工作。

## 处理阶段定义

| 阶段 | processingStage | 名称 | 执行环境 | 类型 | 产物 |
|------|-----------------|------|----------|------|------|
| 1 | — (录制中不创建条目) | 录制 | Recording FGS (microphone) | 前台同步 | audio.ogg 文件 |
| 2 | `uploading` | 上传 | Processing FGS (dataSync) | 同步 | tosKey |
| 3 | `asr` | ASR 识别 | Processing FGS (dataSync) | 异步 | transcript.json |
| 4 | `llm` | LLM 润色汇总 | Processing FGS (dataSync) | 同步 | llm_result.json |
| 5 | `tagging` | 标签归类 | Processing FGS (dataSync) | 同步 | diary_tag_relations |
| 6 | `completed` | 完成 | — | — | 条目可展示 |

## 各阶段详细设计

### 阶段 1：录制

- **执行环境**：Recording FGS（foregroundServiceType = microphone）
- **特性**：始终在前台执行，用户可见
- **产物**：UUID 文件夹内含 `audio.ogg` 文件
- **失败处理**：如果录制阶段失败，说明连文件都没创建成功，**这条日记条目根本不应该存在于数据库中**。直接清理临时文件，不创建任何 DB 记录
- **阶段结束时**：
  - 文件系统：`{uuid}/audio.ogg` 已保存
  - 数据库：`INSERT` 一条新记录（title="正在处理中..."，processingStage='uploading'，status=processing）
  - Recording FGS 停止，任务数据传递给主 isolate

> **注意**：阶段 1 结束时直接将 processingStage 设为 `uploading`，表示下一个要执行的阶段是上传。
> processingStage 的含义是"当前/下一个要执行的处理阶段"。

### 阶段 2：上传

- **执行环境**：Processing FGS（foregroundServiceType = dataSync）
- **输入**：`audio.ogg` 本地文件
- **产物**：`tosKey`（上传到 TOS 后的对象存储 key）
- **类型**：同步（PutObject 单次 PUT 请求）
- **失败恢复**：重新上传整个文件

#### 关于断点续传

调研结论：TOS 支持分片上传（Multipart Upload），但**当前场景不需要实现**：
- 音频文件通常 1-5 分钟，OGG 格式约几 MB
- PutObject 简单上传支持最大 5GB，完全满足
- 分片上传最小分片 4MiB，小文件分片没有意义
- 实现复杂度高（3 次 API + 独立签名），收益低

因此**不需要为阶段 2 添加阶段内中间状态**。只要 processingStage='uploading'，就意味着需要重新上传。

**后续优化方向**：如果未来支持长录音（>30 分钟，文件 >50MB），可以引入分片上传并增加 `uploadId` 等中间状态字段。

### 阶段 3：ASR 识别

- **执行环境**：Processing FGS（foregroundServiceType = dataSync）
- **输入**：tosKey（通过预签名 URL 传给 ASR）
- **产物**：`transcript.json`（带时间戳的识别文本 utterances[]）
- **类型**：异步（提交识别任务 → 轮询状态 → 获取结果）

#### 分步流程

```
3a. 提交识别请求 → 获得 asrTaskId
    → UPDATE processingStage='asr', asrTaskId=xxx
3b. 轮询识别状态（GET /task/status?taskId=xxx）
    → 直到状态为 completed 或 failed
3c. 获取识别结果 → 写入 transcript.json
    → processingStage 推进到 'llm'
```

#### 中断恢复

- 如果 processingStage='asr' 且 asrTaskId 不为空 → 直接查询该任务的识别状态，**不重新提交识别**
- 如果 processingStage='asr' 且 asrTaskId 为空（3a 未完成就中断）→ 重新提交识别请求
- 如果 ASR 识别结果为 failed → 标记整条日记为 failed，用户手动重试时清除 asrTaskId 重新走 3a

#### 数据库变更

```sql
ALTER TABLE diary_entries ADD COLUMN asr_task_id TEXT;  -- ASR 任务 ID
```

### 阶段 4：LLM 润色汇总

- **执行环境**：Processing FGS（foregroundServiceType = dataSync）
- **输入**：transcript.json 中的 utterances[]
- **产物**：`llm_result.json`（title / content / summary / outline）
- **类型**：同步（单次 API 调用，流式返回）
- **失败恢复**：重新发起 LLM 请求。输入（transcript.json）已持久化，不需要重新 ASR

#### 中断恢复

- 如果 processingStage='llm' → 重新发起 LLM 请求（transcript.json 已存在）
- 如果 processingStage 为 'tagging' 或 'completed' → 跳过此阶段

### 阶段 5：标签归类

- **执行环境**：Processing FGS（foregroundServiceType = dataSync）
- **输入**：llm_result.json 中的 content + 数据库中的标签列表
- **产物**：diary_tag_relations 表记录
- **类型**：同步（单次 LLM 调用）
- **失败恢复**：重新发起标签匹配请求。此阶段**不阻塞**（失败不影响日记完成）

#### 中断恢复

- 如果 processingStage='tagging' → 重新发起标签匹配
- 如果 processingStage='completed' → 跳过此阶段

### 阶段 6：完成

- 数据库条目 status 改为 completed
- processingStage 改为 'completed'
- 通知 UI 刷新

## 数据库 Schema 变更

```dart
// diary_entries 表新增字段
TextColumn get processingStage => text().withDefault(const Constant('uploading'))();
TextColumn get asrTaskId => text().nullable()();
```

- `processingStage`：字符串枚举，含义为"当前/下一个要执行的处理阶段"
  - `'uploading'` = 待上传
  - `'asr'` = ASR 处理中/待 ASR
  - `'llm'` = 待 LLM 润色汇总
  - `'tagging'` = 待标签归类
  - `'completed'` = 已完成（与 status=completed 对应）
- `asrTaskId`：ASR 异步任务 ID，用于中断后直接查询识别状态

## 恢复逻辑伪代码

```
恢复处理(entry):
  switch entry.processingStage:
    case 'uploading':
      重新上传音频 → 成功后 stage='asr'
    case 'asr':
      if entry.asrTaskId != null:
        直接查询 ASR 状态 → 获取结果 → 写 transcript.json → stage='llm'
      else:
        提交 ASR 请求 → 记录 asrTaskId → 查询状态 → 获取结果 → stage='llm'
    case 'llm':
      读 transcript.json → 调 LLM → 写 llm_result.json → stage='tagging'
    case 'tagging':
      读 llm_result.json → 调 LLM 标签匹配 → 写 diary_tag_relations → stage='completed'
    case 'completed':
      标记 completed → 完成
```

## 日记条目状态迁移

```
                ┌─────────────┐
                │   不存在     │
                └──────┬──────┘
                       │ R1: INSERT (stage='uploading')
                       ▼
                ┌─────────────┐
          ┌────▶│  processing  │◀────┐
          │     └──────┬──────┘     │
          │            │ 全部完成    │ 用户重试
          │            ▼            │
          │     ┌─────────────┐     │
          │     │  completed   │     │
          │     └─────────────┘     │
          │                         │
          │ 任意步骤失败              │
          │            ┌────────┐   │
          └────────────│ failed │───┘
                       └────────┘
```

- `processing`：日记条目正在处理中（processingStage 标识具体阶段）
- `completed`：处理完成（processingStage='completed'）
- `failed`：处理失败，可通过重试回到 processing（processingStage 保持中断时的值）

## 处理阶段与产物的对应关系

```
阶段  录制         上传          ASR           LLM           标签         完成
      │            │             │             │             │            │
文件  audio.ogg    —            transcript     llm_result    —           —
                                .json          .json
      │            │             │             │             │            │
DB    INSERT       tosKey       asrTaskId     —             —            status=
      stage=       stage=       stage=                                    completed
      'uploading'  'asr'        'llm'                                     stage=
                                                                          'completed'
```

## 双 FGS 架构

`flutter_foreground_task` 同时只能运行一个 FGS。系统使用两个互斥的 FGS 来保证录音和处理都不会被系统杀掉。

### 两个 FGS 的职责

| | Recording FGS | Processing FGS |
|---|---|---|
| **类型** | microphone | dataSync |
| **职责** | 阶段 1（录制） | 阶段 2~5（上传/ASR/LLM/标签） |
| **运行时机** | 用户点击录音 → 点击停止 | 录音结束后，直到队列清空 |
| **运行环境** | 独立 Dart isolate（TaskHandler） | 独立 Dart isolate（TaskHandler） |
| **数据传递** | 通过 sendDataToMain 发给主 isolate | 通过 sendDataToMain 发给主 isolate |

### FGS 切换时序

```
用户点击录音
  │
  ├─ 1. 主 isolate: stopService()（停掉可能正在运行的 Processing FGS）
  ├─ 2. 主 isolate: startService(microphone, RecordingTaskHandler)
  ├─ 3. Recording FGS: 录音中...
  │
用户点击停止
  │
  ├─ 4. Recording FGS: 保存音频 → INSERT DB 条目 → stopService() → 通知主 isolate
  ├─ 5. 主 isolate: 收到完成消息 → 任务入队
  ├─ 6. 主 isolate: startService(dataSync, ProcessingTaskHandler)
  ├─ 7. Processing FGS: 按 processingStage 恢复/开始处理...
  │
（用户再次点击录音）
  │
  ├─ 8. 主 isolate: stopService()（中断 Processing FGS）
  ├─ 9. Processing FGS: onDestroy() → 当前任务保留 processingStage（已写入 DB）
  ├─ 10. 主 isolate: startService(microphone, RecordingTaskHandler)
  ├─ 11. Recording FGS: 新录音...
  │
用户停止新录音
  │
  ├─ 12. Recording FGS: 保存 → INSERT → stopService() → 通知主 isolate
  ├─ 13. 主 isolate: 新任务入队（排在之前中断的任务后面）
  ├─ 14. 主 isolate: startService(dataSync, ProcessingTaskHandler)
  ├─ 15. Processing FGS: 处理队列（先处理之前中断的任务，再处理新任务）
```

### Processing FGS 中断设计

**中断时机**：用户点击开始新录音时，主 isolate 调用 `stopService()`

**中断行为**：
1. Processing FGS 的 `onDestroy()` 被调用
2. 此时当前正在处理的任务的 `processingStage` 已经在各个步骤中逐步更新到 DB（每次推进阶段都会 `UPDATE`）
3. 因此中断时不需要额外的保存操作——DB 中的 `processingStage` 值就是准确的恢复点
4. 被中断的任务 status 保持 `processing`（不标记为 failed，因为不是处理失败，只是被打断）

**恢复行为**：
1. Processing FGS 重新启动后，从 DB 查询所有 `status=processing` 的条目，按 `createdAt` 升序排列（FIFO）
2. 对每个条目，根据 `processingStage` 执行恢复逻辑
3. 如果某一步骤的中产物（如 ASR 结果）已被 TOS 服务端丢弃（超时等），则标记为 failed

### Processing FGS 队列管理

Processing FGS 从 DB 中查询待处理任务，而非依赖内存队列：

```dart
Future<List<DiaryEntry>> getPendingEntries() {
  // 查询所有 status=processing 的条目，按创建时间升序
  return (select(diaryEntries)
        ..where((t) => t.status.equals('processing'))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .get();
}
```

**优势**：
- 无需在主 isolate 维护内存队列——DB 就是队列
- Processing FGS 崩溃或被杀后重启，队列不丢失
- 新任务入队只需 INSERT 一条 processing 状态的 DB 记录

### 主 isolate 协调职责

主 isolate（RecordingPage）负责：
1. **启动录音前**：检查 RECORD_AUDIO 权限 → `stopService()` → 启动 Recording FGS
2. **录音结束后**：收到 Recording FGS 的完成消息 → 启动 Processing FGS
3. **从列表页返回后**：刷新 Badge 计数（查询 processing + failed 数量）

Processing FGS 的启动/停止完全由主 isolate 控制，Processing FGS 本身只负责处理任务。

## 已确认的设计决策

1. **ASR 失败策略**：ASR 返回 failed 时直接标记整条日记为 failed，不自动重试。用户可通过重试按钮手动恢复。
2. **processingStage 与 status 的关系**：status 只有 processing/completed/failed 三个值，processingStage 是 processing/failed 状态下的细化。录制阶段不创建 DB 条目，因此 processingStage 不需要 'recording' 值，从 'uploading' 开始。
3. **并发处理**：Processing FGS 同一时间只处理一个任务，队列按 FIFO（先进先出）顺序处理。
4. **failed 状态的 processingStage**：标记为 failed 时，processingStage 保持中断时的值（如 'asr'），这样重试时可以直接从该阶段恢复，而不是从头开始。

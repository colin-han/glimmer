# ASR 识别增强 L1：个性化上下文 + 专名热词

> 日期：2026-07-06
> 范围：仅 ASR 阶段识别增强（L1）。LLM 提示词优化、L2/L3 为独立议题，不在本 spec 内。

## 背景与问题

当前三个 ASR 接口（Flash 极速版 / 异步标准版 / 实时流式）的 `request` 仅传 `model_name` + `show_utterances`（实时另传 `enable_itn`/`enable_punc`），**完全未使用火山引擎提供的任何识别增强能力**，导致人名、产品名、项目名等专名频繁识别错误，下游 LLM 的 utterances 整理负担大。

经核实火山引擎官方文档，三个接口均支持通过 `request.corpus.context` 注入：

- **热词直传** `{"hotwords":[{"word":"..."}]}`（Flash/标准版 5000 词，实时流式 100 tokens）
- **对话上下文** `{"context_type":"dialog_ctx","context_data":[{"text":"..."}]}`（800 tokens / 20 轮，可放口音/常驻地/语言/话题等个性化信息）

### 反馈污染回路（核心约束）

若从 ASR 输出自动抽取热词，会把识别错误"固化"为权威词，使错误更稳定。**本 spec 严格遵守**：热词表只接受用户提供的金标准来源（用户显式输入），**永不自动镜像 ASR 输出**。自动抽取（L2）属后续独立议题，必须配合用户在环确认。

## 设计

### 1. 配置（已完成）

两个可选 env 变量，写入 `.env.local`，并在 `.env.local.example` 文档化：

- `ASR_HOTWORDS`：逗号分隔的专名（人名/产品/项目）
- `ASR_CONTEXT_PROMPT`：自然语言一句话个性化上下文

**为可选变量，不纳入 `scripts/build.sh` 的 `REQUIRED_ENV_VARS`**——缺失时 ASR 正常工作、仅无增强。

### 2. 读取与构建（`AsrService`）

- 用 `dotenv.maybeGet(...)` 容错读取，缺失视为未配置。
- 抽公共方法 `String? _buildCorpusContext()`：
  - 同时存在 hotwords 与 prompt → 合并为一个 `context` JSON 字符串：
    ```json
    {"hotwords":[{"word":"glimmer"},{"word":"肖伟红"}],
     "context_type":"dialog_ctx",
     "context_data":[{"text":"<ASR_CONTEXT_PROMPT 全文>"}]}
    ```
  - 仅 hotwords → `{"hotwords":[...]}`
  - 仅 prompt → `{"context_type":"dialog_ctx","context_data":[{"text":"..."}]}`
  - 两者皆无 → 返回 `null`（不注入 `corpus`）
- `context` 值为序列化后的 JSON 字符串（官方要求转义引号），由 `jsonEncode` 生成。

### 3. 注入点

| 接口 | 方法 | 注入 | 说明 |
|---|---|---|---|
| Flash 极速版 | `transcribe` / `transcribeFromUrl` | ✅ | 权威 utterances 来源，最关键 |
| 异步标准版 | `submitAsync` | ✅ | 长录音兜底，submit 时传；`queryAsync` 不传 |
| 实时流式 | `RealtimeAsrService.connect` 配置帧 | ✅ | 保持预览与最终一致；hotwords 限 100 tokens（当前词量充足） |

注入方式：在对应 `request` 对象中，当 `_buildCorpusContext()` 非 null 时加入 `'corpus': {'context': <jsonString>}`。realtime 在配置帧的 `request` 中同样处理。

### 4. 降级与容错

- env 缺失 → 不注入，行为与现状完全一致。
- `corpus.context` 解析/接口报错 → 不影响 ASR 主流程（ASR 调用本身的异常处理已存在）。

## 风险与验证

### 风险：`hotwords` 与 `dialog_ctx` 能否共存于同一 `context`

官方文档将二者列为 `context` 字段的不同能力，但未明确能否合并。**预案**：实现后用一段含「肖伟红」「glimmer」等专名的录音实测；若 API 报错或其中一项被忽略，降级为**仅保留 hotwords**（专名是主要痛点），prompt 上下文暂时舍弃。

### 验证方式

选取一段含已知专名的录音，对比注入前后 ASR 结果（重点看专名识别准确率与 utterances 文本质量）。

## 不在范围内（Out of Scope）

- L2：自动抽取热词候选 + 用户在环确认（独立 spec）
- L3：日记编辑 → 错词/对词 diff 反馈（需先有编辑功能）
- env 的应用内 UI 配置（等 L1 稳定后再做）
- LLM 提示词（title/summary/outline/utterances）优化 —— 本次 brainstorming 的其余目标，后续逐块讨论
- `enable_poi_fc` / `loc_info` / 替换词表 / 托管热词表 等其它增强能力（按需后续扩展）

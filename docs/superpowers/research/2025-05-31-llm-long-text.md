# 语音日记 App 支持数小时级别长录音 -- LLM 处理深度调研报告

---

## 一、问题定义

### 1.1 场景分析

当前语音日记 App 的录音通常为几分钟，ASR 转写后的文本量约数千字，在单次 LLM 调用内即可完成处理。需要扩展到**数小时级别**的录音场景（会议、讲座、旅行记录等），面临的核心挑战是：

**文本量估算：**

| 录音时长 | 正常语速(~200字/分钟) | 较快语速(~260字/分钟) | 对应 Token 数(豆包 1:1) |
|----------|----------------------|----------------------|------------------------|
| 30 分钟 | ~6,000 字 | ~7,800 字 | ~6K-8K |
| 1 小时 | ~12,000 字 | ~15,600 字 | ~12K-16K |
| 2 小时 | ~24,000 字 | ~31,200 字 | ~24K-31K |
| 3 小时 | ~36,000 字 | ~46,800 字 | ~36K-47K |
| 5 小时 | ~60,000 字 | ~78,000 字 | ~60K-78K |

### 1.2 核心约束

1.  **Token 限制**：当前使用的豆包模型（通过火山引擎 Ark 接入），不同版本上下文窗口为 32K~256K
2.  **生成质量**：长文本在单次调用中处理时存在"中间丢失"（Lost in the Middle）问题
3.  **成本**：输入 token 数量线性增长，费用显著增加
4.  **延迟**：长文本生成时间大幅增加，用户体验变差
5.  **四段输出要求**：润色正文/日记体提炼/播报大纲/标题，不同任务对上下文的需求不同

---

## 二、现状分析

### 2.1 主流 LLM Context Window 限制

| 模型 | Context Window | 最大输入 | 最大输出 | Token/汉字比 |
|------|---------------|---------|---------|-------------|
| **豆包 1.8 (Doubao-Seed-2.0)** | 256K | 224K | 128K | ~1:1 |
| **豆包 1.6 (Doubao-Pro)** | 128K-256K | 按区间 | 4K-128K | ~1:1 |
| **GPT-4o** | 128K | 128K | 16K | ~1.5-2:1 |
| **Claude Sonnet 4** | 200K-1M | 200K-1M | ~16K | ~1.5-2:1 |
| **Gemini 2.5 Pro** | 1M-2M | 1M | 64K | ~1.5-2:1 |
| **Gemini 2.5 Flash** | 1M | 1M | 64K | ~1.5-2:1 |
| **DeepSeek V3** | 128K | 128K | ~8K | ~1:1 |

**关键发现**：豆包作为国产模型，中文 Token 效率极高（约 1 Token = 1 汉字），这意味着豆包 256K 上下文可以处理约 **22.4 万汉字**，理论上可覆盖约 **18.7 小时** 的正常语速录音。

### 2.2 长文本生成质量退化问题

研究表明，LLM 在处理长上下文时存在显著的质量退化：

| 问题 | 描述 | 严重程度 |
|------|------|---------|
| **Lost in the Middle** | 位于上下文中部的信息最容易被"遗忘"或忽略 | 高 |
| **推理退化** | 随输入长度增加，推理能力（不仅是信息检索）下降 | 高 |
| **上下文污染** | 无关或重复上下文累积导致输出质量下降 | 中 |
| **关键阈值** | LLM 在特定上下文长度处出现灾难性性能下降 | 高 |

关键论文：
- [Intelligence Degradation in Long-Context LLMs](https://arxiv.org/html/2601.15300v1)（arXiv, 2025）-- 首次系统刻画了 Qwen 系列模型在长上下文中的智能退化现象
- [Context Rot](https://www.trychroma.com/research/context-rot)（Chroma Research）-- 发现当"针-问题"相似度降低时，模型性能随输入长度增长而显著退化
- [Reasoning Degradation with Long Context Windows](https://community.openai.com/t/reasoning-degradation-in-lls-with-long-context-windows-new-benchmarks/906891) -- 证明质量退化不仅影响检索，也影响推理能力

**对日记 App 的启示**：即使是豆包 256K 上下文可以"装下"数小时文本，但直接塞入后生成质量（尤其是润色正文和日记体提炼这两个需要深度理解的任务）会显著下降。

### 2.3 当前 LLM 服务架构

根据代码分析（`lib/services/llm_service.dart`），当前架构为：
- 单次 API 调用，将全部 utterances 序列化为 JSON 发送
- 一个 system prompt 包含四项任务指令
- 期望一次性返回完整的 JSON 结果
- 无分段、无重试、无流式处理

这种架构在文本量小时工作良好，但完全不适用于数万字级别。

---

## 三、方案对比

### 3.1 方案总览

| 方案 | 适用场景 | 优点 | 缺点 | 复杂度 |
|------|---------|------|------|--------|
| **A: 直接使用大窗口** | <2 小时 | 实现简单 | 质量退化、成本高 | 低 |
| **B: Map-Reduce 分段** | 任意长度 | 可扩展、可并行 | 信息丢失、合并质量 | 中 |
| **C: 层级化摘要** | 任意长度 | 质量好、有结构 | 多次调用、成本高 | 中高 |
| **D: 主题分割 + 分别处理** | 多话题录音 | 质量最好 | 分割准确度依赖 | 高 |
| **E: 混合策略（推荐）** | 任意长度 | 兼顾质量和成本 | 实现复杂 | 高 |

### 3.2 方案 A: 直接使用大窗口模型

**思路**：利用豆包 256K 或 Gemini 1M+ 的超大上下文窗口，直接将全部文本一次性送入。

**适用范围**：
- 豆包 256K：约可覆盖 18.7 小时（理论值）
- 考虑 system prompt + 输出预留：实际可用约 200K input，覆盖 ~16.7 小时

**问题**：
- 即使"装得下"，研究表明超过约 50K token 后质量开始退化
- 单次调用延迟可能达到数十秒到分钟级
- 成本较高：200K input token 的单次调用约 0.48 元（豆包 128K-256K 区间价格）

**结论**：适合作为 1-2 小时录音的**快速方案**，但不应作为唯一方案。

### 3.3 方案 B: Map-Reduce 分段处理

**思路**：将长文本按固定 token 数分段（如每段 4K-8K token，带 10-20% 重叠），分别处理后在合并。

参考 [LangChain Map-Reduce 文档](https://python.langchain.ac.cn/docs/how_to/summarize_map_reduce/) 和 [Google Cloud Map-Reduce 摘要](https://cloud.google.com/blog/products/ai-machine-learning/long-document-summarization-with-workflows-and-gemini-models)。

**流程**：

```
原始文本 (60K tokens)
    ↓ 分段 (6 段 × 10K tokens, 20% overlap)
[段1] [段2] [段3] [段4] [段5] [段6]
  ↓     ↓     ↓     ↓     ↓     ↓     ← Map: 并行 LLM 调用
[摘要1][摘要2][摘要3][摘要4][摘要5][摘要6]
    ↓         合并         ← Reduce: 再次 LLM 调用
  [最终摘要/润色]
```

**优点**：
- 可并行处理，显著降低延迟
- 每段文本量小，LLM 处理质量高
- 可扩展到任意长度

**缺点**：
- 分段边界可能切断话题
- 合并阶段可能丢失跨段落的上下文关联
- 多次调用增加总成本

**对四段输出的影响**：
- **润色正文**：分段处理会导致段落间连贯性差，合并后质量下降
- **日记体提炼**：适合 Map-Reduce，因为本质是摘要任务
- **播报大纲**：适合 Map-Reduce，需从各段提取关键主题后合并
- **标题**：适合在最终摘要基础上生成

### 3.4 方案 C: 层级化摘要

**思路**：多阶段递归处理，先分段摘要，再将摘要合并后二次摘要，形成层级结构。

参考 [NexusSum: Hierarchical LLM Agents](https://arxiv.org/html/2505.24575v1) 和 [Context-Aware Hierarchical Merging](https://aclanthology.org/2025.findings-acl.289.pdf)（ACL 2025）。

**流程**：

```
原始文本 (60K tokens)
    ↓ 按时间/话题分段
[段1] [段2] [段3] [段4] [段5] [段6]
  ↓     ↓     ↓     ↓     ↓     ↓     ← 第一轮: 各段生成结构化摘要
[摘要1][摘要2][摘要3][摘要4][摘要5][摘要6]  (含: 段落主题、关键词、精简正文)
    ↓       合并摘要      (~6K tokens)
  [全局摘要 + 跨段落关系]
    ↓                     ← 第二轮: 生成全局输出
[标题 / 全局summary / 全局outline]
```

**与 Map-Reduce 的区别**：
- 第一轮不仅生成摘要，还生成结构化信息（主题、关键词、情感标签）
- 第二轮有更丰富的输入用于生成高质量的全局输出
- 可增加第三轮用于润色正文的段落间衔接

### 3.5 方案 D: 主题分割 + 分别处理

**思路**：先对转写文本进行主题分割，识别话题边界，然后对每个主题段落独立处理。

参考 [Topic Segmentation Using Generative Language Models](https://arxiv.org/html/2601.03276v1)（arXiv, 2025）和 [Unsupervised Topic Segmentation with BERT](https://www.semanticscholar.org/paper/Unsupervised-Topic-Segmentation-of-Meetings-with-Solbiati-Heffernan/c4413021289d22151d0791ef1d371476c6ee51c0)。

**分割算法对比**：

| 算法 | 原理 | 优点 | 缺点 | 适用性 |
|------|------|------|------|--------|
| **TextTiling** | 词频变化检测 | 无需模型、速度快 | 仅依赖词频，准确度有限 | 作为基线 |
| **BERT-based** | 句子嵌入相似度 | 准确度高（误差降低 15.5%） | 需要嵌入模型 | 推荐 |
| **LLM-based** | 让 LLM 直接判断分割点 | 最灵活、理解语义 | 成本高、速度慢 | 高质量场景 |
| **时间戳 + 启发式** | 利用停顿、长间隔分割 | 零成本、利用已有数据 | 不可靠 | 辅助手段 |
| **混合策略** | 时间戳初分 + BERT 精分 | 兼顾效率和准确度 | 实现复杂 | **推荐** |

**混合分割策略（推荐）**：

```
1. 利用 ASR 时间戳进行初分：
   - 检测 > 3 秒的停顿作为候选分割点
   - 检测 > 30 秒的间隔作为强分割点

2. 对初分结果用 BERT/LLM 进行精分：
   - 计算相邻段落的语义相似度
   - 相似度低于阈值处确认分割

3. 合并过短段落（< 500 字），拆分过长段落（> 5000 字）
```

### 3.6 方案 E: 混合策略（推荐方案）

**核心思路**：根据文本长度动态选择策略，短文本直接处理，中等文本层级化，长文本主题分割 + 层级化。

```
文本长度判断
    │
    ├─ < 8K tokens (< 40 分钟录音)
    │   └─ 方案 A: 直接单次调用（当前方案，无需修改）
    │
    ├─ 8K-50K tokens (40 分钟 ~ 4 小时)
    │   └─ 方案 C: 层级化摘要
    │       ├─ 第一轮: 按时间分段(~4K/段), 各段生成结构化摘要
    │       ├─ 第二轮: 合并摘要, 生成全局 summary + title + outline
    │       └─ 第一轮各段: 生成润色正文(保留时间戳)
    │
    └─ > 50K tokens (> 4 小时)
        └─ 方案 D+C: 主题分割 + 层级化
            ├─ 步骤 1: 时间戳初分 + 语义精分
            ├─ 步骤 2: 各主题段落并行处理(润色+摘要)
            ├─ 步骤 3: 合并各主题输出, 生成全局 summary/outline/title
            └─ 步骤 4: 生成章节速览(主题列表+关键词)
```

---

## 四、成本分析

### 4.1 豆包 API 价格参考

| 模型 | 输入价格 (元/百万 Token) | 输出价格 (元/百万 Token) | 备注 |
|------|-------------------------|-------------------------|------|
| **Doubao-1.6 (0-32K 区间)** | ~0.8 | ~3.2 | 性价比最高 |
| **Doubao-1.6 (32K-128K 区间)** | ~1.2 | ~8.0 | 长文本区间 |
| **Doubao-1.6 (128K-256K 区间)** | ~2.4 | ~24.0 | 最长区间 |
| **Doubao-V4-Flash** | ~1.0 | - | 缓存命中 0.2 |
| **Doubao-Seed-2.0** | 按区间递增 | 按区间递增 | 最新版 |

注意：火山引擎每天提供 50 万 tokens 免费额度，可用于抵扣部分成本。

### 4.2 不同方案的成本估算

以 **3 小时录音**（约 36,000 字 ≈ 36K tokens）为例：

| 方案 | 输入 Token 总计 | 输出 Token 总计 | 估算成本 | 调用次数 |
|------|----------------|----------------|---------|---------|
| **A: 直接调用** | ~36K + 1K(prompt) = 37K | ~8K | **~0.07 元** | 1 |
| **B: Map-Reduce** | 6×10K + 10K(合并) = 70K | 6×2K + 4K = 16K | **~0.15 元** | 7 |
| **C: 层级化** | 6×10K + 10K = 70K | 6×3K + 6K = 24K | **~0.20 元** | 7-9 |
| **D: 主题分割+C** | 1K(分割) + 5×8K + 15K = 56K | 0.5K + 5×3K + 6K = 21.5K | **~0.18 元** | 6-8 |

以 **5 小时录音**（约 60,000 字 ≈ 60K tokens）为例：

| 方案 | 估算成本 | 调用次数 | 延迟 |
|------|---------|---------|------|
| **A: 直接调用** | ~0.15 元 | 1 | ~60-120s |
| **B: Map-Reduce** | ~0.30 元 | 10 | ~30-60s(并行) |
| **C: 层级化** | ~0.40 元 | 12-15 | ~40-80s(并行) |
| **D: 主题分割+C** | ~0.35 元 | 10-12 | ~35-70s(并行) |

**成本结论**：
- 即使是最复杂的方案，5 小时录音的 LLM 处理成本也不超过 0.5 元
- 豆包的中文 Token 效率和极低价格使得成本不是主要约束
- **主要约束是质量和延迟，而非成本**

### 4.3 与其他模型成本对比

以 3 小时录音（36K tokens）单次直接处理为例：

| 模型 | 输入成本 | 输出成本 | 总成本 |
|------|---------|---------|--------|
| **豆包 1.6** | ~0.04 元 | ~0.03 元 | **~0.07 元** |
| **GPT-4o** | ~$0.09 (0.65 元) | ~$0.12 (0.87 元) | **~1.52 元** |
| **Claude Sonnet** | ~$0.11 (0.80 元) | ~$0.12 (0.87 元) | **~1.67 元** |
| **Gemini 2.5 Flash** | ~$0.005 (0.04 元) | ~$0.005 (0.04 元) | **~0.08 元** |
| **DeepSeek V3** | ~$0.01 (0.07 元) | ~$0.003 (0.02 元) | **~0.09 元** |

**结论**：豆包和 Gemini Flash 在中文长文本处理上最具性价比。Gemini 2.5 Flash 拥有 1M 上下文窗口 + 极低价格，可作为备选模型。

---

## 五、竞品分析

### 5.1 主要竞品对比

| 产品 | 最大录音时长 | AI 摘要功能 | 技术推测 |
|------|------------|-----------|---------|
| **Otter.ai** | 30 分钟(免费) / 90 分钟(Pro) / 无限(Business) | 实时转录 + AI 摘要 | 分段转录 + LLM 摘要 |
| **通义听悟** | **最长 6 小时** / 6GB | 全文摘要、章节速览、发言总结、问答回顾、关键词提取 | 大模型驱动，可能采用分段+层级化 |
| **Notion AI** | 无明确限制 | 会议摘要、行动项提取 | 依赖 Claude/GPT，大窗口或分段 |
| **飞书妙记** | 支持长音频 | 章节速览、智能摘要、待办提取 | 字节自研模型，可能类似豆包方案 |
| **Plaud/SENSE** | 数小时级别 | AI 摘要、章节分析 | 分段处理 + LLM |

### 5.2 通义听悟的参考价值

通义听悟是**最直接的竞品参考**，其功能设计高度相关：

- **章节速览**：将长音频按话题自动分章节，每章生成标题和摘要 -- 对应"主题分割"方案
- **全文摘要**：跨章节的全局摘要 -- 对应"层级化摘要的 Reduce 步骤"
- **发言总结**：按发言人维度汇总 -- 语音日记场景中不适用（单人录音）
- **最长 6 小时支持**：说明其技术方案可处理约 72K-100K tokens 的输入

**推测其技术方案**：
1.  ASR 转写后先进行主题分割
2.  各主题段落独立生成摘要和关键词
3.  合并生成全局摘要
4.  章节标题从各主题段落中提取

这与本报告推荐的"方案 E: 混合策略"高度一致。

---

## 六、推荐策略

### 6.1 分阶段实施建议

#### 第一阶段：支持 30 分钟 - 2 小时录音（快速实现）

**策略**：直接使用大窗口，优化 Prompt

-  当前豆包 256K 上下文完全可容纳 2 小时内的文本（~24K tokens）
-  优化 system prompt，将四段任务拆分为多次调用以避免输出过长
-  增加流式输出支持，改善用户体验
-  预计工作量：2-3 天

**关键改动**：
```
调用 1: 输入全部文本 → 输出 title + outline (快速响应)
调用 2: 输入全部文本 → 输出 content (润色正文，保留时间戳)
调用 3: 输入全部文本 → 输出 summary (日记体提炼)
```

#### 第二阶段：支持 2-4 小时录音（中等改造）

**策略**：层级化摘要（方案 C）

-  按时间分段（每段约 4K tokens），并行处理
-  第一轮：各段生成段落摘要 + 润色正文 + 关键词
-  第二轮：合并生成全局 summary + title + outline
-  预计工作量：5-7 天

#### 第三阶段：支持 4+ 小时录音（完整方案）

**策略**：主题分割 + 层级化（方案 D+C）

-  实现基于时间戳 + 语义的混合分割
-  分割后按主题段落处理
-  生成章节速览作为额外输出
-  预计工作量：7-10 天

### 6.2 具体技术建议

1.  **分段策略**：
    -   段大小：4K-8K tokens（约 2000-4000 字）
    -   重叠度：15-20%（~500-800 字）
    -   分段边界优先选择 ASR 时间戳中的长停顿（> 2 秒）

2.  **Prompt 设计**：
    -   各段处理的 system prompt 应包含"这是完整录音的第 X/Y 段"的上下文
    -   段落摘要应包含：主题、关键词、情感基调、关键事件
    -   合并阶段的 prompt 应包含"以下是录音各段的摘要"的结构化输入

3.  **并行处理**：
    -   使用 Dart 的 `Future.wait()` 并行处理各段
    -   各段处理独立，失败可单独重试
    -   第一轮全部完成后才进行第二轮合并

4.  **进度反馈**：
    -   向用户展示处理进度（"正在分析第 3/8 段..."）
    -   优先完成 outline 和 title（快速响应），content 和 summary 可后台继续

5.  **缓存策略**：
    -   各段处理结果独立缓存，用户重试时只需重处理失败段
    -   利用豆包的缓存命中机制（0.2 元/百万 Token）降低重试成本

6.  **降级方案**：
    -   如果 LLM 调用失败，保留各段独立结果，允许用户查看分段摘要
    -   提供手动合并功能

### 6.3 输出格式扩展

当前输出：`{title, content, summary, outline, utterances[]}`

建议扩展为：

```json
{
  "title": "全局标题",
  "content": "完整润色正文(保留时间戳)",
  "summary": "全局日记体提炼",
  "outline": "全局播报大纲",
  "chapters": [
    {
      "title": "章节标题",
      "startTime": 0,
      "endTime": 1800000,
      "summary": "章节摘要",
      "keywords": ["关键词1", "关键词2"]
    }
  ],
  "utterances": [...]
}
```

---

## 七、风险与注意事项

1.  **LLM 输出稳定性**：分段处理后各段输出格式可能不一致，需要健壮的 JSON 解析和 fallback 逻辑
2.  **时间戳精度**：分段处理时 utterances 的时间戳可能需要跨段调整
3.  **豆包价格变动**：火山引擎价格策略调整频繁，需关注最新定价
4.  **网络超时**：长时间录音的处理可能需要 1-3 分钟，需要合理设置 HTTP 超时并给用户进度反馈
5.  **存储空间**：数小时录音的 WAV 文件可能达到数百 MB，需考虑存储策略

---

## 八、参考资料

### 学术论文
- [Intelligence Degradation in Long-Context LLMs](https://arxiv.org/html/2601.15300v1)
- [Topic Segmentation Using Generative Language Models](https://arxiv.org/html/2601.03276v1)
- [NexusSum: Hierarchical LLM Agents for Long-Form Narrative Summarization](https://arxiv.org/html/2505.24575v1)
- [Context-Aware Hierarchical Merging for Long Document Summarization](https://aclanthology.org/2025.findings-acl.289.pdf)
- [Unsupervised Topic Segmentation of Meetings with BERT](https://www.semanticscholar.org/paper/Unsupervised-Topic-Segmentation-of-Meetings-with-Solbiati-Heffernan/c4413021289d22151d0791ef1d371476c6ee51c0)
- [A Systematic Review of Long Document Summarization Methods](https://www.sciencedirect.com/science/article/pii/S0925231225019599)

### 技术博客/文档
- [Galileo AI - Master LLM Summarization Strategies](https://galileo.ai/blog/llm-summarization-strategies)
- [LangChain - Map-Reduce Summarization](https://python.langchain.ac.cn/docs/how_to/summarize_map_reduce/)
- [Google Cloud - Long Document Summarization](https://cloud.google.com/blog/products/ai-machine-learning/long-document-summarization-with-workflows-and-gemini-models)
- [AssemblyAI - Text Segmentation Approaches](https://www.assemblyai.com/blog/text-segmentation-approaches-datasets-and-evaluation-metrics)
- [Chroma Research - Context Rot](https://www.trychroma.com/research/context-rot)
- [Pinecone - Chunking Strategies](https://www.pinecone.io/learn/chunking-strategies/)

### 官方文档
- [火山方舟 - 模型价格](https://www.volcengine.com/docs/82379/1544106)
- [火山方舟 - 模型列表](https://www.volcengine.com/docs/82379/1330310)
- [通义听悟 - 产品功能](https://help.aliyun.com/zh/tingwu/features)
- [腾讯云 - 主流大模型 Token 计算方式全解析](https://cloud.tencent.com/developer/article/2550219)

### 价格参考
- [PE Collective - LLM API Pricing 2026](https://pecollective.com/blog/llm-api-pricing-comparison/)
- [TLDL - LLM API Pricing 2026](https://www.tldl.io/resources/llm-api-pricing-2026)
- [LLM Pricing Calculator](https://llmpricingcalculator.com/)
- [Redis - LLM Context Windows](https://redis.io/blog/llm-context-windows/)

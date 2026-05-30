# 网络失败重试设计

## 背景

录音结束后 ASR/LLM 网络请求可能失败（锁屏、网络中断等），当前行为是显示错误、丢失所有数据。需要保留已有数据，允许用户重试。

## 状态判断

通过文件存在性推断处理阶段，无需改数据库 schema：

- 无 `transcript.json` → ASR 失败，需重试 ASR
- 有 `transcript.json` 无 `llm_result.json`（及旧格式 `summary.md`）→ LLM 失败，需重试 LLM
- 两者都有 → 处理完成

## RecordingPage 改动

`_stopAndProcess` 中的 try-catch 拆分为两段：

1. **stopRecording 成功后**：音频文件已保存到磁盘
2. **ASR 失败**：存入数据库（title="未命名日记"，duration 已知），跳转详情页
3. **LLM 失败**：transcript.json 已保存，存入数据库（title="未命名日记"），跳转详情页
4. **stopRecording 本身失败**：仍显示错误（无法保留数据）

## DiaryDetailPage 改动

加载时检测文件状态。检测到未完成时：
- 显示重试按钮（代替或补充现有内容区域）
- 重试 ASR：读取 `audio.wav` 路径，调用 `_asrService.transcribe`
- 重试 LLM：读取 `transcript.json`，调用 `_llmService.summarize`
- 重试成功后保存结果文件，更新数据库 title，刷新页面

## DiaryListPage

未完成的日记正常显示在列表中（title 为"未命名日记"），无特殊标记。

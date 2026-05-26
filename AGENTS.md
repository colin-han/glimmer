# AGENTS.md

## 项目

语音日记 — 自用 Android App。录音 → ASR → LLM 润色 → 存储 → TTS 朗读。Sideload APK，不上架 Play Store。

## 语言规范

- 文档全部使用中文
- 代码中的注释使用中文
- 代码标识符（类名、变量名、函数名、文件名等）使用英文
- commit message 使用中文

## 技术栈

- **Flutter**（Dart 3.x，stable channel）→ `flutter build apk --release`
- **本地存储**：`drift`（SQLite）用于元数据和索引；日记正文存为 Markdown/纯文本文件；音频文件存为 `.m4a`
- **AI 能力栈（字节火山引擎）**：单账号、单 API Key
  - ASR：豆包录音文件识别（异步，5 分钟长录音）
  - LLM：Doubao-1.5-pro / 1.6-pro（反思式追问对话、文本润色）；轻量任务用 `doubao-lite`（打标签、生成标题）
  - TTS：豆包语音合成 2.0（WebSocket 流式）
- **备份基础设施（阿里云）**：OSS 归档存储，通过 `workmanager` 插件调用 Android WorkManager 每周自动上传；SSE-OSS 加密
- **关键依赖**：`dio`（HTTP）、`web_socket_channel`（WebSocket）、`record` 或 `flutter_sound`（录音）、`path_provider`（文件路径）
- **OSS 上传**：阿里云 OSS REST API + `dio` 自封装（无官方 Dart SDK）

## 核心约束

- 仅 Android；通过 Flutter 保留未来多端可能性，但当前不要为此设计
- 日记正文存为 Markdown/文本文件，SQLite 仅作索引和元数据，永远不存正文内容
- 无服务端；所有云端调用直接从设备发起至火山引擎和阿里云 API
- 不做客户端加密；备份静落盘加密由 OSS SSE-OSS 承担
- 不上架 Play Store；通过 ADB 安装

## 主流程

录音 (m4a) → 豆包 ASR（异步）→ Doubao LLM（润色 + 反思式追问）→ Markdown 文本 + SQLite 元数据 → 豆包 TTS 2.0（WebSocket 流式）→ 朗读

## 构建与运行

Flutter 项目初始化后补充。预期：`flutter build apk --release` → ADB sideload。

## API Key 管理

火山引擎 API Key 严禁提交到仓库。使用 `.env` 或 `--dart-define` 在构建时注入。`*.env` 必须加入 `.gitignore`。

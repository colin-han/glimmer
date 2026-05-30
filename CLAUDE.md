# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

语音日记 Android App。录音 → ASR 语音识别 → LLM 润色 → 存储。仅 Android，sideload APK，不上架 Play Store。

## 语言规范

- 文档和注释使用中文
- 代码标识符（类名、变量名、函数名、文件名）使用英文
- commit message 使用中文

## 构建与开发命令

```bash
flutter run                                    # 运行应用
flutter build apk --release                    # 构建 release APK
flutter test                                   # 运行测试
flutter analyze                                # 代码分析/lint
dart run build_runner build                    # 重新生成 drift 数据库代码（修改 tables.dart 后必须执行）
dart run build_runner build --delete-conflicting-outputs  # 同上，强制覆盖冲突文件
```

## 环境变量

`.env.local` 存放 API 密钥，模板见 `.env.local.example`。已加入 `.gitignore`，严禁提交。

关键变量：
- `VOLCENGINE_SPEECH_TOKEN` / `VOLCENGINE_SPEECH_APPID` — ASR 服务
- `VOLCENGINE_ARK_API_KEY` / `VOLCENGINE_ARK_ENDPOINT_ID` — LLM (Doubao)

## 架构

分层架构，无复杂状态管理库，直接使用 StatefulWidget。

```
lib/
  main.dart                  # 入口，加载 .env.local，MaterialApp
  models/
    diary_entry.dart         # 日记元数据模型
    utterance.dart           # 带时间戳的语音片段 + TranscriptData + LlmResultData
  pages/                     # 页面（直接导航，无路由表）
    recording_page.dart      # 主页：录音 → ASR → LLM → 保存
    diary_list_page.dart
    diary_detail_page.dart
  services/
    asr_service.dart         # 火山引擎 ASR（带时间戳识别）
    realtime_asr_service.dart # 实时 ASR（WebSocket）
    llm_service.dart         # 火山引擎 Doubao（四段输出：润色/提炼/播报/标题）
    tts_service.dart         # TTS 播报
    audio_recorder_service.dart   # record 插件封装
    audio_player_service.dart     # just_audio 封装
    diary_storage_service.dart    # 文件 I/O + drift 数据库
    database/
      tables.dart            # drift 表定义（修改后需 build_runner）
      app_database.dart      # drift 数据库类
      app_database.g.dart    # 生成代码，勿手动编辑
  widgets/                   # 可复用 UI 组件
```

### 数据存储策略

- **SQLite (drift)**：仅存元数据（id, title, folderPath, duration, createdAt）
- **文件系统**：每个日记一个 UUID 文件夹，内含 `audio.wav`、`transcript.json`、`llm_result.json`
- 正文永远不进 SQLite，确保数据可迁移

### 主流程 (RecordingPage)

录音 (wav) → 实时 ASR（WebSocket）→ Flash ASR 兜底识别（带时间戳）→ LLM 四段输出（润色正文/日记体提炼/播报大纲/标题）→ 写入 llm_result.json + SQLite 元数据 → TTS 播报大纲 → 跳转详情页

## 数据兼容性要求

**自 v1.0.0 起，所有修改必须向后兼容，严禁丢失用户数据。**

- 用户已保存的日记数据不可因任何代码变更而丢失或损坏
- SQLite schema 变更必须通过 drift migration 处理，新字段必须有默认值
- 文件格式变更时，读取逻辑必须兼容旧格式
- 不允许删除或重命名用户数据文件（audio.wav, transcript.json, llm_result.json）
- 不允许执行破坏性数据库操作（DROP TABLE、DELETE 无 WHERE 等）

## 数据格式迁移规则

- 文件系统中的数据格式变更时，必须保持**向后兼容**：读取时优先检测新格式文件，新格式不存在则回退读旧格式
- 每个数据文件都带 `version` 字段（整数），用于未来格式升级时判断版本
- 废弃的写入方法保留在代码中（不删除），仅标记为废弃，确保旧数据仍可读取
- SQLite schema 变更需通过 drift migration 处理

### 当前文件格式

每个日记 UUID 文件夹内：
- `audio.wav` — 录音文件
- `transcript.json` — ASR 原始识别结果（含时间戳）
- `llm_result.json` — LLM 处理结果（title/content/summary/outline + 时间戳 utterances）
- 旧格式 `summary.md` 和 `summary_utterances.json` 仍需兼容读取

## 关键依赖

- `drift` + `build_runner` + `drift_dev` — SQLite ORM + 代码生成
- `record` — 录音
- `just_audio` — 播放
- `dio` — HTTP（ASR/LLM API）
- `flutter_dotenv` — 环境变量
- `flutter_markdown` — Markdown 渲染

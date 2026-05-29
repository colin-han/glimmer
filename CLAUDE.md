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
  models/diary_entry.dart    # 数据模型
  pages/                     # 页面（直接导航，无路由表）
    recording_page.dart      # 主页：录音 → ASR → LLM → 保存
    diary_list_page.dart
    diary_detail_page.dart
  services/
    asr_service.dart         # 火山引擎 ASR（异步长录音识别）
    llm_service.dart         # 火山引擎 Doubao（文本润色 + 标题生成）
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
- **文件系统**：每个日记一个 UUID 文件夹，内含 `audio.m4a`、`transcript.txt`、`summary.md`
- 正文永远不进 SQLite，确保数据可迁移

### 主流程 (RecordingPage)

录音 (m4a) → 提交 ASR 异步任务 → 轮询结果 → LLM 润色生成 Markdown → 写入文件 + SQLite 元数据 → 跳转详情页

## 关键依赖

- `drift` + `build_runner` + `drift_dev` — SQLite ORM + 代码生成
- `record` — 录音
- `just_audio` — 播放
- `dio` — HTTP（ASR/LLM API）
- `flutter_dotenv` — 环境变量
- `flutter_markdown` — Markdown 渲染

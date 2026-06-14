# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

语音日记 Android App。录音 → ASR 语音识别 → LLM 润色 → 存储。仅 Android，sideload APK，不上架 Play Store。

## 语言规范

- 文档和注释使用中文
- 代码标识符（类名、变量名、函数名、文件名）使用英文
- commit message 使用中文

## 异常处理规范

- **禁止直接 `throw Exception('...')`**：需要抛出异常时，必须根据异常的**用途**实现对应的派生类（统一定义在 `lib/exceptions.dart`，基类 `AppException`）
- **禁止基于异常字符串内容判断**：捕获方不得用 `e.toString().contains(...)` 区分异常类型，必须用 `on XxxException` 按类型捕获
- 异常是"无语音内容"等正常业务结果时，应通过返回值（如空列表、`null`）表达，而非抛异常
- 真正的错误（接口失败、超时、前置条件缺失）才抛异常，并使用对应的异常类（`AsrException`/`TtsException`/`RecordingException`/`ProcessingException` 等）

## 构建与开发命令

项目配置了 **dev / prod** 两个 flavor，直接 `flutter run` / `flutter build apk` 会因缺少 `--flavor` 失败。开发与发布请使用 `scripts/` 下的封装脚本（已处理 flavor）。

### 通用命令

```bash
flutter analyze                                # 代码分析/lint
flutter test                                   # 运行测试
dart run build_runner build                    # 重新生成 drift 数据库代码（修改 tables.dart 后必须执行）
dart run build_runner build --delete-conflicting-outputs  # 同上，强制覆盖冲突文件
```

### 开发与发布脚本（scripts/）

| 脚本 | 作用 |
|---|---|
| `./scripts/run_dev.sh` | 运行 **dev** flavor（`--flavor dev --dart-define=dev=true`）；从 `.env.local` 读取 `WORKTREE` 注入为 `--dart-define=worktree`，使不同 worktree 生成独立包名（如 `dev.w1` / `dev.w2`）可共存安装。**日常开发用此脚本** |
| `./scripts/run_prod.sh` | 运行 **prod** flavor（`--flavor prod`） |
| `./scripts/build.sh` | `flutter clean` 后构建 **prod release** APK，输出到 `build/app/outputs/flutter-apk/app-prod-release.apk` |
| `./scripts/install.sh` | 将 prod release APK 安装到已连接设备（`adb install -r` 保留数据），需先执行 `build.sh` |
| `./scripts/update_version.sh` | 更新版本号：bump 版本 → 改 `pubspec.yaml` → git 提交 → 打 tag → **push 到 origin**。用法 `[major\|minor\|patch\|<#.#.#>]`，默认 patch；仅限 main 分支且工作区干净；`--skip-version` 跳过版本号只打 tag |
| `./scripts/release.sh` | 完整发布流程：`update_version` → `build` → `install`。用法同 update_version |

> ⚠️ `update_version.sh` / `release.sh` 会**自动 `git push`**（提交 + tag 到 origin），属于发布动作，非日常提交。日常代码提交仍按下方「提交规范」手动 commit。

## 提交规范

- **每次提交代码前必须对改动文件运行 `dart format`**（`dart format lib/` 格式化全部，或 `dart format <具体文件>` 仅格式化本次改动），保持代码风格统一
- **每次提交代码前必须运行 `flutter analyze`**，并解决全部问题（info / warning / error 一律清零），目标是输出 `No issues found!` 方可提交
- 极少数情况下，若某问题修复价值极小或属分析器误报，可用 `// ignore: 规则名` 抑制，并在注释中简要说明原因
- ⚠️ `// ignore:` 规则名后必须紧跟空格或行尾，切勿紧跟中文等非 ASCII 字符（如全角括号 `（`），否则规则名解析失败、忽略会**静默失效**

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
    llm_service.dart         # 火山引擎 Doubao（三段输出：提炼/播报/标题）
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

录音 (wav) → 实时 ASR（WebSocket）→ Flash ASR 兜底识别（带时间戳）→ LLM 三段输出（日记体提炼/播报大纲/标题）→ 写入 llm_result.json + SQLite 元数据 → TTS 播报大纲 → 跳转详情页

## 数据兼容性要求

**兼容性基线为 v1.0.0：自 v1.0.0 起所有修改必须向后兼容，严禁丢失用户数据。v1.0.0 之前版本（基于 summary.md + summary_utterances.json 的旧格式）不再支持，无需兼容读取。**

- 用户已保存的日记数据不可因任何代码变更而丢失或损坏
- SQLite schema 变更必须通过 drift migration 处理，新字段必须有默认值
- 文件格式变更时，读取逻辑必须兼容旧格式
- 不允许删除或重命名用户数据文件（audio.wav, transcript.json, llm_result.json）
- 不允许执行破坏性数据库操作（DROP TABLE、DELETE 无 WHERE 等）

## 数据格式迁移规则

- 文件系统中的数据格式变更时，必须保持**向后兼容**：读取时优先检测新格式文件，新格式不存在则回退读旧格式
- 每个数据文件都带 `version` 字段（整数），用于未来格式升级时判断版本
- 废弃的写入方法保留在代码中（不删除），仅标记为废弃；v1.0.0 之前的旧格式（summary.md / summary_utterances.json）不再保证可读取
- SQLite schema 变更需通过 drift migration 处理

### 当前文件格式

每个日记 UUID 文件夹内：
- `audio.wav` — 录音文件
- `transcript.json` — ASR 原始识别结果（含时间戳）
- `llm_result.json` — LLM 处理结果（title/summary/outline + 时间戳 utterances）
- 旧格式 `summary.md` 和 `summary_utterances.json`（v1.0.0 之前）**不再支持读取**；readLlmResult 不回退读旧格式是有意设计，非缺陷

## 关键依赖

- `drift` + `build_runner` + `drift_dev` — SQLite ORM + 代码生成
- `record` — 录音
- `just_audio` — 播放
- `dio` — HTTP（ASR/LLM API）
- `flutter_dotenv` — 环境变量
- `flutter_markdown` — Markdown 渲染

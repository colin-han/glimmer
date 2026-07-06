# ASR 识别增强 L1 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ASR_HOTWORDS` / `ASR_CONTEXT_PROMPT` 两个可选 env 注入火山引擎 ASR 的 `request.corpus.context`，提升专名与个性化识别准确率。

**Architecture:** 抽出一个**纯函数** `buildAsrCorpusContext(...)` 负责把"逗号分隔热词 + 上下文一句话"序列化成 `corpus.context` 的 JSON 字符串（可独立单测）；`AsrService` 的三个识别方法（`transcribe` / `transcribeFromUrl` / `submitAsync`）与 `RealtimeAsrService` 的配置帧各自读取 env 并调用该纯函数，按需注入。env 缺失则不注入，行为与现状一致。

**Tech Stack:** Dart / Flutter，`dio ^5.7.0`，`flutter_dotenv ^5.2.1`（`dotenv.maybeGet`），`flutter_test` + `mocktail`。

## Global Constraints

- **反馈污染红线**：热词来源仅为用户提供的 env（金标准）。本计划**不做任何从 ASR 输出自动抽取热词**的逻辑。代码注释须写明此约束。
- **env 可选**：`ASR_HOTWORDS` / `ASR_CONTEXT_PROMPT` 缺失或为空时不得注入 `corpus`，ASR 行为完全不变；**不纳入** `scripts/build.sh` 的 `REQUIRED_ENV_VARS`（已确认）。
- **语言规范**：注释/文档中文，标识符英文。
- **提交规范**：每次提交前对改动文件运行 `dart format`，并运行 `flutter analyze` 至 `No issues found!`。`// ignore: 规则名` 后必须紧跟空格或行尾。
- **数据兼容**：本改动仅影响 ASR 请求体，不触碰 SQLite schema、不改动任何文件格式（`audio.wav` / `transcript.json` / `llm_result.json`），无迁移。

---

## 文件结构

- **Create** `lib/services/asr_context_builder.dart` — 纯函数 `buildAsrCorpusContext`，负责 `corpus.context` JSON 的构建（无 dotenv、无 Dio，纯可测）。
- **Create** `test/asr_context_builder_test.dart` — 上述纯函数的单测。
- **Modify** `lib/services/asr_service.dart` — 新增 `_buildRequest()`，三个识别方法复用，按需注入 `corpus`。
- **Modify** `lib/services/realtime_asr_service.dart` — 配置帧 `request` 按需注入 `corpus`。

---

### Task 1: 纯函数 `buildAsrCorpusContext` 及单测（TDD）

**Files:**
- Create: `lib/services/asr_context_builder.dart`
- Test: `test/asr_context_builder_test.dart`

**Interfaces:**
- Produces: `String? buildAsrCorpusContext({String? hotwords, String? prompt})` —— 后续任务的核心依赖。返回值：序列化后的 `corpus.context` JSON 字符串；当 `hotwords` 与 `prompt` 均无有效内容时返回 `null`（调用方据此跳过注入）。

**JSON 契约（实现须严格匹配）：**
- 仅 hotwords：`{"hotwords":[{"word":"a"},{"word":"b"}]}`
- 仅 prompt：`{"context_type":"dialog_ctx","context_data":[{"text":"..."}]}`
- 两者皆有：合并为 `{"hotwords":[...],"context_type":"dialog_ctx","context_data":[{"text":"..."}]}`
- 皆无：`null`

- [ ] **Step 1: 写失败测试**

创建 `test/asr_context_builder_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/asr_context_builder.dart';

void main() {
  group('buildAsrCorpusContext', () {
    test('hotwords + prompt 合并：同时包含 hotwords 与 dialog_ctx', () {
      final result = buildAsrCorpusContext(
        hotwords: 'glimmer,肖伟红',
        prompt: '我使用标准普通话。',
      );
      expect(result, isNotNull);
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'glimmer'},
        {'word': '肖伟红'},
      ]);
      expect(map['context_type'], 'dialog_ctx');
      expect(map['context_data'], [
        {'text': '我使用标准普通话。'},
      ]);
    });

    test('仅 hotwords：不含 context_type / context_data', () {
      final result = buildAsrCorpusContext(hotwords: 'glimmer,ears');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'glimmer'},
        {'word': 'ears'},
      ]);
      expect(map.containsKey('context_type'), isFalse);
      expect(map.containsKey('context_data'), isFalse);
    });

    test('仅 prompt：不含 hotwords', () {
      final result = buildAsrCorpusContext(prompt: '我常驻西安市。');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map.containsKey('hotwords'), isFalse);
      expect(map['context_type'], 'dialog_ctx');
      expect(map['context_data'], [
        {'text': '我常驻西安市。'},
      ]);
    });

    test('两者皆空：返回 null（不注入 corpus）', () {
      expect(buildAsrCorpusContext(), isNull);
      expect(buildAsrCorpusContext(hotwords: '', prompt: ''), isNull);
      expect(buildAsrCorpusContext(hotwords: '   ', prompt: '  '), isNull);
    });

    test('hotwords 去空白、去空项、trim', () {
      final result = buildAsrCorpusContext(hotwords: ' a , b , , c ');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'a'},
        {'word': 'b'},
        {'word': 'c'},
      ]);
    });

    test('prompt 仅空白时按"无 prompt"处理，但仍可只注入 hotwords', () {
      final result = buildAsrCorpusContext(hotwords: 'glimmer', prompt: '   ');
      final map = jsonDecode(result!) as Map<String, dynamic>;
      expect(map['hotwords'], [
        {'word': 'glimmer'},
      ]);
      expect(map.containsKey('context_type'), isFalse);
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/asr_context_builder_test.dart`
Expected: FAIL —— 编译错误 `name 'buildAsrCorpusContext' is not defined`（文件尚未创建）。

- [ ] **Step 3: 实现纯函数**

创建 `lib/services/asr_context_builder.dart`：

```dart
import 'dart:convert';

/// 构建 ASR `request.corpus.context` 的 JSON 字符串。
///
/// [hotwords] 为逗号分隔的专名（人名/产品/项目）；[prompt] 为个性化上下文一句话
/// （口音/常驻地/语言/话题）。两者皆无有效内容时返回 `null`，调用方据此不注入 `corpus`。
///
/// 红线：热词来源必须为用户提供的金标准。**严禁**从 ASR 输出自动抽取热词回填，
/// 否则会把识别错误固化为权威词（反馈污染）。自动抽取需配合用户在环确认，属后续议题。
String? buildAsrCorpusContext({String? hotwords, String? prompt}) {
  final words = (hotwords ?? '')
      .split(',')
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();
  final promptText = prompt?.trim();
  final hasPrompt = promptText != null && promptText.isNotEmpty;

  if (words.isEmpty && !hasPrompt) return null;

  final map = <String, dynamic>{};
  if (words.isNotEmpty) {
    map['hotwords'] = words.map((w) => {'word': w}).toList();
  }
  if (hasPrompt) {
    map['context_type'] = 'dialog_ctx';
    map['context_data'] = [
      {'text': promptText},
    ];
  }
  return jsonEncode(map);
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/asr_context_builder_test.dart`
Expected: PASS（全部用例通过）。

- [ ] **Step 5: 格式化 + 分析**

Run:
```bash
dart format lib/services/asr_context_builder.dart test/asr_context_builder_test.dart
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/asr_context_builder.dart test/asr_context_builder_test.dart
git commit -m "feat(asr): 新增 corpus.context 构建纯函数及单测"
```

---

### Task 2: `AsrService` 三个识别方法注入 `corpus`

**Files:**
- Modify: `lib/services/asr_service.dart`

**Interfaces:**
- Consumes: `String? buildAsrCorpusContext({String? hotwords, String? prompt})`（Task 1 产出）。
- Produces: `transcribe` / `transcribeFromUrl` / `submitAsync` 的请求体在配置了 env 时带 `corpus.context`。`queryAsync` 不变（查询接口不传 corpus）。

**说明：** 注入逻辑涉及 dotenv + Dio，属集成层，无现成 Dio mock 基础设施；核心 JSON 构建已由 Task 1 的纯函数全覆盖。本任务以 `flutter analyze` + 代码审查为质量门，端到端验证在 Task 4。

- [ ] **Step 1: 新增 import**

在 `lib/services/asr_service.dart` 顶部 import 区（`import '../models/utterance.dart';` 之后）新增：

```dart
import 'asr_context_builder.dart';
```

- [ ] **Step 2: 新增 `_buildRequest()` 方法**

在 `AsrService` 类内（`final Dio _dio = Dio();` 之后、`transcribe` 之前）新增：

```dart
  /// 构建 ASR 请求的 `request` 字段，按需注入个性化 `corpus.context`。
  /// env 未配置时返回的 request 不含 corpus，行为与现状一致。
  Map<String, dynamic> _buildRequest() {
    final request = <String, dynamic>{
      'model_name': 'bigmodel',
      'show_utterances': true,
    };
    final corpusContext = buildAsrCorpusContext(
      hotwords: dotenv.maybeGet('ASR_HOTWORDS'),
      prompt: dotenv.maybeGet('ASR_CONTEXT_PROMPT'),
    );
    if (corpusContext != null) {
      request['corpus'] = {'context': corpusContext};
    }
    return request;
  }
```

- [ ] **Step 3: `transcribe` 改用 `_buildRequest()`**

把 `transcribe` 方法中：
```dart
        'request': {'model_name': 'bigmodel', 'show_utterances': true},
```
替换为：
```dart
        'request': _buildRequest(),
```

- [ ] **Step 4: `transcribeFromUrl` 改用 `_buildRequest()`**

把 `transcribeFromUrl` 方法中同样的：
```dart
        'request': {'model_name': 'bigmodel', 'show_utterances': true},
```
替换为：
```dart
        'request': _buildRequest(),
```

- [ ] **Step 5: `submitAsync` 改用 `_buildRequest()`**

把 `submitAsync` 方法 data 中的：
```dart
        'request': {'model_name': 'bigmodel', 'show_utterances': true},
```
替换为：
```dart
        'request': _buildRequest(),
```

> `queryAsync` **不改**：查询接口请求体为 `{}`，不传 corpus。

- [ ] **Step 6: 格式化 + 分析**

Run:
```bash
dart format lib/services/asr_service.dart
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 7: 提交**

```bash
git add lib/services/asr_service.dart
git commit -m "feat(asr): Flash/异步识别注入个性化 corpus.context"
```

---

### Task 3: `RealtimeAsrService` 配置帧注入 `corpus`

**Files:**
- Modify: `lib/services/realtime_asr_service.dart`

**Interfaces:**
- Consumes: `String? buildAsrCorpusContext({String? hotwords, String? prompt})`（Task 1 产出）。
- Produces: `connect()` 发出的配置帧 `request` 在配置了 env 时带 `corpus.context`。

- [ ] **Step 1: 新增 import**

在 `lib/services/realtime_asr_service.dart` 顶部 import 区（`import '../exceptions.dart';` 之后）新增：

```dart
import 'asr_context_builder.dart';
```

- [ ] **Step 2: 配置帧注入 corpus**

在 `connect()` 方法中，把配置帧的 `request`：
```dart
      'request': {
        'model_name': 'bigmodel',
        'enable_itn': true,
        'enable_punc': true,
        'show_utterances': true,
      },
```
替换为构建逻辑（realtime 的 request 字段与 flash 不同，单独就地构建）：

```dart
      'request': _buildRealtimeRequest(),
```

并在 `RealtimeAsrService` 类内（`connect` 之前）新增方法：

```dart
  /// 构建实时 ASR 配置帧的 `request` 字段，按需注入个性化 `corpus.context`。
  Map<String, dynamic> _buildRealtimeRequest() {
    final request = <String, dynamic>{
      'model_name': 'bigmodel',
      'enable_itn': true,
      'enable_punc': true,
      'show_utterances': true,
    };
    final corpusContext = buildAsrCorpusContext(
      hotwords: dotenv.maybeGet('ASR_HOTWORDS'),
      prompt: dotenv.maybeGet('ASR_CONTEXT_PROMPT'),
    );
    if (corpusContext != null) {
      request['corpus'] = {'context': corpusContext};
    }
    return request;
  }
```

> realtime 复用同一 `buildAsrCorpusContext` 纯函数，保证三个接口的 context 构建逻辑一致。realtime 流式热词上限 100 tokens（当前 env 词量远低于此）。

- [ ] **Step 3: 格式化 + 分析**

Run:
```bash
dart format lib/services/realtime_asr_service.dart
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 提交**

```bash
git add lib/services/realtime_asr_service.dart
git commit -m "feat(asr): 实时 ASR 配置帧注入个性化 corpus.context"
```

---

### Task 4: 端到端验证 + 合并降级判定

**Files:**
- 无代码改动（除非触发降级，则 Modify `lib/services/asr_context_builder.dart`）。

**目的：** 验证（a）注入后 ASR 不报错；（b）专名识别确实改善；（c）`hotwords` 与 `dialog_ctx` 合并存于同一 `context` 是否被火山引擎接受（spec 风险点）。若不被接受，执行预案降级。

- [ ] **Step 1: 确认 env 已就位**

确认 `.env.local` 含（Task 前已写入）：
```
ASR_HOTWORDS=glimmer,harness,eyeguide,ears,肖伟红,...
ASR_CONTEXT_PROMPT=我使用标准普通话...西安市...
```
未配置时此步跳过（无增强可验证）。

- [ ] **Step 2: 运行 dev 版本**

Run: `./scripts/run_dev.sh`
录制一段**自然包含专名**的语音，例如："今天和肖伟红聊了 glimmer 这个项目，王碧岩也在"，时长约 10-30 秒。

- [ ] **Step 3: 观察结果**

进入识别流程，检查：
1. ASR 是否**正常返回**（无接口错误、无超时）。
2. 实时预览文本与最终 utterances 中，「肖伟红」「glimmer」「王碧岩」是否被正确识别（对比改动前）。
3. Flutter 控制台**无** ASR 相关报错（特别关注是否因 `corpus.context` 格式被拒）。

- [ ] **Step 4: 合并降级判定**

- 若 ASR 正常且专名识别改善 → **验证通过**，无需降级，本计划结束。
- 若 ASR 报错/拒绝请求体，或其中一项（hotwords 或 dialog_ctx）明显未生效 → 触发降级：

  编辑 `lib/services/asr_context_builder.dart` 的 `buildAsrCorpusContext`，**优先保留 hotwords**（专名是主要痛点），移除 `context_type` / `context_data` 分支。具体：删除函数中如下两段：

  ```dart
  // 删除：hasPrompt 相关判定与赋值
  final hasPrompt = ...;
  if (hasPrompt) { ... }
  ```
  并把函数开头判空改为仅依据 `words.isEmpty`：

  ```dart
  if (words.isEmpty) return null;
  ```

  随后运行：
  ```bash
  dart format lib/services/asr_context_builder.dart
  flutter test test/asr_context_builder_test.dart
  flutter analyze
  ```
  > 注意：降级后 `test/asr_context_builder_test.dart` 中涉及 prompt 的用例需相应改写为"prompt 不再产生 context_type/context_data"，保持测试与新行为一致（hotwords 仍可注入、prompt 被忽略）。

  改写测试 + 重新通过后提交：
  ```bash
  git add lib/services/asr_context_builder.dart test/asr_context_builder_test.dart
  git commit -m "fix(asr): corpus.context 降级为仅 hotwords（API 不支持与 dialog_ctx 合并）"
  ```
  然后回到 Step 2 重新验证。

- [ ] **Step 5: 记录结论**

在 plan 文件顶部或 commit 里注明实测结论（合并是否被接受 / 是否降级），供后续 L2 决策参考。

---

## Self-Review 结论

- **Spec 覆盖**：env 读取与构建 → Task 1；Flash 两接口 + 异步 submit → Task 2；realtime → Task 3；queryAsync 不传（符合 spec）→ Task 2 Step 5 已注明；env 缺失不注入 → Task 1 纯函数 + 各注入点的 null 判定；合并降级预案 → Task 4 Step 4。✅
- **占位符**：无 TBD/TODO，每个代码步骤均含完整代码。✅
- **类型一致**：`buildAsrCorpusContext({String? hotwords, String? prompt}) → String?` 在 Task 1/2/3 中签名一致；`_buildRequest()` / `_buildRealtimeRequest()` 返回 `Map<String, dynamic>`。✅

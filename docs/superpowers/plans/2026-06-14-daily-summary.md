# 每日总结（Daily Summary）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在「天」的维度上，把一天内所有录音的原始 ASR 全文重组为一篇连贯日记（标题 + 正文 + 播报），每天首次打开 app 自动生成昨天的总结，支持手动生成/重新生成/删除，并在按天分组的列表中查看。

**Architecture:** 新增独立的「日」实体——`DailySummaries` 表（元数据）+ `daily/daily_summary_<date>.json`（正文），遵循「元数据入库 + 正文入文件」策略。引入 `ProcessingTask` 接口，把录音处理与每日总结各封装为 Task，`ProcessingTaskHandler`（现有 `recording_processor.dart`）退化为调度两类任务的调度器。LLM 聚合由新建的 `DailySummaryService` 负责（读各篇 transcript → 拼接 → 超长降级 → 调 LLM），UI 在 list 日期分组下增加「本日总结」入口 + 新增 `DailySummaryPage`。

**Tech Stack:** Flutter / Dart、drift（SQLite ORM）+ build_runner、flutter_foreground_task（FGS 调度）、dio（LLM HTTP）、mocktail（测试 mock）、flutter_markdown（正文渲染）。

---

## 与 spec 的关键差异说明（必读）

spec 在 `docs/superpowers/specs/2026-06-14-daily-summary-design.md`。本计划在以下几处对 spec 做了工程化落地决策，实现时请遵循本计划：

1. **`summarizeDay` 归属 `DailySummaryService` 而非 `LlmService`**。spec 5.1 写 `LlmService.summarizeDay(List<DiaryEntry>)`，但该方法需读取各 entry 的 `transcript.json`（文件 IO）。现有 `LlmService` 仅依赖 `dio` + `dotenv`，引入文件 IO 会破坏其单一职责且无法注入测试。**决策**：新建 `DailySummaryService`，组合 `DiaryStorageService`（读文件）+ `LlmService`（纯 LLM 调用）；`LlmService` 新增一个**纯 LLM 调用**方法 `summarizeDayText(String text, {required bool degraded})`。拼接/降级逻辑提取为纯函数以便单测。

2. **复用 `EntryStatus` 枚举**。spec 说 DailySummary 的 status「与 DiaryEntries 语义一致」。`EntryStatus { processing, completed, failed }`（`lib/models/diary_entry.dart`）已满足，直接复用，不新增枚举，DRY。

3. **drift 行类名冲突处理**。drift 会为 `DailySummaries` 表生成行数据类 `DailySummary`，与本计划自定义的 model 同名。沿用现有 `diary_storage_service.dart` 的 `hide DiaryEntry, Tag, DiaryTagRelation` 模式——`hide` 掉 drift 生成的 `DailySummary`，使用 `lib/models/daily_summary.dart` 中自定义的 `DailySummary`。

4. **测试引入 `mocktail`**。项目当前无 mock 框架（`pubspec.yaml` dev_dependencies 仅 flutter_test/lints/drift_dev/build_runner/launcher_icons）。纯函数（拼接/降级/天气聚合/json 往返）直接 TDD；服务/调度层用 `mocktail` mock `LlmService`/`DiaryStorageService`。`mocktail` 零 codegen，是 Dart 社区主流选择。

5. **daily_summary_page 的 TTS 播报按钮为新建**。经核查 `diary_detail_page.dart` 当前**未集成** TTS（`_retry` 是同步调用 ASR/LLM，不走 TTS）。`TtsService.speak(text, voiceType)` 接口可用，本计划在 `DailySummaryPage` 内新建播报按钮调用它，不复用任何「现有播报按钮」（不存在）。

6. **list 分组 key 由 label 改为日期字符串**。现有 `_buildDateGroups` 用「今天（6月14日）」这样的 label 作 `Map` key，无法反查 `'yyyy-MM-dd'` 对应的 DailySummary。改造为按 `'yyyy-MM-dd'` 分组（label 仅用于显示），使每个分组能查到对应 DailySummary。

---

## 文件结构

### 新建文件

| 文件 | 职责 |
|---|---|
| `lib/models/daily_summary.dart` | `DailySummary`（DB 行 model）+ `DailySummaryData`（正文文件，带 version）+ `DailySummaryResult`（LLM 返回）+ `DayWeatherSummary` + 纯函数（`buildDayFullText` / `shouldDegrade` / `buildDaySummariesText` / `aggregateDayWeather`） |
| `lib/services/daily_summary_service.dart` | `DailySummaryService.summarizeDay(List<DiaryEntry>) → DailySummaryResult`：读 transcript/llm_result → 拼接 → 降级 → 调 `LlmService` → 记 API 日志 |
| `lib/services/processing_task.dart` | `ProcessingTask` 接口 + `ProcessingContext`（共享依赖容器） |
| `lib/services/diary_processing_task.dart` | `DiaryProcessingTask(DiaryEntry)`：从现有 `ProcessingTaskHandler` 提取 `_processEntry`/`_doUpload`/`_doAsr`/`_doLlm`/`_doTagging`/`_doComplete`/`_handleEmptyAsr`/`_markFailed`，行为完全不变 |
| `lib/services/daily_summary_processing_task.dart` | `DailySummaryProcessingTask(String date)`：查当天 entries → `summarizeDay` → 写文件 + DB；失败标记 `status=failed` 并抛 `DailySummaryException` |
| `lib/pages/daily_summary_page.dart` | 每日总结详情页：AppBar（聚合天气）+ 正文（Markdown）+ outline TTS 播报 + 当天录音列表 + 状态横幅 |
| `test/daily_summary_test.dart` | 纯函数测试：拼接/降级/天气聚合/json 往返 |
| `test/daily_summary_service_test.dart` | mock LLM/Storage，验证 summarizeDay 流程与降级 |
| `test/processing_task_test.dart` | mock 两类 Task，验证调度顺序与错误隔离 |
| `test/daily_summary_storage_test.dart` | DailySummary 文件/DB 读写 |

### 修改文件

| 文件 | 改动 |
|---|---|
| `lib/exceptions.dart` | 新增 `DailySummaryException extends AppException` |
| `lib/services/database/tables.dart` | 新增 `DailySummaries` 表 |
| `lib/services/database/app_database.dart` | `tables` 加 `DailySummaries`、`schemaVersion` 7→8、`onUpgrade` 加 `if (from < 8)` 块、新增 DailySummary 查询方法 |
| `lib/services/database/app_database.g.dart` | build_runner 重新生成（勿手改） |
| `lib/services/diary_storage_service.dart` | `hide` drift 的 `DailySummary`；新增 `getEntriesByDate` / DailySummary CRUD / `writeDailySummaryJson` / `readDailySummaryJson` / `hasDailySummary` / `deleteDailySummary` |
| `lib/services/llm_service.dart` | 新增 `summarizeDayText(String text, {required bool degraded}) → DailySummaryResult`（纯 LLM 调用） |
| `lib/services/recording_processor.dart` | `ProcessingTaskHandler.onStart` 改为调度 `ProcessingTask` 列表（录音在前、总结在后） |
| `lib/main.dart` | 新增 `_runDailySummaryIfNeeded()`，在 `main()` 中调用 |
| `lib/pages/diary_list_page.dart` | `_buildDateGroups` 改按日期分组 + 每组下「本日总结」行；`_onTaskData` 扩展监听 dailySummary 消息 |
| `pubspec.yaml` | dev_dependencies 加 `mocktail` |

---

## 任务总览（按依赖顺序执行）

1. **基础设施**：加 `mocktail` + `DailySummaryException`
2. **数据模型 + 纯函数**：`daily_summary.dart`（model/data/result + 拼接/降级/天气聚合）
3. **drift 数据层**：表 + migration + build_runner + DB 查询 + storage 读写
4. **DailySummaryService**：LLM 聚合 + 超长降级 + API 日志
5. **任务抽象**：`ProcessingTask` 接口 + `ProcessingContext` + `DiaryProcessingTask`（提取）
6. **DailySummaryProcessingTask + 调度器改造**
7. **启动钩子**：`main.dart` `_runDailySummaryIfNeeded`
8. **DailySummary 详情页**（天气聚合 + TTS + 状态横幅）
9. **list 分组重构 + 「本日总结」行 + 手动生成/重新生成/删除 + FGS 消息**
10. **收尾**：`flutter analyze` 清零 + `dart format` + 集成验证

> 全程遵循 CLAUDE.md：提交前对改动文件运行 `dart format` + `flutter analyze` 清零；commit message 用中文；异常用派生类、按类型捕获。

---

## Task 1: 基础设施（mocktail 依赖 + DailySummaryException）

**Files:**
- Modify: `pubspec.yaml`（dev_dependencies 加 mocktail）
- Modify: `lib/exceptions.dart`（新增 DailySummaryException）
- Test: `test/daily_summary_exception_test.dart`

- [ ] **Step 1: 加 mocktail 到 dev_dependencies**

在 `pubspec.yaml` 的 `dev_dependencies:` 下，`flutter_launcher_icons` 之后新增一行：

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  drift_dev: ^2.22.1
  build_runner: ^2.4.14
  flutter_launcher_icons: ^0.14.3
  mocktail: ^1.0.4
```

- [ ] **Step 2: 运行 `flutter pub get` 确认依赖可解析**

Run: `flutter pub get`
Expected: 输出 `Got dependencies!`（或类似），无版本冲突报错。

- [ ] **Step 3: 写失败测试（DailySummaryException 是 AppException 子类、可按类型捕获）**

创建 `test/daily_summary_exception_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/exceptions.dart';

void main() {
  test('DailySummaryException 是 AppException 子类，携带 message', () {
    const exc = DailySummaryException('昨天录音尚未处理完成');
    expect(exc, isA<AppException>());
    expect(exc.message, '昨天录音尚未处理完成');
    expect(exc.toString(), '昨天录音尚未处理完成');
  });

  test('可按 DailySummaryException 类型捕获，不被通用 AppException 吞掉', () {
    Object thrown() {
      throw const DailySummaryException('聚合失败');
    }

    // 按 DailySummaryException 捕获
    expect(
      () => thrown(),
      throwsA(isA<DailySummaryException>()),
    );
    // 同时也是 AppException
    expect(
      () => thrown(),
      throwsA(isA<AppException>()),
    );
  });
}
```

- [ ] **Step 4: 运行测试，确认失败**

Run: `flutter test test/daily_summary_exception_test.dart`
Expected: FAIL，报 `DailySummaryException isn't defined`（类尚未创建）。

- [ ] **Step 5: 实现 DailySummaryException**

在 `lib/exceptions.dart` 末尾（`ProcessingException` 类之后）追加：

```dart
/// 每日总结相关异常（LLM 聚合失败、当天录音尚未处理完成等）。
class DailySummaryException extends AppException {
  const DailySummaryException(super.message);
}
```

- [ ] **Step 6: 运行测试，确认通过**

Run: `flutter test test/daily_summary_exception_test.dart`
Expected: PASS（2 个测试全过）。

- [ ] **Step 7: 提交**

```bash
git add pubspec.yaml pubspec.lock lib/exceptions.dart test/daily_summary_exception_test.dart
git commit -m "feat: 新增 DailySummaryException 与 mocktail 测试依赖"
```

---

## Task 2: 数据模型 + 纯函数（daily_summary.dart）

定义 `DailySummary`（DB 元数据 model）、`DailySummaryData`（正文文件）、`DayWeatherSummary`，以及可单测的纯函数：全文拼接 / 降级判断 / summary 聚合 / 天气聚合。

> **分层注意**：本文件属于 `models` 层，**不得 import `services`**。因此 `DailySummaryResult`（含 `LlmUsage`，属 services 层）放到 Task 4 的 `daily_summary_service.dart`，不在这里。

**Files:**
- Create: `lib/models/daily_summary.dart`
- Test: `test/daily_summary_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/daily_summary_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/daily_summary.dart';
import 'package:voice_diary/models/diary_entry.dart';

DiaryEntry _entry({
  required DateTime createdAt, {
  String? weatherIcon,
  String? weatherText,
  String? temperature,
  String? locationName,
}) {
  return DiaryEntry(
    id: createdAt.millisecondsSinceEpoch.toString(),
    title: 't',
    folderPath: '/x',
    durationSeconds: 0,
    createdAt: createdAt,
    weatherIcon: weatherIcon,
    weatherText: weatherText,
    temperature: temperature,
    locationName: locationName,
  );
}

void main() {
  group('buildDayFullText', () {
    test('多篇按顺序拼接，分隔标记含序号与 HH:mm', () {
      final text = buildDayFullText([
        (createdAt: DateTime(2026, 6, 13, 9, 5), text: '早上好'),
        (createdAt: DateTime(2026, 6, 13, 14, 30), text: '下午开会了'),
      ]);
      expect(text, contains('### 第 1 段 · 09:05'));
      expect(text, contains('早上好'));
      expect(text, contains('### 第 2 段 · 14:30'));
      expect(text, contains('下午开会了'));
    });

    test('空列表返回空字符串', () {
      expect(buildDayFullText(const []), '');
    });

    test('去除片段首尾空白', () {
      final text = buildDayFullText([
        (createdAt: DateTime(2026, 6, 13, 9), text: '  带空白  '),
      ]);
      expect(text, contains('带空白'));
      expect(text, isNot(contains('  带空白')));
    });
  });

  group('shouldDegrade', () {
    test('等于阈值不降级（> 才降级）', () {
      expect(shouldDegrade('a' * 25000), isFalse);
    });
    test('超过阈值降级', () {
      expect(shouldDegrade('a' * 25001), isTrue);
    });
  });

  group('buildDaySummariesText', () {
    test('降级拼接各篇 summary，含标题', () {
      final text = buildDaySummariesText([
        (
          createdAt: DateTime(2026, 6, 13, 9),
          title: '早晨',
          summary: '晨跑',
        ),
      ]);
      expect(text, contains('### 第 1 段 · 09:00（早晨）'));
      expect(text, contains('晨跑'));
    });
  });

  group('aggregateDayWeather', () {
    test('天气取众数 icon、温度取 min~max、地点取众数', () {
      final agg = aggregateDayWeather([
        _entry(
          createdAt: DateTime(2026, 6, 13, 9),
          weatherIcon: '104',
          weatherText: '阴',
          temperature: '18',
          locationName: '海淀区',
        ),
        _entry(
          createdAt: DateTime(2026, 6, 13, 14),
          weatherIcon: '104',
          weatherText: '阴',
          temperature: '25',
          locationName: '海淀区',
        ),
        _entry(
          createdAt: DateTime(2026, 6, 13, 20),
          weatherIcon: '100',
          weatherText: '晴',
          temperature: '22',
          locationName: '朝阳区',
        ),
      ]);
      expect(agg.weatherIcon, '104'); // 104 出现 2 次 > 100 的 1 次
      expect(agg.weatherText, '阴');
      expect(agg.tempMin, 18);
      expect(agg.tempMax, 25);
      expect(agg.tempDisplay, '18°~25°');
      expect(agg.locationName, '海淀区');
      expect(agg.isEmpty, isFalse);
    });

    test('温度全相同只显示单值', () {
      final agg = aggregateDayWeather([
        _entry(createdAt: DateTime(2026, 6, 13, 9), temperature: '24'),
        _entry(createdAt: DateTime(2026, 6, 13, 14), temperature: '24'),
      ]);
      expect(agg.tempDisplay, '24°');
    });

    test('无任何天气数据时 isEmpty', () {
      final agg = aggregateDayWeather([
        _entry(createdAt: DateTime(2026, 6, 13, 9)),
      ]);
      expect(agg.isEmpty, isTrue);
      expect(agg.tempDisplay, '');
    });

    test('非数字温度被忽略', () {
      final agg = aggregateDayWeather([
        _entry(createdAt: DateTime(2026, 6, 13, 9), temperature: 'abc'),
        _entry(createdAt: DateTime(2026, 6, 13, 14), temperature: '20'),
      ]);
      expect(agg.tempMin, 20);
      expect(agg.tempMax, 20);
    });
  });

  group('DailySummaryData', () {
    test('toJson / fromJson 往返保持字段', () {
      final original = DailySummaryData(
        version: 1,
        date: '2026-06-13',
        title: '标题',
        summary: '## 正文',
        outline: '播报',
        sourceEntryIds: const ['uuid1', 'uuid2'],
        degraded: true,
      );
      final restored = DailySummaryData.fromJson(original.toJson());
      expect(restored.version, 1);
      expect(restored.date, '2026-06-13');
      expect(restored.title, '标题');
      expect(restored.summary, '## 正文');
      expect(restored.outline, '播报');
      expect(restored.sourceEntryIds, ['uuid1', 'uuid2']);
      expect(restored.degraded, isTrue);
    });

    test('fromJson 容错：缺字段降级为默认值', () {
      final restored = DailySummaryData.fromJson({});
      expect(restored.version, 1);
      expect(restored.title, '');
      expect(restored.degraded, isFalse);
      expect(restored.sourceEntryIds, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/daily_summary_test.dart`
Expected: FAIL，报 `buildDayFullText` / `DailySummaryData` 等未定义。

- [ ] **Step 3: 实现 lib/models/daily_summary.dart**

创建 `lib/models/daily_summary.dart`：

```dart
import 'diary_entry.dart';

// --- 容错解析工具（与 utterance.dart 一致的降级风格）---
String _asString(dynamic v) =>
    v is String ? v : (v == null ? '' : v.toString());

int _asInt(dynamic v, [int def = 0]) =>
    v is int ? v : (v is num ? v.toInt() : def);

/// 每日总结的元数据，对应 SQLite DailySummaries 表的一行。
class DailySummary {
  /// 日期 'yyyy-MM-dd'，主键。
  final String date;
  final String title;
  final EntryStatus status;
  final List<String> sourceEntryIds;
  final int entryCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const DailySummary({
    required this.date,
    required this.title,
    required this.status,
    required this.sourceEntryIds,
    required this.entryCount,
    required this.createdAt,
    this.updatedAt,
  });

  DailySummary copyWith({
    String? title,
    EntryStatus? status,
    List<String>? sourceEntryIds,
    int? entryCount,
    DateTime? updatedAt,
  }) {
    return DailySummary(
      date: date,
      title: title ?? this.title,
      status: status ?? this.status,
      sourceEntryIds: sourceEntryIds ?? this.sourceEntryIds,
      entryCount: entryCount ?? this.entryCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 每日总结正文文件 daily/daily_summary_<date>.json 的模型。
class DailySummaryData {
  final int version;
  final String date;
  final String title;
  final String summary;
  final String outline;
  final List<String> sourceEntryIds;
  final bool degraded;

  const DailySummaryData({
    required this.version,
    required this.date,
    required this.title,
    required this.summary,
    required this.outline,
    required this.sourceEntryIds,
    required this.degraded,
  });

  factory DailySummaryData.fromJson(Map<String, dynamic> json) {
    return DailySummaryData(
      version: _asInt(json['version'], 1),
      date: _asString(json['date']),
      title: _asString(json['title']),
      summary: _asString(json['summary']),
      outline: _asString(json['outline']),
      sourceEntryIds:
          (json['sourceEntryIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      degraded: json['degraded'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'date': date,
    'title': title,
    'summary': summary,
    'outline': outline,
    'sourceEntryIds': sourceEntryIds,
    'degraded': degraded,
  };
}

/// 一天的天气聚合结果（详情页现算，不入库）。
class DayWeatherSummary {
  final String? locationName;
  final String? weatherIcon;
  final String? weatherText;
  final num? tempMin;
  final num? tempMax;

  const DayWeatherSummary({
    this.locationName,
    this.weatherIcon,
    this.weatherText,
    this.tempMin,
    this.tempMax,
  });

  bool get isEmpty =>
      locationName == null &&
      weatherIcon == null &&
      weatherText == null &&
      tempMin == null;

  /// 温度展示：无数据→''；全相同→'24°'；有差异→'18°~25°'。
  String get tempDisplay {
    if (tempMin == null || tempMax == null) return '';
    if (tempMin == tempMax) return '${tempMin!.round()}°';
    return '${tempMin!.round()}°~${tempMax!.round()}°';
  }
}

/// 超长降级阈值（拼接全文超过此字数则退回各篇 summary 聚合）。
const int kDaySummaryDegradeThreshold = 25000;

/// 各篇录音供全文拼接的片段：创建时刻 + 该篇 ASR 全文。
typedef DayFullTextSegment = ({DateTime createdAt, String text});

/// 把一天各篇 ASR 全文按时间顺序拼接，篇间插入分隔标记。
/// 标记格式：`### 第 N 段 · HH:mm`（HH:mm 取该篇 createdAt 时刻）。
String buildDayFullText(List<DayFullTextSegment> segments) {
  final buf = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final hh = s.createdAt.hour.toString().padLeft(2, '0');
    final mm = s.createdAt.minute.toString().padLeft(2, '0');
    buf.writeln('### 第 ${i + 1} 段 · $hh:$mm');
    buf.writeln(s.text.trim());
    buf.writeln();
  }
  return buf.toString().trimRight();
}

/// 拼接全文是否超过降级阈值。
bool shouldDegrade(String fullText) =>
    fullText.length > kDaySummaryDegradeThreshold;

/// 降级模式下各篇供拼接的片段：创建时刻 + 标题 + summary。
typedef DaySummarySegment = ({
  DateTime createdAt,
  String title,
  String summary,
});

/// 降级模式：拼接各篇 LLM summary（而非全文）。
String buildDaySummariesText(List<DaySummarySegment> segments) {
  final buf = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final hh = s.createdAt.hour.toString().padLeft(2, '0');
    final mm = s.createdAt.minute.toString().padLeft(2, '0');
    buf.writeln('### 第 ${i + 1} 段 · $hh:$mm（${s.title}）');
    buf.writeln(s.summary.trim());
    buf.writeln();
  }
  return buf.toString().trimRight();
}

/// 取频次最高的 key（众数）；空 map 返回 null；平局取先出现的。
String? _modeKey(Map<String, int> counts) {
  if (counts.isEmpty) return null;
  var bestKey = counts.keys.first;
  var bestCount = counts[bestKey]!;
  counts.forEach((k, v) {
    if (v > bestCount) {
      bestKey = k;
      bestCount = v;
    }
  });
  return bestKey;
}

/// 聚合一天各篇录音的天气：地点众数 + 天气众数（按 weatherIcon 统计）+ 温度 min~max。
/// 详情页现算，不入库；全无数据时返回 isEmpty 的对象。
DayWeatherSummary aggregateDayWeather(List<DiaryEntry> entries) {
  final locCounts = <String, int>{};
  final iconCounts = <String, int>{};
  final iconToText = <String, String>{};
  final temps = <num>[];

  for (final e in entries) {
    final loc = e.locationName;
    if (loc != null && loc.isNotEmpty) {
      locCounts[loc] = (locCounts[loc] ?? 0) + 1;
    }
    final icon = e.weatherIcon;
    if (icon != null && icon.isNotEmpty) {
      iconCounts[icon] = (iconCounts[icon] ?? 0) + 1;
      if (!iconToText.containsKey(icon) &&
          e.weatherText != null &&
          e.weatherText!.isNotEmpty) {
        iconToText[icon] = e.weatherText!;
      }
    }
    final temp = e.temperature;
    if (temp != null && temp.isNotEmpty) {
      final n = num.tryParse(temp);
      if (n != null) temps.add(n);
    }
  }

  final iconMode = _modeKey(iconCounts);

  num? tempMin;
  num? tempMax;
  if (temps.isNotEmpty) {
    temps.sort();
    tempMin = temps.first;
    tempMax = temps.last;
  }

  return DayWeatherSummary(
    locationName: _modeKey(locCounts),
    weatherIcon: iconMode,
    weatherText: iconMode == null ? null : iconToText[iconMode],
    tempMin: tempMin,
    tempMax: tempMax,
  );
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/daily_summary_test.dart`
Expected: PASS（全部用例通过）。

- [ ] **Step 5: 提交**

```bash
dart format lib/models/daily_summary.dart test/daily_summary_test.dart
git add lib/models/daily_summary.dart test/daily_summary_test.dart
git commit -m "feat: 新增每日总结数据模型与拼接/降级/天气聚合纯函数"
```

---

## Task 3: drift 数据层（表 + migration + DB 查询 + storage 读写）

> **命名决策（取代 header 差异说明第 3 条的 hide 方案）**：drift 默认会为表 `DailySummaries` 生成行类 `DailySummary`，与我们的 model 同名。采用 drift 的 `@DataClassName('DailySummaryRow')` 注解，把生成的行类命名为 `DailySummaryRow`，**彻底避免冲突**——`diary_storage_service.dart` 无需 `hide`，model 与 drift 行类各叫各的名字，更干净。

> **测试现实性说明**：DB 层依赖 drift 代码生成，无法严格「先红后绿」。本任务采用「改表/查询 → build_runner 生成 → 内存 DB 测试验证」流程。为支持内存 DB 测试，给 `AppDatabase` 加一个 `forTesting` 注入构造（绕过单例）。

**Files:**
- Modify: `lib/services/database/tables.dart`（新增 DailySummaries 表）
- Modify: `lib/services/database/app_database.dart`（tables 列表、schemaVersion 8、migration、forTesting 构造、查询方法）
- Regenerate: `lib/services/database/app_database.g.dart`（build_runner）
- Modify: `lib/services/diary_storage_service.dart`（getEntriesByDate、DailySummary CRUD、正文文件 IO）
- Test: `test/daily_summary_storage_test.dart`

- [ ] **Step 1: 在 tables.dart 新增 DailySummaries 表**

在 `lib/services/database/tables.dart` 的 `ApiLogs` 类之后追加：

```dart
/// 每日总结元数据表。每行对应一天的「日」总结实体。
/// 行类名用 DataClassName 显式指定为 DailySummaryRow，避免与 model 层的
/// DailySummary（lib/models/daily_summary.dart）同名冲突。
@DataClassName('DailySummaryRow')
class DailySummaries extends Table {
  /// 日期 'yyyy-MM-dd'，主键。
  TextColumn get date => text()();

  TextColumn get title => text()();

  /// processing / completed / failed（与 DiaryEntries.status 语义一致）。
  TextColumn get status =>
      text().withDefault(const Constant('processing'))();

  /// 参与总结的录音 id 列表，JSON 数组字符串，如 '["uuid1","uuid2"]'。
  TextColumn get sourceEntryIds => text().withDefault(const Constant('[]'))();

  IntColumn get entryCount => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {date};
}
```

- [ ] **Step 2: 改 app_database.dart — tables 列表 + forTesting + schemaVersion + migration**

2a. 把 `@DriftDatabase` 的 tables 列表加上 `DailySummaries`（约第 12 行）：

```dart
@DriftDatabase(
  tables: [DiaryEntries, Tags, DiaryTagRelations, ApiLogs, DailySummaries],
)
```

2b. 在 `AppDatabase._internal()` 之后、`factory AppDatabase()` 之前，新增测试注入构造（约第 14-15 行）：

```dart
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal() : super(_openConnection());
  static AppDatabase? _instance;

  /// 仅用于测试：注入内存或其他 executor，绕过单例与文件连接。
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  /// 单例工厂。
  ///
  /// AppDatabase 内部用 NativeDatabase.createInBackground，每个实例都会起一个独立
  /// 后台 isolate 连接 voice_diary.db。代码里 DiaryStorageService / ApiLogService 以及
  /// 各页面都各自 `new`，会导致同一 isolate 内并存多个连接（资源浪费 + 并发写 SQLITE_BUSY）。
  /// 全 app 共享同一实例后，每个 isolate 只剩一个连接。
  ///
  /// 注：Dart static 是「每 isolate 一份」，主 isolate 与 FGS isolate 各自持有一个实例——
  /// 这正是所需（drift 连接不能跨 isolate），符合预期。
  factory AppDatabase() => _instance ??= AppDatabase._internal();
```

2c. 把 `schemaVersion` 从 `7` 改为 `8`（约第 29 行）：

```dart
  @override
  int get schemaVersion => 8;
```

2d. 在 `onUpgrade` 的 `if (from < 7) { ... }` 块之后、闭合之前，新增 `if (from < 8)` 块（约第 93 行之后）：

```dart
      if (from < 7) {
        if (!await _tableExists('api_logs')) await m.createTable(apiLogs);
      }
      if (from < 8) {
        if (!await _tableExists('daily_summaries')) {
          await m.createTable(dailySummaries);
        }
      }
```

- [ ] **Step 3: 重新生成 drift 代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 输出含 `Built build_xxx`，无错误。生成 `DailySummaryRow`、`DailySummariesCompanion` 等。若提示冲突，确认用的是 `--delete-conflicting-outputs`。

- [ ] **Step 4: 在 app_database.dart 新增 DailySummary 查询方法 + getEntriesByDate**

在 `// --- ApiLogs ---` 区块之后、类闭合 `}` 之前（约第 240 行 `getRecentLogs` 方法之后）追加：

```dart
  // --- DailySummaries ---

  Future<DailySummaryRow?> getDailySummaryByDate(String date) {
    return (select(dailySummaries)..where((t) => t.date.equals(date)))
        .getSingleOrNull();
  }

  Future<List<DailySummaryRow>> getPendingDailySummaries() {
    return (select(dailySummaries)
          ..where((t) => t.status.equals('processing'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<DailySummaryRow>> getAllDailySummaries() {
    return (select(dailySummaries)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  Future<void> upsertDailySummary(DailySummariesCompanion row) {
    return into(dailySummaries).insert(row, mode: InsertMode.insertOrReplace);
  }

  Future<void> deleteDailySummaryRow(String date) {
    return (delete(dailySummaries)..where((t) => t.date.equals(date))).go();
  }

  /// 查询某天（'yyyy-MM-dd'）的所有日记条目，按 createdAt 升序。
  /// 用半开区间 [start, end) 避免边界包含次日 0 点。
  Future<List<DiaryEntry>> getEntriesByDate(String date) {
    final day = DateTime.parse(date);
    final start =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = DateTime(day.year, day.month, day.day)
        .add(const Duration(days: 1))
        .millisecondsSinceEpoch;
    return (select(diaryEntries)
          ..where(
            (t) =>
                t.createdAt.isBiggerOrEqualValue(start) &
                t.createdAt.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
```

- [ ] **Step 5: 写内存 DB 测试**

创建 `test/daily_summary_storage_test.dart`：

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => await db.close());

  group('DailySummaries CRUD', () {
    test('upsertDailySummary 插入并可按 date 读取', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: '一天的总结',
          status: const Value('completed'),
          sourceEntryIds: const Value('["u1","u2"]'),
          entryCount: const Value(2),
          createdAt: 1,
        ),
      );
      final got = await db.getDailySummaryByDate('2026-06-13');
      expect(got, isNotNull);
      expect(got!.title, '一天的总结');
      expect(got.status, 'completed');
      expect(got.entryCount, 2);
    });

    test('相同 date upsert 覆盖（insertOrReplace）', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: '旧',
          createdAt: 1,
        ),
      );
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: '新',
          createdAt: 2,
        ),
      );
      final got = await db.getDailySummaryByDate('2026-06-13');
      expect(got!.title, '新');
      expect(got.createdAt, 2);
    });

    test('getPendingDailySummaries 只返回 processing', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: 'a',
          createdAt: 1,
          status: const Value('processing'),
        ),
      );
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-12',
          title: 'b',
          createdAt: 2,
          status: const Value('completed'),
        ),
      );
      final pending = await db.getPendingDailySummaries();
      expect(pending, hasLength(1));
      expect(pending.first.date, '2026-06-13');
    });

    test('deleteDailySummaryRow 删除', () async {
      await db.upsertDailySummary(
        DailySummariesCompanion.insert(
          date: '2026-06-13',
          title: 'a',
          createdAt: 1,
        ),
      );
      await db.deleteDailySummaryRow('2026-06-13');
      expect(await db.getDailySummaryByDate('2026-06-13'), isNull);
    });
  });

  group('getEntriesByDate', () {
    test('按当天范围过滤并按 createdAt 升序', () async {
      const day = '2026-06-13';
      final d = DateTime.parse(day);
      await db.insertEntry(
        DiaryEntriesCompanion.insert(
          id: 'e1',
          title: 't1',
          folderPath: '/p1',
          durationSeconds: 0,
          createdAt:
              DateTime(d.year, d.month, d.day, 20).millisecondsSinceEpoch,
        ),
      );
      await db.insertEntry(
        DiaryEntriesCompanion.insert(
          id: 'e2',
          title: 't2',
          folderPath: '/p2',
          durationSeconds: 0,
          createdAt:
              DateTime(d.year, d.month, d.day, 9).millisecondsSinceEpoch,
        ),
      );
      // 前一天，应被排除
      await db.insertEntry(
        DiaryEntriesCompanion.insert(
          id: 'e3',
          title: 't3',
          folderPath: '/p3',
          durationSeconds: 0,
          createdAt: DateTime(d.year, d.month, d.day - 1, 12)
              .millisecondsSinceEpoch,
        ),
      );
      final rows = await db.getEntriesByDate(day);
      expect(rows.map((r) => r.id), ['e2', 'e1']); // 9点在前
      expect(rows, hasLength(2));
    });

    test('当天无记录返回空列表', () async {
      expect(await db.getEntriesByDate('2020-01-01'), isEmpty);
    });
  });
}
```

- [ ] **Step 6: 运行测试，确认通过**

Run: `flutter test test/daily_summary_storage_test.dart`
Expected: PASS（6 个测试全过）。若报 `DailySummaryRow`/`DailySummariesCompanion` 未定义，回到 Step 3 确认 build_runner 成功。

- [ ] **Step 7: 在 diary_storage_service.dart 新增 storage 方法**

7a. 顶部 import 区加一行（在 `import '../models/utterance.dart';` 之后）：

```dart
import '../models/daily_summary.dart';
```

7b. 在 `readSummaryUtterances` 方法之后（`// --- llm_result.json ---` 区块之前，约第 162 行），新增 DailySummary 正文文件 IO + getEntriesByDate 包装 + 元数据 CRUD。为保持聚合，放在 `getAllEntries` 方法附近；这里统一追加到 `getPendingEntries` 方法（约第 476 行）之后、类闭合之前：

```dart
  // --- DailySummary：按日期查 entries ---

  /// 查询某天（'yyyy-MM-dd'）的录音条目，按 createdAt 升序。
  Future<List<DiaryEntry>> getEntriesByDate(String date) async {
    final rows = await _db.getEntriesByDate(date);
    return rows
        .map(
          (r) => DiaryEntry(
            id: r.id,
            title: r.title,
            folderPath: r.folderPath,
            durationSeconds: r.durationSeconds,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            tosKey: r.tosKey,
            audioFormat: r.audioFormat,
            uploadedAt: r.uploadedAt != null
                ? DateTime.fromMillisecondsSinceEpoch(r.uploadedAt!)
                : null,
            weatherIcon: r.weatherIcon,
            weatherText: r.weatherText,
            temperature: r.temperature,
            locationName: r.locationName,
            locationLat: r.locationLat,
            locationLon: r.locationLon,
            status: _parseStatus(r.status),
            processingStage: ProcessingStage.fromString(r.processingStage),
            asrTaskId: r.asrTaskId,
          ),
        )
        .toList();
  }

  // --- DailySummary 正文文件（<appDocDir>/daily/daily_summary_<date>.json）---

  Future<String> get _dailyDir async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'daily'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<File> _dailySummaryFile(String date) async {
    final dir = await _dailyDir;
    return File(p.join(dir, 'daily_summary_$date.json'));
  }

  Future<void> writeDailySummaryJson(String date, DailySummaryData data) async {
    final file = await _dailySummaryFile(date);
    await _writeAtomic(file, jsonEncode(data.toJson()));
  }

  Future<DailySummaryData> readDailySummaryJson(String date) async {
    final file = await _dailySummaryFile(date);
    final content = await file.readAsString();
    return DailySummaryData.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );
  }

  Future<bool> hasDailySummary(String date) async {
    final file = await _dailySummaryFile(date);
    return file.exists();
  }

  Future<void> deleteDailySummaryFile(String date) async {
    final file = await _dailySummaryFile(date);
    if (await file.exists()) await file.delete();
  }

  // --- DailySummary 元数据（DB）---

  Future<DailySummary?> getDailySummary(String date) async {
    final row = await _db.getDailySummaryByDate(date);
    return row == null ? null : _summaryRowToModel(row);
  }

  Future<List<DailySummary>> getPendingDailySummaries() async {
    final rows = await _db.getPendingDailySummaries();
    return rows.map(_summaryRowToModel).toList();
  }

  /// upsert：写入或覆盖某天的总结元数据。
  Future<void> saveDailySummary(DailySummary summary) async {
    await _db.upsertDailySummary(
      DailySummariesCompanion(
        date: Value(summary.date),
        title: Value(summary.title),
        status: Value(summary.status.name),
        sourceEntryIds: Value(jsonEncode(summary.sourceEntryIds)),
        entryCount: Value(summary.entryCount),
        createdAt: Value(summary.createdAt.millisecondsSinceEpoch),
        updatedAt: Value(summary.updatedAt?.millisecondsSinceEpoch),
      ),
    );
  }

  /// 删除某天的总结：删 DB 行 + 删正文文件（不动当天录音）。
  Future<void> deleteDailySummary(String date) async {
    await _db.deleteDailySummaryRow(date);
    await deleteDailySummaryFile(date);
  }

  DailySummary _summaryRowToModel(DailySummaryRow r) {
    return DailySummary(
      date: r.date,
      title: r.title,
      status: _parseStatus(r.status),
      sourceEntryIds: _parseSourceEntryIds(r.sourceEntryIds),
      entryCount: r.entryCount,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
      updatedAt: r.updatedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(r.updatedAt!),
    );
  }

  List<String> _parseSourceEntryIds(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json);
      if (list is List) return list.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }
```

- [ ] **Step 8: 运行 analyze 确认全量编译**

Run: `flutter analyze lib/services/database/ lib/services/diary_storage_service.dart`
Expected: `No issues found!`。若报 `DailySummaryRow` 未定义，确认 Step 3 的 build_runner 在 Step 2 改完 tables 列表后重新跑过。

- [ ] **Step 9: 提交**

```bash
dart format lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/diary_storage_service.dart test/daily_summary_storage_test.dart
git add lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/database/app_database.g.dart lib/services/diary_storage_service.dart test/daily_summary_storage_test.dart
git commit -m "feat: 新增 DailySummaries 表与迁移、DB 查询、storage 读写（schemaVersion→8）"
```

---

## Task 4: DailySummaryService（LLM 聚合 + 超长降级 + API 日志）

> **分层决策**：`DailySummaryResult`（含 `LlmUsage`）放在 `llm_service.dart`（与 `LlmResult` 同源，是 LLM 返回值）。`DailySummaryService`（业务编排：读 transcript → 拼接 → 降级 → 调 LLM → 记日志）单向依赖 `LlmService` + `DiaryStorageService`，无循环。
>
> **职责边界**：`summarizeDay` 假设调用方已保证各篇 transcript 可读（前置检查在 Task 6 的 `DailySummaryProcessingTask`：当天若有 `processing` 篇则整体判 `failed`）。`summarizeDay` 内部对单篇 transcript 读失败做容错跳过。

**Files:**
- Modify: `lib/services/llm_service.dart`（新增 `DailySummaryResult` + `summarizeDayText` 纯 LLM 调用）
- Create: `lib/services/daily_summary_service.dart`
- Test: `test/daily_summary_service_test.dart`

- [ ] **Step 1: 在 llm_service.dart 新增 DailySummaryResult + summarizeDayText**

1a. 在 `LlmResult` 类定义之后（约第 70 行，`class LlmService {` 之前）新增 `DailySummaryResult` 类：

```dart
/// 每日总结的 LLM 返回（无 utterances，全天重组无单篇时间戳）。
class DailySummaryResult {
  final String title;
  final String summary;
  final String outline;
  final bool degraded;
  final LlmUsage? usage;

  const DailySummaryResult({
    required this.title,
    required this.summary,
    required this.outline,
    required this.degraded,
    this.usage,
  });
}
```

1b. 在文件顶部的 import 之后（约第 7 行）新增两个 prompt 常量：

```dart
/// 每日总结 system prompt（全文模式）。
const _kDaySummaryPrompt =
    '你是一个日记助手。用户会给你一天里多段语音识别的口语文本'
    '（按时间顺序，每段以 `### 第 N 段 · HH:mm` 分隔）。'
    '请把这一整天的全部内容写成一篇真正连贯的日记：\n'
    '\n'
    '1. **日记正文（summary）**：以第一人称「我」的视角，把一整天的经历、想法、感受'
    '串联成一篇流畅的 Markdown 日记，不要分条列举，500-1000字。\n'
    '2. **概览播报（outline）**：生成一段口语化播报文本，提炼这一天最重要的主题或事件，'
    '适合 TTS 朗读，不要使用列表格式。\n'
    '3. **标题（title）**：从内容中提炼简短标题，不超过20字。\n'
    '\n'
    '严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
    '{"title": "标题", "summary": "日记正文(Markdown)", "outline": "概览播报文本"}';

/// 每日总结 system prompt（降级模式：基于各篇 summary 聚合）。
const _kDaySummaryDegradedPrompt =
    '你是一个日记助手。由于当天内容过长，下面给你的是这一天各段语音的日记摘要'
    '（按时间顺序，每段以 `### 第 N 段 · HH:mm（标题）` 分隔）。'
    '请把它们融合成一篇连贯的全天日记：\n'
    '\n'
    '1. **日记正文（summary）**：以第一人称「我」的视角，融合各段摘要成一篇流畅的 Markdown 日记，500-1000字。\n'
    '2. **概览播报（outline）**：口语化全天概览，适合 TTS 朗读，不要使用列表格式。\n'
    '3. **标题（title）**：简短标题，不超过20字。\n'
    '\n'
    '严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
    '{"title": "标题", "summary": "日记正文(Markdown)", "outline": "概览播报文本"}';
```

1c. 在 `LlmService` 类内（`summarize` 方法之后，约第 163 行）新增 `summarizeDayText` 方法：

```dart
  /// 每日总结的纯 LLM 调用：根据 [degraded] 选用不同 system prompt。
  /// [text] 为已拼接好的全天文本（全文或降级 summary 聚合）。
  Future<DailySummaryResult> summarizeDayText(
    String text, {
    required bool degraded,
  }) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': degraded ? _kDaySummaryDegradedPrompt : _kDaySummaryPrompt,
          },
          {'role': 'user', 'content': text},
        ],
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    final content =
        response.data['choices'][0]['message']['content'] as String;
    final usageJson = response.data['usage'] as Map<String, dynamic>?;
    LlmUsage? usage;
    if (usageJson != null) {
      usage = LlmUsage(
        promptTokens: usageJson['prompt_tokens'] as int? ?? 0,
        completionTokens: usageJson['completion_tokens'] as int? ?? 0,
        totalTokens: usageJson['total_tokens'] as int? ?? 0,
        cachedTokens:
            (usageJson['prompt_tokens_details'] as Map<String, dynamic>?)
                ?['cached_tokens'] as int?,
        reasoningTokens:
            (usageJson['completion_tokens_details'] as Map<String, dynamic>?)
                ?['reasoning_tokens'] as int?,
      );
    }

    // 复用单篇容错解析（utterances 对 daily 无意义，忽略）
    final parsed = _parseResult(content);
    return DailySummaryResult(
      title: parsed.title,
      summary: parsed.summary,
      outline: parsed.outline,
      degraded: degraded,
      usage: usage,
    );
  }
```

- [ ] **Step 2: 写失败测试（mock LlmService + DiaryStorageService + ApiLogService）**

创建 `test/daily_summary_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/exceptions.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/utterance.dart';
import 'package:voice_diary/services/api_log_service.dart';
import 'package:voice_diary/services/daily_summary_service.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/llm_service.dart';

class _MockStorage extends Mock implements DiaryStorageService {}

class _MockLlm extends Mock implements LlmService {}

class _MockApiLog extends Mock implements ApiLogService {}

DiaryEntry _entry({
  required String id,
  required DateTime createdAt,
  String folder = '/x',
}) {
  return DiaryEntry(
    id: id,
    title: 't',
    folderPath: folder,
    durationSeconds: 0,
    createdAt: createdAt,
  );
}

void main() {
  late _MockStorage storage;
  late _MockLlm llm;
  late _MockApiLog apiLog;
  late DailySummaryService service;

  setUp(() {
    storage = _MockStorage();
    llm = _MockLlm();
    apiLog = _MockApiLog();
    service = DailySummaryService(
      storage: storage,
      llm: llm,
      apiLog: apiLog,
    );
    // logApiCall 默认 no-op
    when(
      () => apiLog.logApiCall(
        diaryId: any(named: 'diaryId'),
        apiType: any(named: 'apiType'),
        step: any(named: 'step'),
        status: any(named: 'status'),
        durationMs: any(named: 'durationMs'),
        errorMessage: any(named: 'errorMessage'),
        responseSummary: any(named: 'responseSummary'),
        promptTokens: any(named: 'promptTokens'),
        completionTokens: any(named: 'completionTokens'),
        totalTokens: any(named: 'totalTokens'),
        cachedTokens: any(named: 'cachedTokens'),
        reasoningTokens: any(named: 'reasoningTokens'),
      ),
    ).thenAnswer((_) async {});
  });

  test('正常模式：拼接各篇全文（按时间排序），degraded=false', () async {
    final e1 = _entry(id: 'e1', createdAt: DateTime(2026, 6, 13, 9));
    final e2 = _entry(id: 'e2', createdAt: DateTime(2026, 6, 13, 14));
    when(() => storage.readTranscriptJson(any())).thenAnswer(
      (_) async => TranscriptData(
        version: 1,
        utterances: [Utterance(text: '内容', startTime: 0, endTime: 1)],
      ),
    );
    when(
      () => llm.summarizeDayText(any(), degraded: any(named: 'degraded')),
    ).thenAnswer(
      (_) async => const DailySummaryResult(
        title: '标题',
        summary: '正文',
        outline: '播报',
        degraded: false,
      ),
    );

    final result = await service.summarizeDay([e2, e1]); // 故意倒序验证排序

    expect(result.title, '标题');
    expect(result.degraded, isFalse);
    final captured = verify(
      () => llm.summarizeDayText(
        captureAny(),
        degraded: captureAny(named: 'degraded'),
      ),
    ).captured;
    expect(captured[0], contains('### 第 1 段 · 09:00')); // e1 排序后在前
    expect(captured[0], contains('### 第 2 段 · 14:00'));
    expect(captured[1], isFalse);
  });

  test('降级模式：全文超阈值改用各篇 summary 聚合，degraded=true', () async {
    final e1 = _entry(id: 'e1', createdAt: DateTime(2026, 6, 13, 9));
    when(() => storage.readTranscriptJson(any())).thenAnswer(
      (_) async => TranscriptData(
        version: 1,
        utterances: [Utterance(text: 'x' * 30000, startTime: 0, endTime: 1)],
      ),
    );
    when(() => storage.readLlmResult(any())).thenAnswer(
      (_) async => LlmResultData(
        version: 1,
        title: '早晨',
        summary: '晨跑内容',
        outline: '',
        utterances: const [],
      ),
    );
    when(
      () => llm.summarizeDayText(any(), degraded: any(named: 'degraded')),
    ).thenAnswer(
      (_) async => const DailySummaryResult(
        title: 't',
        summary: 's',
        outline: 'o',
        degraded: true,
      ),
    );

    final result = await service.summarizeDay([e1]);

    expect(result.degraded, isTrue);
    final captured = verify(
      () => llm.summarizeDayText(
        captureAny(),
        degraded: captureAny(named: 'degraded'),
      ),
    ).captured;
    expect(captured[1], isTrue);
    expect(captured[0], contains('晨跑内容')); // 用了 summary 而非全文
  });

  test('LLM 失败时抛 DailySummaryException', () async {
    final e1 = _entry(id: 'e1', createdAt: DateTime(2026, 6, 13, 9));
    when(() => storage.readTranscriptJson(any())).thenAnswer(
      (_) async => TranscriptData(
        version: 1,
        utterances: [Utterance(text: 'a', startTime: 0, endTime: 1)],
      ),
    );
    when(
      () => llm.summarizeDayText(any(), degraded: any(named: 'degraded')),
    ).thenThrow(Exception('网络错误'));

    expect(
      () => service.summarizeDay([e1]),
      throwsA(isA<DailySummaryException>()),
    );
  });
}
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `flutter test test/daily_summary_service_test.dart`
Expected: FAIL，报 `DailySummaryService` 未定义。

- [ ] **Step 4: 实现 lib/services/daily_summary_service.dart**

创建 `lib/services/daily_summary_service.dart`：

```dart
import '../exceptions.dart';
import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import 'api_log_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';

/// 每日总结生成服务：读各篇 transcript → 拼接 → 超长降级 → 调 LLM → 记 API 日志。
class DailySummaryService {
  final DiaryStorageService _storage;
  final LlmService _llm;
  final ApiLogService _apiLog;

  DailySummaryService({
    DiaryStorageService? storage,
    LlmService? llm,
    ApiLogService? apiLog,
  })  : _storage = storage ?? DiaryStorageService(),
        _llm = llm ?? LlmService(),
        _apiLog = apiLog ?? ApiLogService();

  /// 把一天各篇录音重组为一篇总结。
  ///
  /// [entries] 无序传入也会内部按 createdAt 升序。
  /// 前置条件：各篇 transcript.json 应已存在（由调用方 DailySummaryProcessingTask
  /// 检查当天无 processing 篇后再调用）；单篇读失败则容错跳过。
  Future<DailySummaryResult> summarizeDay(List<DiaryEntry> entries) async {
    final sorted = [...entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final diaryIdForLog = sorted.isEmpty ? 'daily' : sorted.first.id;

    final sw = Stopwatch()..start();
    try {
      // 1) 读各篇 transcript 全文
      final fullSegments = <DayFullTextSegment>[];
      for (final e in sorted) {
        try {
          final transcript = await _storage.readTranscriptJson(e.folderPath);
          final text = transcript.fullText;
          if (text.isNotEmpty) {
            fullSegments.add((createdAt: e.createdAt, text: text));
          }
        } catch (_) {
          // 单篇 transcript 读失败跳过，不整盘失败
        }
      }

      // 2) 拼接 + 超长降级判断
      String combined = buildDayFullText(fullSegments);
      var degraded = shouldDegrade(combined);

      // 3) 降级：退回各篇 summary 聚合
      if (degraded) {
        final summarySegments = <DaySummarySegment>[];
        for (final e in sorted) {
          try {
            final llmData = await _storage.readLlmResult(e.folderPath);
            summarySegments.add((
              createdAt: e.createdAt,
              title: llmData.title,
              summary: llmData.summary,
            ));
          } catch (_) {}
        }
        combined = buildDaySummariesText(summarySegments);
      }

      // 4) 调 LLM
      final result = await _llm.summarizeDayText(combined, degraded: degraded);

      sw.stop();
      await _apiLog.logApiCall(
        diaryId: diaryIdForLog,
        apiType: 'llm_daily_summary',
        step: 'daily_summary',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        promptTokens: result.usage?.promptTokens,
        completionTokens: result.usage?.completionTokens,
        totalTokens: result.usage?.totalTokens,
        cachedTokens: result.usage?.cachedTokens,
        reasoningTokens: result.usage?.reasoningTokens,
        responseSummary: degraded ? '降级：基于各篇摘要聚合' : null,
      );
      return result;
    } catch (e) {
      sw.stop();
      await _apiLog.logApiCall(
        diaryId: diaryIdForLog,
        apiType: 'llm_daily_summary',
        step: 'daily_summary',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      throw DailySummaryException('每日总结生成失败: $e');
    }
  }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `flutter test test/daily_summary_service_test.dart`
Expected: PASS（3 个测试全过）。

- [ ] **Step 6: analyze + 提交**

Run: `flutter analyze lib/services/llm_service.dart lib/services/daily_summary_service.dart`
Expected: `No issues found!`

```bash
dart format lib/services/llm_service.dart lib/services/daily_summary_service.dart test/daily_summary_service_test.dart
git add lib/services/llm_service.dart lib/services/daily_summary_service.dart test/daily_summary_service_test.dart
git commit -m "feat: 新增 DailySummaryService 与 LLM 每日总结聚合（含超长降级）"
```

---

## Task 5: 任务抽象（ProcessingTask 接口 + ProcessingContext + DiaryProcessingTask 提取）

> **失败处理决策（对 spec 6.2/6.3 的工程化调整）**：spec 说「DailySummaryTask 抛异常，调度器统一处理」。但两类 Task 的失败标记目标不同表（DiaryEntries vs DailySummaries）、通知消息 type 也不同（`failed` vs `dailySummaryFailed`），统一到调度器反而要分支判断。**决策**：每个 Task 在 `execute` 内部完整处理自己的失败（标记 `status=failed` + `sendToMain` 失败消息 + `logStep`），不向上抛；调度器只负责顺序执行 + 防御性 try/catch（防止一个 Task 的未捕获异常中断其他 Task）。错误隔离由此自然达成。

**Files:**
- Create: `lib/services/processing_task.dart`（接口 + Context）
- Create: `lib/services/diary_processing_task.dart`（提取自 recording_processor.dart）
- Test: `test/processing_task_test.dart`

- [ ] **Step 1: 写失败测试（契约 + completed 路径）**

创建 `test/processing_task_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/processing_stage.dart';
import 'package:voice_diary/services/diary_processing_task.dart';
import 'package:voice_diary/services/processing_task.dart';

DiaryEntry _entry({
  String id = 'e1',
  ProcessingStage stage = ProcessingStage.completed,
  String title = '',
}) {
  return DiaryEntry(
    id: id,
    title: title,
    folderPath: '/x',
    durationSeconds: 0,
    createdAt: DateTime(2026, 6, 13),
    status: EntryStatus.processing,
    processingStage: stage,
  );
}

void main() {
  // DiaryProcessingTask 是从原 ProcessingTaskHandler 提取的纯搬运（行为完全不变）。
  // 其 execute 内部调用 FlutterForegroundTask（platform 插件），单测环境无法驱动，
  // 故这里只验证 Task 契约；execute 行为由 Task 10 手动集成验证覆盖
  // （与 spec §11「测调度而非提取全链路」一致）。
  test('DiaryProcessingTask 实现 ProcessingTask 契约', () {
    final task = DiaryProcessingTask(_entry());
    expect(task, isA<ProcessingTask>());
    expect(task.taskType, 'diary');
    expect(task.id, 'e1');
    expect(task.notificationText, isNotEmpty);
  });

  test('notificationText 基于 displayTitle', () {
    final task = DiaryProcessingTask(
      DiaryEntry(
        id: 'e2',
        title: '今天很开心',
        folderPath: '/x',
        durationSeconds: 0,
        createdAt: DateTime(2026, 6, 13),
      ),
    );
    expect(task.notificationText, contains('今天很开心'));
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/processing_task_test.dart`
Expected: FAIL，报 `ProcessingTask` / `ProcessingContext` / `DiaryProcessingTask` 未定义。

- [ ] **Step 3: 实现 lib/services/processing_task.dart（接口 + Context）**

创建 `lib/services/processing_task.dart`：

```dart
import 'api_log_service.dart';
import 'asr_service.dart';
import 'daily_summary_service.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'tos_upload_service.dart';

/// 处理任务的统一抽象。录音处理与每日总结各封装为一个 Task，
/// 由 ProcessingTaskHandler 调度器统一拉起、顺序执行、错误隔离。
abstract class ProcessingTask {
  /// 任务标识：录音为 entryId，每日总结为日期 'yyyy-MM-dd'。
  String get id;

  /// 任务类型：'diary' | 'daily_summary'。
  String get taskType;

  /// FGS 通知文案。
  String get notificationText;

  /// 执行任务。失败时由 Task 自行标记 status=failed + 通知主 isolate，
  /// 不向上抛（保证调度器错误隔离）。
  Future<void> execute(ProcessingContext ctx);
}

/// Task 执行时共享的依赖容器，避免每个 Task 各自 new service。
class ProcessingContext {
  final DiaryStorageService storage;
  final LlmService llm;
  final AsrService asr;
  final TosUploadService tos;
  final ApiLogService apiLog;
  final DailySummaryService dailySummary;

  /// 向主 isolate 发送消息（封装 FlutterForegroundTask.sendDataToMain）。
  final void Function(Map<String, dynamic>) sendToMain;

  const ProcessingContext({
    required this.storage,
    required this.llm,
    required this.asr,
    required this.tos,
    required this.apiLog,
    required this.dailySummary,
    required this.sendToMain,
  });
}
```

- [ ] **Step 4: 实现 lib/services/diary_processing_task.dart（从 recording_processor.dart 提取，行为不变）**

创建 `lib/services/diary_processing_task.dart`：

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../exceptions.dart';
import '../models/diary_entry.dart';
import '../models/processing_stage.dart';
import '../models/utterance.dart';
import 'asr_service.dart';
import 'llm_service.dart';
import 'processing_task.dart';
import 'tos_upload_service.dart';

/// 录音处理任务：把单篇录音走完 上传→ASR→LLM→标签→完成 流程。
///
/// 从原 ProcessingTaskHandler 的 _processEntry / _doUpload / _doAsr / _doLlm /
/// _doTagging / _doComplete / _handleEmptyAsr / _markFailed 提取，行为完全不变，
/// 仅改为通过 ProcessingContext 访问依赖。失败时自行标记 entry failed + 通知，
/// 不向上抛。
class DiaryProcessingTask implements ProcessingTask {
  final DiaryEntry entry;

  DiaryProcessingTask(this.entry);

  @override
  String get id => entry.id;

  @override
  String get taskType => 'diary';

  @override
  String get notificationText => '语音日记 - ${entry.displayTitle}';

  @override
  Future<void> execute(ProcessingContext ctx) async {
    debugPrint(
      '[DiaryTask] 开始处理: ${entry.id}, stage=${entry.processingStage.value}',
    );
    await ctx.apiLog.logStep(
      diaryId: entry.id,
      step: 'processing',
      status: 'started',
      message: '从 ${entry.processingStage.value} 阶段恢复',
    );
    try {
      await _processEntry(ctx);
      await ctx.apiLog.logStep(
        diaryId: entry.id,
        step: 'processing',
        status: 'success',
      );
    } catch (e) {
      debugPrint('[DiaryTask] 处理异常 (${entry.id}): $e');
      await ctx.apiLog.logStep(
        diaryId: entry.id,
        step: 'processing',
        status: 'error',
        message: e.toString(),
      );
      await _markFailed(ctx, '处理失败');
    }
  }

  Future<void> _processEntry(ProcessingContext ctx) async {
    switch (entry.processingStage) {
      case ProcessingStage.uploading:
        await _doUpload(ctx);
        // ASR 结果为空则直接完成，跳过 LLM/tagging
        if (await _doAsr(ctx)) break;
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.asr:
        // TOS 已上传（tosKey 存在），直接 ASR
        if (await _doAsr(ctx)) break;
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.llm:
        // ASR 已完成，transcript.json 已存在
        await _doLlm(ctx);
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.tagging:
        // LLM 已完成，llm_result.json 已存在
        await _doTagging(ctx);
        await _doComplete(ctx);

      case ProcessingStage.completed:
        // 已完成，跳过
        await _doComplete(ctx);
    }
  }

  /// 阶段: 上传音频到 TOS
  Future<void> _doUpload(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 上传音频...',
    );

    // 查找音频文件
    String? audioFilePath;
    for (final name in ['audio.ogg', 'audio.wav']) {
      final f = File('${entry.folderPath}/$name');
      if (await f.exists()) {
        audioFilePath = f.path;
        break;
      }
    }
    if (audioFilePath == null) {
      throw ProcessingException('音频文件不存在: ${entry.folderPath}');
    }

    final tosKey = await ctx.tos.uploadAudio(audioFilePath, entry.id);
    await ctx.storage.updateTosKeyAndStage(
      entry.id,
      tosKey,
      ProcessingStage.asr,
    );
    ctx.sendToMain({'type': 'stageUpdate', 'entryId': entry.id, 'stage': 'asr'});
    debugPrint('[DiaryTask] 上传完成: $tosKey');
  }

  /// 阶段: ASR 识别（异步 submit + query）。
  /// 返回 true 表示识别结果为空（已标记完成，调用方应跳过后续 LLM 阶段）。
  Future<bool> _doAsr(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 语音识别...',
    );

    await ctx.apiLog.logStep(
      diaryId: entry.id,
      step: 'asr',
      status: 'started',
    );

    final sw = Stopwatch()..start();
    try {
      final tosKey = await ctx.storage.getTosKey(entry.id);
      if (tosKey == null) {
        throw const ProcessingException('tosKey 为空，无法进行 ASR');
      }

      final presignedUrl = await ctx.tos.getPresignedUrl(tosKey);

      AsrResult asrResult;
      if (entry.asrTaskId != null) {
        debugPrint('[DiaryTask] 恢复 ASR 查询: ${entry.asrTaskId}');
        try {
          asrResult = await ctx.asr.pollAsyncResult(entry.asrTaskId!);
        } catch (e) {
          debugPrint('[DiaryTask] ASR 查询失败，重新提交: $e');
          final newTaskId = await ctx.asr.submitAsync(presignedUrl);
          await ctx.storage.updateAsrTaskIdAndStage(
            entry.id,
            newTaskId,
            ProcessingStage.asr,
          );
          asrResult = await ctx.asr.pollAsyncResult(newTaskId);
        }
      } else {
        final asrTaskId = await ctx.asr.submitAsync(presignedUrl);
        await ctx.storage.updateAsrTaskIdAndStage(
          entry.id,
          asrTaskId,
          ProcessingStage.asr,
        );
        asrResult = await ctx.asr.pollAsyncResult(asrTaskId);
      }

      await ctx.storage.writeTranscriptJson(
        entry.folderPath,
        TranscriptData(version: 1, utterances: asrResult.utterances),
      );

      // 识别结果为空：写入占位结果并标记完成，不进入 LLM，也不能重试
      if (asrResult.utterances.isEmpty) {
        sw.stop();
        return _handleEmptyAsr(ctx, sw.elapsedMilliseconds);
      }

      await ctx.storage.updateProcessingStage(entry.id, ProcessingStage.llm);

      sw.stop();
      ctx.sendToMain({
        'type': 'stageUpdate',
        'entryId': entry.id,
        'stage': 'llm',
      });
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'asr_async',
        step: 'asr',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        audioDurationSeconds: entry.durationSeconds,
      );
      debugPrint('[DiaryTask] ASR 完成');
      return false;
    } catch (e) {
      sw.stop();
      // 真正的错误：记录并抛出
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'asr_async',
        step: 'asr',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
        audioDurationSeconds: entry.durationSeconds,
      );
      rethrow;
    }
  }

  /// ASR 识别结果为空时的统一处理：写空 transcript + 占位 LLM 结果，标记完成。
  /// 返回 true 表示已完成，调用方应跳过后续 LLM 阶段。
  Future<bool> _handleEmptyAsr(ProcessingContext ctx, int durationMs) async {
    debugPrint('[DiaryTask] ASR 识别结果为空，标记完成');
    await ctx.storage.writeTranscriptJson(
      entry.folderPath,
      TranscriptData(version: 1, utterances: []),
    );
    await ctx.storage.writeLlmResult(
      entry.folderPath,
      LlmResultData(
        version: 1,
        title: '未识别到语音内容',
        summary: '本次录音未识别到语音内容，可能录音过短或无声。',
        outline: '',
        utterances: [],
      ),
    );
    await ctx.apiLog.logApiCall(
      diaryId: entry.id,
      apiType: 'asr_async',
      step: 'asr',
      status: 'success',
      durationMs: durationMs,
      audioDurationSeconds: entry.durationSeconds,
      responseSummary: '识别结果为空，跳过 LLM 直接完成',
    );
    await _doComplete(ctx);
    return true;
  }

  /// 阶段: LLM 润色汇总
  Future<void> _doLlm(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - AI 总结...',
    );

    await ctx.apiLog.logStep(diaryId: entry.id, step: 'llm', status: 'started');

    final sw = Stopwatch()..start();
    try {
      final transcript = await ctx.storage.readTranscriptJson(
        entry.folderPath,
      );
      final llmResult = await ctx.llm.summarize(transcript.utterances);

      await ctx.storage.writeLlmResult(
        entry.folderPath,
        LlmResultData(
          version: 1,
          title: llmResult.title,
          summary: llmResult.summary,
          outline: llmResult.outline,
          utterances: llmResult.utterances,
        ),
      );
      await ctx.storage.updateProcessingStage(
        entry.id,
        ProcessingStage.tagging,
      );

      sw.stop();
      ctx.sendToMain({
        'type': 'stageUpdate',
        'entryId': entry.id,
        'stage': 'tagging',
        'title': llmResult.title,
      });
      final usage = llmResult.usage;
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_summarize',
        step: 'llm',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
        promptTokens: usage?.promptTokens,
        completionTokens: usage?.completionTokens,
        totalTokens: usage?.totalTokens,
        cachedTokens: usage?.cachedTokens,
        reasoningTokens: usage?.reasoningTokens,
      );
      debugPrint('[DiaryTask] LLM 完成');
    } catch (e) {
      sw.stop();
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_summarize',
        step: 'llm',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// 阶段: 标签归类（失败不阻塞）
  Future<void> _doTagging(ProcessingContext ctx) async {
    FlutterForegroundTask.updateService(
      notificationTitle: '正在处理',
      notificationText: '语音日记 - 自动归类...',
    );

    final sw = Stopwatch()..start();
    try {
      final llmResult = await ctx.storage.readLlmResult(entry.folderPath);
      final allTags = await ctx.storage.getAllTags();
      final tagsWithPrompt =
          allTags.where((t) => t.matchPrompt.isNotEmpty).toList();
      if (tagsWithPrompt.isNotEmpty) {
        final tagInfos = tagsWithPrompt
            .map(
              (t) => TagInfo(id: t.id, name: t.name, matchPrompt: t.matchPrompt),
            )
            .toList();
        final matchedTagIds = await ctx.llm.matchTags(
          llmResult.summary,
          tagInfos,
        );
        if (matchedTagIds.isNotEmpty) {
          await ctx.storage.autoTagDiary(entry.id, matchedTagIds);
        }
      }

      sw.stop();
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'success',
        durationMs: sw.elapsedMilliseconds,
      );
      debugPrint('[DiaryTask] 标签归类完成');
    } catch (e) {
      sw.stop();
      await ctx.apiLog.logApiCall(
        diaryId: entry.id,
        apiType: 'llm_match_tags',
        step: 'tagging',
        status: 'error',
        durationMs: sw.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
      // 标签归类失败不阻塞，不 rethrow
      debugPrint('[DiaryTask] 自动归类失败（不阻塞）: $e');
    }
  }

  /// 阶段: 完成
  Future<void> _doComplete(ProcessingContext ctx) async {
    // 读取 LLM 结果获取标题
    String title = entry.displayTitle;
    try {
      final llmResult = await ctx.storage.readLlmResult(entry.folderPath);
      title = llmResult.title;
    } catch (_) {}

    await ctx.storage.updateEntry(
      DiaryEntry(
        id: entry.id,
        title: title,
        folderPath: entry.folderPath,
        durationSeconds: entry.durationSeconds,
        createdAt: entry.createdAt,
        tosKey: entry.tosKey,
        audioFormat: entry.audioFormat,
        uploadedAt: DateTime.now(),
        weatherIcon: entry.weatherIcon,
        weatherText: entry.weatherText,
        temperature: entry.temperature,
        locationName: entry.locationName,
        locationLat: entry.locationLat,
        locationLon: entry.locationLon,
        status: EntryStatus.completed,
        processingStage: ProcessingStage.completed,
      ),
    );

    FlutterForegroundTask.updateService(
      notificationTitle: '处理完成',
      notificationText: '语音日记 - $title',
    );

    ctx.sendToMain({'type': 'completed', 'entryId': entry.id});
    debugPrint('[DiaryTask] 处理完成: ${entry.id}');
  }

  Future<void> _markFailed(ProcessingContext ctx, String title) async {
    try {
      await ctx.storage.updateEntryTitleAndStatus(
        entry.id,
        title,
        EntryStatus.failed,
      );
    } catch (e) {
      debugPrint('[DiaryTask] 标记 failed 失败: $e');
    }
    ctx.sendToMain({'type': 'failed', 'entryId': entry.id, 'step': 0, 'error': ''});
  }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `flutter test test/processing_task_test.dart`
Expected: PASS（2 个测试全过）。

- [ ] **Step 6: analyze + 提交**

Run: `flutter analyze lib/services/processing_task.dart lib/services/diary_processing_task.dart`
Expected: `No issues found!`

```bash
dart format lib/services/processing_task.dart lib/services/diary_processing_task.dart test/processing_task_test.dart
git add lib/services/processing_task.dart lib/services/diary_processing_task.dart test/processing_task_test.dart
git commit -m "refactor: 提取 ProcessingTask 接口与 DiaryProcessingTask（行为不变）"
```

---

## Task 6: DailySummaryProcessingTask + 调度器改造

实现每日总结任务，并把 `ProcessingTaskHandler.onStart` 改造为调度两类 Task 的调度器（录音在前、总结在后）。

**Files:**
- Create: `lib/services/daily_summary_processing_task.dart`
- Modify: `lib/services/recording_processor.dart`（精简为调度器）
- Test: `test/daily_summary_processing_task_test.dart`

- [ ] **Step 1: 写失败测试（4 个分支）**

创建 `test/daily_summary_processing_task_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/exceptions.dart';
import 'package:voice_diary/models/daily_summary.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/services/api_log_service.dart';
import 'package:voice_diary/services/asr_service.dart';
import 'package:voice_diary/services/daily_summary_processing_task.dart';
import 'package:voice_diary/services/daily_summary_service.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/llm_service.dart';
import 'package:voice_diary/services/processing_task.dart';
import 'package:voice_diary/services/tos_upload_service.dart';

class _MockStorage extends Mock implements DiaryStorageService {}

class _MockDailySummary extends Mock implements DailySummaryService {}

class _MockLlm extends Mock implements LlmService {}

class _MockAsr extends Mock implements AsrService {}

class _MockTos extends Mock implements TosUploadService {}

class _MockApiLog extends Mock implements ApiLogService {}

DiaryEntry _entry({EntryStatus status = EntryStatus.completed}) {
  return DiaryEntry(
    id: 'e1',
    title: 't',
    folderPath: '/x',
    durationSeconds: 0,
    createdAt: DateTime(2026, 6, 13),
    status: status,
  );
}

ProcessingContext _ctx({
  required _MockStorage storage,
  required _MockDailySummary dailySummary,
  required List<Map<String, dynamic>> sent,
}) {
  return ProcessingContext(
    storage: storage,
    llm: _MockLlm(),
    asr: _MockAsr(),
    tos: _MockTos(),
    apiLog: _MockApiLog(),
    dailySummary: dailySummary,
    sendToMain: sent.add,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      DailySummary(
        date: 'fb',
        title: '',
        status: EntryStatus.completed,
        sourceEntryIds: const [],
        entryCount: 0,
        createdAt: DateTime(2026, 6, 13),
      ),
    );
    registerFallbackValue(
      const DailySummaryData(
        version: 1,
        date: 'fb',
        title: '',
        summary: '',
        outline: '',
        sourceEntryIds: [],
        degraded: false,
      ),
    );
    registerFallbackValue(<DiaryEntry>[]);
  });

  test('0 篇 → 标记 completed 空总结，通知 dailySummaryCompleted', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => const []);
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(
      () => storage.writeDailySummaryJson(any(), any()),
    ).thenAnswer((_) async {});
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask('2026-06-13').execute(
      _ctx(storage: storage, dailySummary: dailySummary, sent: sent),
    );

    verify(() => storage.writeDailySummaryJson('2026-06-13', any())).called(1);
    verify(() => storage.saveDailySummary(any())).called(1);
    verifyNever(() => dailySummary.summarizeDay(any()));
    expect(sent.any((m) => m['type'] == 'dailySummaryCompleted'), isTrue);
  });

  test('当天有 processing 篇 → 标记 failed，不调 summarizeDay', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    when(() => storage.getEntriesByDate(any())).thenAnswer(
      (_) async => [_entry(status: EntryStatus.processing)],
    );
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask('2026-06-13').execute(
      _ctx(storage: storage, dailySummary: dailySummary, sent: sent),
    );

    verifyNever(() => dailySummary.summarizeDay(any()));
    verifyNever(() => storage.writeDailySummaryJson(any(), any()));
    expect(sent.any((m) => m['type'] == 'dailySummaryFailed'), isTrue);
  });

  test('正常 → summarizeDay + 写文件 + completed', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => [_entry()]);
    when(() => dailySummary.summarizeDay(any())).thenAnswer(
      (_) async => const DailySummaryResult(
        title: 't',
        summary: 's',
        outline: 'o',
        degraded: false,
      ),
    );
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(
      () => storage.writeDailySummaryJson(any(), any()),
    ).thenAnswer((_) async {});
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask('2026-06-13').execute(
      _ctx(storage: storage, dailySummary: dailySummary, sent: sent),
    );

    verify(() => dailySummary.summarizeDay(any())).called(1);
    verify(() => storage.writeDailySummaryJson('2026-06-13', any())).called(1);
    expect(sent.any((m) => m['type'] == 'dailySummaryCompleted'), isTrue);
  });

  test('summarizeDay 失败 → 标记 failed + dailySummaryFailed', () async {
    final storage = _MockStorage();
    final dailySummary = _MockDailySummary();
    final sent = <Map<String, dynamic>>[];
    when(
      () => storage.getEntriesByDate(any()),
    ).thenAnswer((_) async => [_entry()]);
    when(() => dailySummary.summarizeDay(any())).thenThrow(
      const DailySummaryException('聚合失败'),
    );
    when(() => storage.getDailySummary(any())).thenAnswer((_) async => null);
    when(() => storage.saveDailySummary(any())).thenAnswer((_) async {});

    await DailySummaryProcessingTask('2026-06-13').execute(
      _ctx(storage: storage, dailySummary: dailySummary, sent: sent),
    );

    verifyNever(() => storage.writeDailySummaryJson(any(), any()));
    expect(sent.any((m) => m['type'] == 'dailySummaryFailed'), isTrue);
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/daily_summary_processing_task_test.dart`
Expected: FAIL，报 `DailySummaryProcessingTask` 未定义。

- [ ] **Step 3: 实现 lib/services/daily_summary_processing_task.dart**

创建 `lib/services/daily_summary_processing_task.dart`：

```dart
import 'package:flutter/foundation.dart';

import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import 'processing_task.dart';

/// 每日总结处理任务：把指定日期当天所有录音的 ASR 全文重组为一篇总结。
///
/// 流程：查当天 entries → 0 篇空完成 / 有 processing 篇判 failed / 否则
/// summarizeDay 聚合 → 写正文文件 + 更新元数据。失败时标记 status=failed +
/// 通知，不向上抛。
class DailySummaryProcessingTask implements ProcessingTask {
  final String date;

  DailySummaryProcessingTask(this.date);

  @override
  String get id => date;

  @override
  String get taskType => 'daily_summary';

  @override
  String get notificationText => '生成每日总结（$date）';

  @override
  Future<void> execute(ProcessingContext ctx) async {
    debugPrint('[DailySummaryTask] 开始处理: $date');
    final entries = await ctx.storage.getEntriesByDate(date);
    final sourceEntryIds = entries.map((e) => e.id).toList();

    // 0 篇：空总结标记完成
    if (entries.isEmpty) {
      await _saveCompleted(
        ctx,
        title: '今天没有录音',
        summary: '',
        outline: '',
        sourceEntryIds: const [],
        entryCount: 0,
        degraded: false,
      );
      ctx.sendToMain({'type': 'dailySummaryCompleted', 'date': date});
      return;
    }

    // 前置：当天有 recording 尚未处理完成 → 判 failed（明确失败优于静默跳过）
    final hasProcessing =
        entries.any((e) => e.status == EntryStatus.processing);
    if (hasProcessing) {
      await _markFailed(ctx, '当天有录音尚未处理完成');
      return;
    }

    // 调 LLM 聚合（通知文案由调度器循环统一管理，task 内不再调 updateService）
    try {
      ctx.sendToMain({
        'type': 'dailySummaryStage',
        'date': date,
        'stage': 'llm',
      });
      final result = await ctx.dailySummary.summarizeDay(entries);
      await _saveCompleted(
        ctx,
        title: result.title,
        summary: result.summary,
        outline: result.outline,
        sourceEntryIds: sourceEntryIds,
        entryCount: entries.length,
        degraded: result.degraded,
      );
      ctx.sendToMain({'type': 'dailySummaryCompleted', 'date': date});
    } catch (e) {
      await _markFailed(ctx, e.toString());
    }
  }

  Future<void> _saveCompleted(
    ProcessingContext ctx, {
    required String title,
    required String summary,
    required String outline,
    required List<String> sourceEntryIds,
    required int entryCount,
    required bool degraded,
  }) async {
    await ctx.storage.writeDailySummaryJson(
      date,
      DailySummaryData(
        version: 1,
        date: date,
        title: title,
        summary: summary,
        outline: outline,
        sourceEntryIds: sourceEntryIds,
        degraded: degraded,
      ),
    );
    final existing = await ctx.storage.getDailySummary(date);
    await ctx.storage.saveDailySummary(
      DailySummary(
        date: date,
        title: title,
        status: EntryStatus.completed,
        sourceEntryIds: sourceEntryIds,
        entryCount: entryCount,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _markFailed(ProcessingContext ctx, String error) async {
    debugPrint('[DailySummaryTask] 失败 ($date): $error');
    final existing = await ctx.storage.getDailySummary(date);
    await ctx.storage.saveDailySummary(
      DailySummary(
        date: date,
        title: existing?.title ?? '生成失败',
        status: EntryStatus.failed,
        sourceEntryIds: existing?.sourceEntryIds ?? const [],
        entryCount: existing?.entryCount ?? 0,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    ctx.sendToMain({
      'type': 'dailySummaryFailed',
      'date': date,
      'error': error,
    });
  }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/daily_summary_processing_task_test.dart`
Expected: PASS（4 个测试全过）。

- [ ] **Step 5: 改造 recording_processor.dart 为调度器**

用以下完整内容**替换**整个 `lib/services/recording_processor.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'api_log_service.dart';
import 'asr_service.dart';
import 'daily_summary_processing_task.dart';
import 'daily_summary_service.dart';
import 'diary_processing_task.dart';
import 'diary_storage_service.dart';
import 'llm_service.dart';
import 'processing_task.dart';
import 'tos_upload_service.dart';

/// Processing FGS 入口函数
@pragma('vm:entry-point')
void processingCallback() {
  FlutterForegroundTask.setTaskHandler(ProcessingTaskHandler());
}

/// 处理阶段调度器，运行在 FGS isolate 中。
///
/// 查询录音（DiaryEntries status=processing）+ 每日总结（DailySummaries
/// status=processing）两类 pending 任务，分别包成 DiaryProcessingTask /
/// DailySummaryProcessingTask，录音在前、总结在后，依次 execute；错误隔离。
/// 具体处理逻辑在各 Task 内部。
class ProcessingTaskHandler extends TaskHandler {
  void _sendToMain(Map<String, dynamic> data) {
    FlutterForegroundTask.sendDataToMain(data);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ProcessingHandler] onStart');

    try {
      await dotenv.load(fileName: '.env.local');
    } catch (e) {
      debugPrint('[ProcessingHandler] dotenv.load 失败: $e');
    }

    final storage = DiaryStorageService();
    final ctx = ProcessingContext(
      storage: storage,
      llm: LlmService(),
      asr: AsrService(),
      tos: TosUploadService(),
      apiLog: ApiLogService(),
      dailySummary: DailySummaryService(),
      sendToMain: _sendToMain,
    );

    // 录音任务在前、每日总结在后（总结依赖当天录音已处理完成）
    final entries = await storage.getPendingEntries();
    final summaries = await storage.getPendingDailySummaries();
    final tasks = <ProcessingTask>[
      ...entries.map(DiaryProcessingTask.new),
      ...summaries.map((s) => DailySummaryProcessingTask(s.date)),
    ];

    if (tasks.isEmpty) {
      debugPrint('[ProcessingHandler] 无待处理任务，停止');
      _sendToMain({'type': 'processingDone'});
      await _stopService();
      return;
    }

    debugPrint('[ProcessingHandler] 待处理任务: ${tasks.length} 个');
    for (final task in tasks) {
      FlutterForegroundTask.updateService(
        notificationTitle: '正在处理',
        notificationText: task.notificationText,
      );
      try {
        await task.execute(ctx);
      } catch (e) {
        // 防御性兜底：Task 应自管失败，这里防止一个 Task 的未捕获异常中断其他
        debugPrint('[ProcessingHandler] task ${task.id} 未捕获异常: $e');
      }
    }

    debugPrint('[ProcessingHandler] 全部处理完成');
    _sendToMain({'type': 'processingDone'});
    await _stopService();
  }

  Future<void> _stopService() async {
    await Future.delayed(const Duration(seconds: 2));
    FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
    _sendToMain({
      'type': 'notificationPressed',
      'state': 'processing',
      'entryId': '',
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ProcessingHandler] onDestroy, isTimeout=$isTimeout');
    // 通知主 isolate 服务已停止，避免用户等待时 UI 卡住
    _sendToMain({'type': 'processingDone'});
  }
}
```

- [ ] **Step 6: analyze + 运行全部测试，确认改造无回归**

Run: `flutter analyze lib/services/recording_processor.dart lib/services/daily_summary_processing_task.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全部既有测试 + 新测试通过（确认 DiaryProcessingTask 提取未破坏现有行为——此时旧 `_processEntry` 等已从 recording_processor.dart 移除，引用全部走 Task）。

- [ ] **Step 7: 提交**

```bash
dart format lib/services/daily_summary_processing_task.dart lib/services/recording_processor.dart test/daily_summary_processing_task_test.dart
git add lib/services/daily_summary_processing_task.dart lib/services/recording_processor.dart test/daily_summary_processing_task_test.dart
git commit -m "feat: 新增 DailySummaryProcessingTask，调度器改造为两类任务调度"
```

---

## Task 7: 启动钩子（main.dart `_runDailySummaryIfNeeded`）

每天首次打开 app 自动为「昨天」生成总结。把"目标日期决策"提取为 `@visibleForTesting` 纯函数，使核心分支可单测；FGS 启动 / SharedPreferences / storage 调用部分靠 Task 10 手动验证（平台依赖，自动化测试 ROI 低）。

**Files:**
- Modify: `lib/main.dart`（新增 import、`_runDailySummaryIfNeeded`、`dailySummaryTargetDate`、`dateKey`，`main()` 调用钩子）
- Test: `test/daily_summary_boot_hook_test.dart`

- [ ] **Step 1: 写失败测试（日期决策 + dateKey）**

创建 `test/daily_summary_boot_hook_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/main.dart';

void main() {
  group('dailySummaryTargetDate', () {
    test('今天未为昨天生成 → 返回昨天 key', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      expect(
        dailySummaryTargetDate(lastGenDate: null, now: now),
        '2026-06-13',
      );
    });

    test('今天已为昨天生成（last == 昨天）→ 返回 null', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      expect(
        dailySummaryTargetDate(lastGenDate: '2026-06-13', now: now),
        isNull,
      );
    });

    test('last 是更早日期（多天未打开）→ 仍只返回昨天，不回填更早', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      expect(
        dailySummaryTargetDate(lastGenDate: '2026-06-10', now: now),
        '2026-06-13',
      );
    });

    test('跨年/跨月正确', () {
      final now = DateTime(2026, 1, 2, 0, 5);
      expect(
        dailySummaryTargetDate(lastGenDate: null, now: now),
        '2026-01-01',
      );
    });
  });

  test('dateKey 零填充', () {
    expect(dateKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(dateKey(DateTime(2026, 6, 13)), '2026-06-13');
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/daily_summary_boot_hook_test.dart`
Expected: FAIL，报 `dailySummaryTargetDate` / `dateKey` 未定义。

- [ ] **Step 3: 改 main.dart — 加 import**

在 `lib/main.dart` 顶部 import 区，在现有 import 之后追加：

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'models/daily_summary.dart';
import 'models/diary_entry.dart';
import 'services/recording_processor.dart' show processingCallback;
```

- [ ] **Step 4: 改 main.dart — main() 调用钩子**

把 `main()` 中 `_runTosMigrationIfNeeded();` 那一行之后、`runApp(...)` 之前，新增一行：

```dart
  _runTosMigrationIfNeeded();
  _runDailySummaryIfNeeded();

  runApp(const VoiceDiaryApp());
```

- [ ] **Step 5: 改 main.dart — 新增 dateKey / dailySummaryTargetDate / _runDailySummaryIfNeeded**

在 `_runTosMigrationIfNeeded` 函数之后（约第 54 行）、`class VoiceDiaryApp` 之前，新增：

```dart
/// 日期 → 'yyyy-MM-dd'。
@visibleForTesting
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 计算需要生成总结的目标日期（昨天）；今天已为昨天生成过则返回 null。
/// 多天未打开也只补「昨天」一天（更早的历史由用户在 list 分组手动生成）。
@visibleForTesting
String? dailySummaryTargetDate({
  required String? lastGenDate,
  required DateTime now,
}) {
  final yesterday =
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
  final key = dateKey(yesterday);
  return lastGenDate == key ? null : key;
}

/// 异步执行：每天首次打开 app 时自动为「昨天」生成每日总结。
/// 仿 _runTosMigrationIfNeeded，fire-and-forget，不阻塞 UI。
Future<void> _runDailySummaryIfNeeded() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('last_daily_summary_gen_date');
    final target = dailySummaryTargetDate(
      lastGenDate: last,
      now: DateTime.now(),
    );
    if (target == null) return; // 今天已为昨天生成过

    final storage = DiaryStorageService();
    // 昨天有录音才生成
    final entries = await storage.getEntriesByDate(target);
    if (entries.isEmpty) {
      // 无录音也更新 gen date，避免每次启动重复查
      await prefs.setString('last_daily_summary_gen_date', target);
      return;
    }

    // 已有记录的处理：null→新建 pending；processing→重启 FGS 继续；
    // completed/failed→不自动重新生成，更新 gen date 跳过
    final existing = await storage.getDailySummary(target);
    if (existing == null) {
      await storage.saveDailySummary(
        DailySummary(
          date: target,
          title: '正在生成…',
          status: EntryStatus.processing,
          sourceEntryIds: const [],
          entryCount: 0,
          createdAt: DateTime.now(),
        ),
      );
    } else if (existing.status != EntryStatus.processing) {
      await prefs.setString('last_daily_summary_gen_date', target);
      return;
    }

    // 启动 processing FGS（若未运行）。复用现有 channel / processingCallback。
    if (!await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.initCommunicationPort();
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '正在处理',
        notificationText: '语音日记 - 处理中...',
        callback: processingCallback,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[DailySummary] 启动 FGS 失败: ${result.error}');
      }
    }

    await prefs.setString('last_daily_summary_gen_date', target);
  } catch (e) {
    debugPrint('[DailySummary] 启动钩子跳过: $e');
  }
}
```

- [ ] **Step 6: 运行测试，确认通过**

Run: `flutter test test/daily_summary_boot_hook_test.dart`
Expected: PASS（5 个测试全过）。

- [ ] **Step 7: analyze + 提交**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

```bash
dart format lib/main.dart test/daily_summary_boot_hook_test.dart
git add lib/main.dart test/daily_summary_boot_hook_test.dart
git commit -m "feat: 新增每天首次打开自动生成昨日每日总结的启动钩子"
```

---

## Task 8: DailySummary 详情页（天气聚合 + TTS + 状态横幅）

新建 `DailySummaryPage`：AppBar（日期 + 聚合天气 + 操作菜单）→ 聚合天气行 → 状态横幅 → 正文（Markdown）→ outline TTS 播报 → 当天录音列表。顺带提取 `ensureProcessingFgsRunning` helper 统一 FGS 启动逻辑。

> UI 布局无 widget 自动化测试（项目无 widget test 先例），靠 Task 10 手动验证；本任务的可测纯逻辑（`DayWeatherSummary.display`）走 TDD。

**Files:**
- Modify: `lib/models/daily_summary.dart`（DayWeatherSummary 加 `display` getter）
- Modify: `lib/services/recording_processor.dart`（加 `ensureProcessingFgsRunning` 顶层 helper）
- Create: `lib/pages/daily_summary_page.dart`
- Modify: `lib/main.dart`（启动钩子改用 helper，DRY）
- Test: `test/daily_summary_display_test.dart`

- [ ] **Step 1: 写失败测试（DayWeatherSummary.display）**

创建 `test/daily_summary_display_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/daily_summary.dart';

void main() {
  test('DayWeatherSummary.display 拼接地点/emoji/温度', () {
    const w = DayWeatherSummary(
      locationName: '海淀区',
      weatherIcon: '104',
      weatherText: '阴',
      tempMin: 18,
      tempMax: 25,
    );
    expect(w.display, contains('海淀区'));
    expect(w.display, contains('☁️')); // weatherEmoji('104') == '☁️'
    expect(w.display, contains('18°~25°'));
  });

  test('display 无数据返回空字符串', () {
    const w = DayWeatherSummary();
    expect(w.display, '');
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/daily_summary_display_test.dart`
Expected: FAIL，报 `display` getter 未定义。

- [ ] **Step 3: 给 DayWeatherSummary 加 display getter**

在 `lib/models/daily_summary.dart` 的 `DayWeatherSummary` 类内，`tempDisplay` getter 之后追加：

```dart
  /// 聚合天气的展示文本，如 '海淀区  ☁️ 18°~25°'；无数据返回 ''。
  String get display {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    if (weatherIcon != null) {
      final emoji =
          DiaryEntry.weatherEmoji(weatherIcon!) ?? weatherText ?? '';
      if (emoji.isNotEmpty) parts.add(emoji);
    }
    if (tempDisplay.isNotEmpty) parts.add(tempDisplay);
    return parts.join('  ');
  }
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/daily_summary_display_test.dart`
Expected: PASS。

- [ ] **Step 5: 在 recording_processor.dart 加 ensureProcessingFgsRunning helper**

在 `processingCallback()` 函数之后、`class ProcessingTaskHandler` 之前追加：

```dart
/// 确保 processing FGS 正在运行：未运行则启动（复用现有 channel / processingCallback）；
/// 已运行则不重复启动。供启动钩子、详情页重新生成、list 手动生成共用。
Future<void> ensureProcessingFgsRunning({
  String notificationText = '语音日记 - 处理中...',
}) async {
  if (await FlutterForegroundTask.isRunningService) return;
  FlutterForegroundTask.initCommunicationPort();
  final result = await FlutterForegroundTask.startService(
    serviceTypes: [ForegroundServiceTypes.dataSync],
    notificationTitle: '正在处理',
    notificationText: notificationText,
    callback: processingCallback,
  );
  if (result is ServiceRequestFailure) {
    debugPrint('[Processing] 启动 FGS 失败: ${result.error}');
  }
}
```

- [ ] **Step 6: 创建 lib/pages/daily_summary_page.dart**

创建 `lib/pages/daily_summary_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../design_tokens.dart';
import '../models/daily_summary.dart';
import '../models/diary_entry.dart';
import '../services/diary_storage_service.dart';
import '../services/recording_processor.dart';
import '../services/tts_service.dart';
import '../widgets/detail/detail_content_section.dart';
import 'diary_detail_page.dart';

class DailySummaryPage extends StatefulWidget {
  /// 日期 'yyyy-MM-dd'。
  final String date;

  const DailySummaryPage({super.key, required this.date});

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  final _storageService = DiaryStorageService();
  final _ttsService = TtsService();

  bool _loading = true;
  DailySummary? _summary;
  DailySummaryData? _data;
  List<DiaryEntry> _entries = const [];
  bool _isActivelyProcessing = false;
  bool _isPlayingTts = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  Future<void> _loadData() async {
    final summary = await _storageService.getDailySummary(widget.date);
    final entries = await _storageService.getEntriesByDate(widget.date);
    DailySummaryData? data;
    if (await _storageService.hasDailySummary(widget.date)) {
      try {
        data = await _storageService.readDailySummaryJson(widget.date);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _summary = summary;
        _entries = entries;
        _data = data;
        _loading = false;
      });
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    final date = data['date'] as String?;
    if (date != null && date != widget.date) return;

    if (type == 'dailySummaryStage' && mounted) {
      setState(() => _isActivelyProcessing = true);
    } else if ((type == 'dailySummaryCompleted' ||
            type == 'dailySummaryFailed') &&
        mounted) {
      setState(() => _isActivelyProcessing = false);
      _loadData();
    }
  }

  String get _dateDisplay {
    final d = DateTime.parse(widget.date);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}';
  }

  DayWeatherSummary get _weather => aggregateDayWeather(_entries);

  Future<void> _playOutline() async {
    if (_data == null || _data!.outline.isEmpty) return;
    setState(() => _isPlayingTts = true);
    try {
      await _ttsService.speak(_data!.outline, VoiceType.femaleSweet);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('播报失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPlayingTts = false);
    }
  }

  Future<void> _regenerate() async {
    final now = DateTime.now();
    final existing = await _storageService.getDailySummary(widget.date);
    await _storageService.saveDailySummary(
      DailySummary(
        date: widget.date,
        title: '正在生成…',
        status: EntryStatus.processing,
        sourceEntryIds: existing?.sourceEntryIds ?? const [],
        entryCount: existing?.entryCount ?? 0,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    await ensureProcessingFgsRunning(notificationText: '生成每日总结...');
    if (mounted) setState(() => _isActivelyProcessing = true);
    _loadData();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除每日总结'),
        content: const Text('删除总结不影响当天的录音，确定删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _storageService.deleteDailySummary(widget.date);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weatherDisplay = _weather.display;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dateDisplay, style: const TextStyle(fontSize: 16)),
            if (weatherDisplay.isNotEmpty)
              Text(
                weatherDisplay,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: WarmTokens.warmMuted,
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'regen') {
                _regenerate();
              } else if (v == 'delete') {
                _delete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'regen', child: Text('重新生成')),
              PopupMenuItem(value: 'delete', child: Text('删除总结')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusBanner(),
                    if (_data?.degraded == true)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: WarmTokens.warmMuted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '当天内容较长，基于各篇摘要生成',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: WarmTokens.warmMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_data != null && _data!.summary.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DetailContentSection(summary: _data!.summary),
                    ],
                    if (_data != null && _data!.outline.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildOutlineSection(),
                    ],
                    const SizedBox(height: 24),
                    _buildEntryList(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _summary?.status;
    if (status == EntryStatus.processing) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WarmTokens.warmProcessBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WarmTokens.warmMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isActivelyProcessing ? '正在生成每日总结...' : '生成暂停',
              style: const TextStyle(
                color: WarmTokens.warmBrown,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    if (status == EntryStatus.failed) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WarmTokens.failedBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: WarmTokens.failedAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '生成失败',
                style: TextStyle(color: WarmTokens.failedText, fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('重试', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: WarmTokens.failedAccent,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildOutlineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: WarmTokens.warmAmber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '概览播报',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WarmTokens.warmBrown,
              ),
            ),
            const Spacer(),
            if (_isPlayingTts)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.volume_up),
                onPressed: _playOutline,
                tooltip: '播报',
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _data!.outline,
          style: TextStyle(
            fontSize: 14,
            height: 1.8,
            color: WarmTokens.warmBrown,
          ),
        ),
      ],
    );
  }

  Widget _buildEntryList() {
    if (_entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: WarmTokens.warmAmber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '当天录音 ${_entries.length} 篇',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WarmTokens.warmBrown,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._entries.map(_buildEntryItem),
      ],
    );
  }

  Widget _buildEntryItem(DiaryEntry e) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: e)),
            )
            .then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WarmTokens.warmCardBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: WarmTokens.warmBrown,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${e.formattedDate} · ${e.durationDisplay}',
                    style: TextStyle(
                      fontSize: 12,
                      color: WarmTokens.warmMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: WarmTokens.warmMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: main.dart 启动钩子改用 ensureProcessingFgsRunning（DRY）**

7a. 修改 `lib/main.dart` 顶部 import 的 recording_processor 行，加上 helper：

```dart
import 'services/recording_processor.dart'
    show processingCallback, ensureProcessingFgsRunning;
```

> 注意：`processingCallback` 现在只被 `ensureProcessingFgsRunning` 内部使用，main.dart 不再直接引用。若 `flutter analyze` 报 `processingCallback` 未使用，可把 import 简化为 `show ensureProcessingFgsRunning;`。先用上面这行，Step 8 的 analyze 会给出确切结论。

7b. 把 `_runDailySummaryIfNeeded` 中的 FGS 启动段：

```dart
    if (!await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.initCommunicationPort();
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '正在处理',
        notificationText: '语音日记 - 处理中...',
        callback: processingCallback,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[DailySummary] 启动 FGS 失败: ${result.error}');
      }
    }
```

替换为：

```dart
    await ensureProcessingFgsRunning();
```

- [ ] **Step 8: analyze + 提交**

Run: `flutter analyze lib/models/daily_summary.dart lib/services/recording_processor.dart lib/pages/daily_summary_page.dart lib/main.dart`
Expected: `No issues found!`。若 main.dart 报 `processingCallback` 未使用 import，按 Step 7a 说明把 import 改为 `show ensureProcessingFgsRunning;`。

```bash
dart format lib/models/daily_summary.dart lib/services/recording_processor.dart lib/pages/daily_summary_page.dart lib/main.dart test/daily_summary_display_test.dart
git add lib/models/daily_summary.dart lib/services/recording_processor.dart lib/pages/daily_summary_page.dart lib/main.dart test/daily_summary_display_test.dart
git commit -m "feat: 新增 DailySummaryPage（聚合天气/正文/TTS 播报/录音列表）与 FGS 启动 helper"
```

---

## Task 9: list 分组重构 + 「本日总结」行 + 手动操作 + FGS 消息监听

改造 `diary_list_page.dart`：分组 key 由 label 改为 `dateKey 'yyyy-MM-dd'`（label 仅用于显示），每个分组下新增按 DailySummary 状态自适应的「本日总结」行；扩展 FGS 消息监听刷新。

> 本任务为 UI 改造，无自动化测试（与 Task 8 同理），靠 Task 10 手动验证状态自适应。
>
> `_dateKey` 为本页私有日期格式化（与 main.dart 的 `dateKey` 逻辑一致，2 行小函数，本地保留以避免 page 反向 import app 入口）。

**Files:**
- Modify: `lib/services/diary_storage_service.dart`（加 `getAllDailySummaries` 包装）
- Modify: `lib/pages/diary_list_page.dart`（import、State 字段、`_loadData`、`_onTaskData`、`_buildDateGroups`、新增 `_buildDailySummaryRow` / `_requestDailySummary` / `_dateKey`）

- [ ] **Step 1: diary_storage_service.dart 加 getAllDailySummaries**

在 Task 3 新增的 `getPendingDailySummaries` 方法之后追加：

```dart
  Future<List<DailySummary>> getAllDailySummaries() async {
    final rows = await _db.getAllDailySummaries();
    return rows.map(_summaryRowToModel).toList();
  }
```

- [ ] **Step 2: diary_list_page.dart 加 import**

在文件顶部 import 区，`import '../models/diary_entry.dart';` 之后追加：

```dart
import '../models/daily_summary.dart';
```

在 `import 'diary_detail_page.dart';` 之后追加：

```dart
import '../services/recording_processor.dart' show ensureProcessingFgsRunning;
import 'daily_summary_page.dart';
```

- [ ] **Step 3: State 加 _dailySummaries 字段**

找到（约第 22 行）：

```dart
  Map<String, List<Tag>> _entryTags = {};
  bool _loading = true;
```

在 `_entryTags = {};` 之后插入一行：

```dart
  Map<String, List<Tag>> _entryTags = {};
  Map<String, DailySummary> _dailySummaries = {};
  bool _loading = true;
```

- [ ] **Step 4: _loadData 加 daily summaries 查询**

找到现有 `_loadData` 方法，把它替换为：

```dart
  Future<void> _loadData() async {
    // 并发保护：_onTaskData / onRefresh / 页面返回 .then 等多处可能并发触发 _loadData，
    // 用版本号确保只有最后一次发起的加载结果写入 UI，避免旧结果覆盖新结果。
    final version = ++_loadVersion;
    final entries = await _storageService.getAllEntries();
    final tags = await _storageService.getAllTags();
    // 复用上面已查的 tags，避免 getAllEntryTags 内部重复查询 tags 表
    final entryTags = await _storageService.getAllEntryTags(allTags: tags);
    final dailySummaries = await _storageService.getAllDailySummaries();
    if (version != _loadVersion) return;
    if (mounted) {
      setState(() {
        _entries = entries;
        _tags = tags;
        _entryTags = entryTags;
        _dailySummaries = {for (final d in dailySummaries) d.date: d};
        _loading = false;
      });
    }
  }
```

- [ ] **Step 5: _onTaskData 扩展监听 dailySummary 消息**

找到现有 `_onTaskData` 方法，替换为：

```dart
  /// 接收 FGS 消息，录音/每日总结完成/失败/阶段更新时刷新列表
  void _onTaskData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final type = data['type'] as String;
    if (type == 'completed' ||
        type == 'failed' ||
        type == 'dailySummaryCompleted' ||
        type == 'dailySummaryFailed' ||
        type == 'dailySummaryStage') {
      _loadData();
    }
  }
```

- [ ] **Step 6: 重构 _buildDateGroups（按 dateKey 分组 + 插入 summary 行）**

找到现有 `_buildDateGroups` 方法，替换为：

```dart
  Widget _buildDateGroups(List<DiaryEntry> entries) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    // 按 dateKey 'yyyy-MM-dd' 分组，保留插入顺序（entries 已按 createdAt desc）
    final groups = <String, List<DiaryEntry>>{};
    for (final entry in entries) {
      final key = _dateKey(entry.createdAt);
      groups.putIfAbsent(key, () => []).add(entry);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: WarmTokens.warmAmber,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: groups.entries
            .expand((group) {
              final date = DateTime.parse(group.key);
              final diff = todayDate.difference(date).inDays;
              final label = _getDateLabel(date, diff);
              return [
                _buildGroupHeader(label),
                _buildDailySummaryRow(group.key),
                ...group.value.map((entry) => _buildEntryCard(entry)),
              ];
            })
            .toList(),
      ),
    );
  }

  /// DateTime → 'yyyy-MM-dd'。
  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
```

- [ ] **Step 7: 新增 _buildDailySummaryRow 与 _requestDailySummary**

在 `_buildDateGroups` 方法之后（`_getDateLabel` 之前）新增：

```dart
  /// 请求生成/重新生成某天的每日总结：置 status=processing + 启动 FGS。
  Future<void> _requestDailySummary(String dateKey) async {
    final now = DateTime.now();
    final existing = _dailySummaries[dateKey];
    await _storageService.saveDailySummary(
      DailySummary(
        date: dateKey,
        title: '正在生成…',
        status: EntryStatus.processing,
        sourceEntryIds: existing?.sourceEntryIds ?? const [],
        entryCount: existing?.entryCount ?? 0,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    await ensureProcessingFgsRunning(notificationText: '生成每日总结...');
    _loadData();
  }

  /// 每个日期分组下的「本日总结」行，按 DailySummary 状态自适应。
  Widget _buildDailySummaryRow(String dateKey) {
    final summary = _dailySummaries[dateKey];

    // processing：转圈
    if (summary?.status == EntryStatus.processing) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WarmTokens.warmProcessBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WarmTokens.warmAmber,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '⏳ 正在生成本日总结…',
              style: TextStyle(fontSize: 14, color: WarmTokens.warmBrown),
            ),
          ],
        ),
      );
    }

    // failed：重试
    if (summary?.status == EntryStatus.failed) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WarmTokens.failedBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: WarmTokens.failedAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠ 生成失败',
                style: TextStyle(fontSize: 14, color: WarmTokens.failedText),
              ),
            ),
            TextButton(
              onPressed: () => _requestDailySummary(dateKey),
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // completed：标题预览 + 重新生成
    if (summary?.status == EntryStatus.completed) {
      final s = summary!;
      return GestureDetector(
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => DailySummaryPage(date: dateKey),
                ),
              )
              .then((_) => _loadData());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: WarmTokens.warmCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: WarmTokens.warmAmber.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_stories,
                size: 18,
                color: WarmTokens.warmAmber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WarmTokens.warmBrown,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _requestDailySummary(dateKey),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh,
                    size: 16,
                    color: WarmTokens.warmMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 无记录：生成本日总结
    return GestureDetector(
      onTap: () => _requestDailySummary(dateKey),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WarmTokens.warmAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: WarmTokens.warmAmber.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_note, size: 18, color: WarmTokens.warmAmber),
            const SizedBox(width: 8),
            Text(
              '📝 生成本日总结',
              style: TextStyle(
                fontSize: 14,
                color: WarmTokens.warmAmber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 8: analyze + 提交**

Run: `flutter analyze lib/services/diary_storage_service.dart lib/pages/diary_list_page.dart`
Expected: `No issues found!`

```bash
dart format lib/services/diary_storage_service.dart lib/pages/diary_list_page.dart
git add lib/services/diary_storage_service.dart lib/pages/diary_list_page.dart
git commit -m "feat: list 按日期分组新增「本日总结」行（状态自适应）与手动生成"
```

---

## Task 10: 收尾（全量 analyze + format + test + 集成验证）

所有功能任务完成后，做全量质量门禁 + 手动集成验证。

**Files:** 无新增，仅验证与可能的格式修复。

- [ ] **Step 1: 全量 dart format**

Run: `dart format lib/ test/`
Expected: 列出本次改动文件（若有格式调整），无错误。

- [ ] **Step 2: 全量 flutter analyze 清零**

Run: `flutter analyze`
Expected: `No issues found!`。若有 info/warning/error，逐个修复（极少情况下用 `// ignore: 规则名` 并注释原因；注意 `// ignore:` 规则名后紧跟空格或行尾，勿紧跟中文等非 ASCII 字符）。

- [ ] **Step 3: 全量测试通过**

Run: `flutter test`
Expected: 全部测试通过（既有 4 个 + 本计划新增 7 个测试文件）。

- [ ] **Step 4: 确认 build_runner 产物最新**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 无变更或仅重新生成 `app_database.g.dart`，无错误。

- [ ] **Step 5: 若 Step 1-4 有格式/分析修复，提交**

```bash
git add -A
git commit -m "chore: 每日总结收尾（format + analyze 清零）"
```
（若 Step 1-4 无改动，跳过本步。）

- [ ] **Step 6: 集成手动验证（运行 dev 版本）**

Run: `./scripts/run_dev.sh`（安装到设备后，按以下清单逐项验证）

**启动钩子（spec 第 7 节）：**
- [ ] 昨天有 ≥1 篇录音 → 首次打开 app，FGS 启动生成昨日总结；完成后 list 昨天分组出现 completed 行
- [ ] 昨天无录音 → 打开 app 不创建总结，不报错
- [ ] 同一天再次打开 → 不重复生成（`last_daily_summary_gen_date` 已记录）
- [ ] 模拟多天未打开（手动改设备时间或多次）→ 只自动补昨天一天，更早不回填

**list 分组（spec 第 9.1 节）：**
- [ ] 每个日期分组标题下出现「本日总结」行
- [ ] 无记录 → 「📝 生成本日总结」按钮
- [ ] completed → 标题预览 + 「↻ 重新生成」图标，点击进详情页
- [ ] processing → 「⏳ 正在生成本日总结…」转圈
- [ ] failed → 「⚠ 生成失败 · 重试」

**手动操作（spec 第 8 节）：**
- [ ] 点击「生成本日总结」→ FGS 启动 → 转圈 → completed
- [ ] completed 行点 refresh → 重新生成
- [ ] 详情页菜单「重新生成」→ 重新生成
- [ ] 详情页菜单「删除总结」→ 确认后删除，返回 list 该行变回「生成本日总结」；当天录音仍在

**DailySummary 详情页（spec 第 9.2-9.3 节）：**
- [ ] AppBar 显示日期（如「6月13日 周五」）+ 聚合天气（地点众数 + emoji + 温度范围）
- [ ] 正文 Markdown 渲染正常
- [ ] outline 播报按钮 → TTS 朗读
- [ ] 当天录音列表 → 点击进单篇详情页
- [ ] 降级场景：用一篇超长录音（>25000 字）当天测试，详情页显示「基于各篇摘要生成」提示（可选，难触发）

**FGS 通信（spec 第 9.4 节）：**
- [ ] 生成中 list 行转圈；完成后自动刷新（无需手动下拉）

- [ ] **Step 7: 全部验证通过后，按需更新 spec 状态**

若实现与 spec 有出入（如本计划的差异说明），更新 `docs/superpowers/specs/2026-06-14-daily-summary-design.md` 的「状态」与差异说明，保持 spec/plan 一致。

---

## Self-Review

完成全部任务后，对计划做以下自检（已在撰写时执行，记录结论）：

**1. Spec 覆盖**：spec 各节均有任务对应——
- §3 架构 / §6 任务抽象 → Task 5、6
- §4 数据模型与存储 / §4.3 migration / §4.4 兼容性 → Task 2、3
- §5 LLM 聚合 / §5.2 降级 / §5.3 API 日志 → Task 4
- §7 启动钩子 → Task 7
- §8 手动生成/重新生成/删除 → Task 8（详情页菜单）、Task 9（list 行）
- §9 UI / §9.1 list / §9.2 详情页 / §9.3 天气聚合 / §9.4 FGS 消息 → Task 8、9
- §10 边界（0 篇/processing 篇/失败）→ Task 6（DailySummaryProcessingTask 4 分支测试）
- §11 测试策略 → 各任务 TDD
- §12 实现拆分 1-8 → Task 2-10 一一对应

**2. 占位符扫描**：无 TBD/TODO/「稍后实现」/「类似 Task N」。DiaryProcessingTask 虽是「提取」，但给出了完整目标代码（非引用其他任务）。

**3. 类型一致性**：跨任务关键符号一致——
- 类：`DailySummary`（model）/ `DailySummaryRow`（drift 行）/ `DailySummariesCompanion`（Task 3 命名决策）/ `DailySummaryData` / `DailySummaryResult` / `DailySummaryService` / `DailySummaryProcessingTask` / `DiaryProcessingTask` / `ProcessingTask` / `ProcessingContext` / `DailySummaryException` / `DayWeatherSummary`
- 方法：`summarizeDay`（DailySummaryService）/ `summarizeDayText`（LlmService）/ `buildDayFullText` / `shouldDegrade` / `buildDaySummariesText` / `aggregateDayWeather` / `getEntriesByDate` / `getDailySummary` / `getPendingDailySummaries` / `getAllDailySummaries` / `saveDailySummary` / `deleteDailySummary` / `writeDailySummaryJson` / `readDailySummaryJson` / `hasDailySummary` / `ensureProcessingFgsRunning` / `dailySummaryTargetDate` / `dateKey`
- FGS 消息 type：`dailySummaryStage` / `dailySummaryCompleted` / `dailySummaryFailed`（Task 6 发送，Task 8/9 监听，命名一致）
- `ProcessingContext` 字段：`storage` / `llm` / `asr` / `tos` / `apiLog` / `dailySummary` / `sendToMain`（Task 5 定义，Task 5/6 消费，一致）

结论：计划与 spec 对齐、无占位符、类型一致，可交付执行。


> 说明：本任务**只新增** `ProcessingTask`/`ProcessingContext`/`DiaryProcessingTask`，**暂不改动** `recording_processor.dart`（调度器改造在 Task 6）。此时 `DiaryProcessingTask` 与原 `ProcessingTaskHandler._processEntry` 等并存，无冲突。Task 6 会把调度器切到使用 Task，并移除旧逻辑。

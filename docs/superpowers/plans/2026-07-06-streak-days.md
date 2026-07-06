# 录音累计天数显示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在录音主界面顶部展示「您已经连续 X 天，累计 Y 天录制语音日记」；录音启动时渐进缩小到左上角 chip，本 session 内单向不回弹。

**Architecture:** 纯函数计算 streak/total（`lib/utils/recording_stats.dart`）← `DiaryStorageService.getRecordingDayStats()` 查询 `DiaryEntries.createdAt` 包装 ← `StreakBadge` 纯展示组件（内部用 `AnimatedAlign`+`AnimatedScale`+`AnimatedContainer`+`AnimatedOpacity`）← `RecordingPage` 把 body 改为 `Stack`，用 `_hasRecordedThisSession` 标志位驱动 compact。

**Tech Stack:** Flutter / Dart, drift（已有）, flutter_test。无新增依赖。

## Global Constraints

- 包名 `voice_diary`（import 前缀 `package:voice_diary/...`）。
- 注释 / 文档 / commit message 用中文；代码标识符用英文。
- **每个任务提交前必须**：对改动文件运行 `dart format <files>`，并运行 `flutter analyze` 直到输出 `No issues found!`（info/warning/error 全清零）才可 commit。
- **禁止** `throw Exception('...')`；业务正常结果用返回值表达，真正错误用 `lib/exceptions.dart` 中的派生类。
- 数据兼容：不新增表、不新增列、不改文件格式；只读 `DiaryEntries.createdAt`。
- 若 `// ignore:` 规则名后必须紧跟空格或行尾，**不要**紧跟中文等非 ASCII 字符（否则忽略静默失效）。
- 本计划在 worktree `feature/period` 分支上执行；每个 Task 末尾 commit，不 push。

参考设计稿：`docs/superpowers/specs/2026-07-06-streak-days-design.md`。

---

## File Structure

| 文件 | 职责 | 动作 |
|---|---|---|
| `lib/utils/recording_stats.dart` | 纯函数 `computeRecordingStats()`：日期集合 + now → (streak, total) | 新建 |
| `test/utils/recording_stats_test.dart` | 纯函数单测 | 新建 |
| `lib/services/diary_storage_service.dart` | `getRecordingDayStats({DateTime? now})`：查 createdAt 列，调纯函数 | 修改 |
| `test/diary_storage_service_test.dart` | service 方法测试（追加用例） | 修改 |
| `lib/design_tokens.dart` | 新增 6 个 streak 专用色 token | 修改 |
| `lib/widgets/streak_badge.dart` | `StreakBadge` 纯展示组件（含全部动画） | 新建 |
| `test/widgets/streak_badge_test.dart` | widget 测试 | 新建 |
| `lib/pages/recording_page.dart` | 加载 stats、`_hasRecordedThisSession`、body 改 Stack | 修改 |

---

## Task 1: 纯函数 computeRecordingStats + 单测

**Files:**
- Create: `lib/utils/recording_stats.dart`
- Test: `test/utils/recording_stats_test.dart`

**Interfaces:**
- Produces: `({int currentStreak, int totalDays}) computeRecordingStats({required Iterable<DateTime> recordingTimes, required DateTime now})`

口径（来自 spec）：把 `recordingTimes` 折算本地日期去重 → `totalDays`；起点 anchor = 今天（若集合含今天）否则昨天（若含昨天）否则 streak=0；从 anchor 按天往前数连续命中。

- [ ] **Step 1: 写失败测试**

Create `test/utils/recording_stats_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/utils/recording_stats.dart';

void main() {
  // 固定 now，所有用例围绕 2026-07-06（周二）。
  final now = DateTime(2026, 7, 6, 12, 0);

  ({int currentStreak, int totalDays}) stats(List<DateTime> times) =>
      computeRecordingStats(recordingTimes: times, now: now);

  test('空集合 → (0, 0)', () {
    expect(stats([]), (currentStreak: 0, totalDays: 0));
  });

  test('只有今天 → (1, 1)', () {
    expect(stats([DateTime(2026, 7, 6, 8, 0)]), (currentStreak: 1, totalDays: 1));
  });

  test('今天 + 昨天 → (2, 2)', () {
    expect(
      stats([DateTime(2026, 7, 6), DateTime(2026, 7, 5)]),
      (currentStreak: 2, totalDays: 2),
    );
  });

  test('只有昨天（今天没录）→ 向后兼容，(1, 1)', () {
    expect(stats([DateTime(2026, 7, 5)]), (currentStreak: 1, totalDays: 1));
  });

  test('昨天 + 前天（今天没录）→ (2, 2)', () {
    expect(
      stats([DateTime(2026, 7, 5), DateTime(2026, 7, 4)]),
      (currentStreak: 2, totalDays: 2),
    );
  });

  test('今天 + 昨天 + 断档 + 前天 → 断档后不往前数，(2, 2)', () {
    expect(
      stats([DateTime(2026, 7, 6), DateTime(2026, 7, 5), DateTime(2026, 7, 3)]),
      (currentStreak: 2, totalDays: 3),
    );
  });

  test('同一天多条 entry → 去重，(1, 1)', () {
    expect(
      stats([DateTime(2026, 7, 6, 8), DateTime(2026, 7, 6, 20)]),
      (currentStreak: 1, totalDays: 1),
    );
  });

  test('只有前天（今/昨都没）→ 累计 1，连续 0', () {
    expect(stats([DateTime(2026, 7, 4)]), (currentStreak: 0, totalDays: 1));
  });

  test('长连续：今天起往前 5 天 → (5, 5)', () {
    expect(
      stats([
        DateTime(2026, 7, 6),
        DateTime(2026, 7, 5),
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 3),
        DateTime(2026, 7, 2),
      ]),
      (currentStreak: 5, totalDays: 5),
    );
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/utils/recording_stats_test.dart`
Expected: FAIL — `computeRecordingStats` 未定义 / import 失败。

- [ ] **Step 3: 写实现**

Create `lib/utils/recording_stats.dart`:

```dart
/// 录音统计：根据有录音的时间点集合 + 当前时间，计算连续天数与累计天数。
///
/// - [totalDays]：所有录音按本地日期去重后的天数。
/// - [currentStreak]：含今天且向后兼容昨天——
///   集合含「今天」则从今天起往前数；今天没有、含「昨天」则从昨天起往前数；
///   都没有则返回 0。
library;

/// 把 [dt] 折算为本地日期的 'yyyy-MM-dd' key（与具体时分秒无关）。
String _dateKey(DateTime dt) {
  final l = dt.toLocal();
  return '${l.year}-'
      '${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')}';
}

/// 计算录音统计。
///
/// 纯函数（不查 DB、不读系统时钟），便于单测。`now` 由调用方注入。
({int currentStreak, int totalDays}) computeRecordingStats({
  required Iterable<DateTime> recordingTimes,
  required DateTime now,
}) {
  final days = <String>{};
  for (final t in recordingTimes) {
    days.add(_dateKey(t));
  }
  final totalDays = days.length;
  if (totalDays == 0) return (currentStreak: 0, totalDays: 0);

  final nowLocal = now.toLocal();
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final anchor = days.contains(_dateKey(today))
      ? today
      : (days.contains(_dateKey(yesterday)) ? yesterday : null);

  if (anchor == null) return (currentStreak: 0, totalDays: totalDays);

  var streak = 0;
  var cur = anchor;
  while (days.contains(_dateKey(cur))) {
    streak++;
    cur = cur.subtract(const Duration(days: 1));
  }
  return (currentStreak: streak, totalDays: totalDays);
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/utils/recording_stats_test.dart`
Expected: PASS（全部用例）。

- [ ] **Step 5: format + analyze**

Run: `dart format lib/utils/recording_stats.dart test/utils/recording_stats_test.dart`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: commit**

```bash
git add lib/utils/recording_stats.dart test/utils/recording_stats_test.dart
git commit -m "feat: 新增录音统计纯函数 computeRecordingStats

按本地日期去重计算累计天数；连续天数含今天且向后兼容昨天。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: DiaryStorageService.getRecordingDayStats + 测试

**Files:**
- Modify: `lib/services/diary_storage_service.dart`（在类末尾、`getPendingProcessingTasks()` 后追加）
- Test: `test/diary_storage_service_test.dart`（在 `main()` 内追加用例）

**Interfaces:**
- Consumes: `computeRecordingStats`（Task 1）
- Produces: `Future<({int currentStreak, int totalDays})> DiaryStorageService.getRecordingDayStats({DateTime? now})`

- [ ] **Step 1: 写失败测试**

在 `test/diary_storage_service_test.dart` 的 `main()` 内追加（已有的 `setUp` 提供了 `service`、`db`，`createEntry` helper 默认 `createdAt: DateTime(2026, 6, 14)`，这里需要自定义 createdAt，所以直接调 `service.createEntry`）：

```dart
  group('getRecordingDayStats', () {
    Future<void> entryAt(String id, DateTime createdAt) async {
      await service.createEntry(
        DiaryEntry(
          id: id,
          title: 't',
          folderPath: '/tmp/$id',
          durationSeconds: 60,
          createdAt: createdAt,
        ),
      );
    }

    test('空库 → (0, 0)', () async {
      expect(
        await service.getRecordingDayStats(now: DateTime(2026, 7, 6)),
        (currentStreak: 0, totalDays: 0),
      );
    });

    test('今天 + 昨天 → (2, 2)；以注入 now 为准', () async {
      await entryAt('a', DateTime(2026, 7, 6, 9));
      await entryAt('b', DateTime(2026, 7, 5, 21));
      expect(
        await service.getRecordingDayStats(now: DateTime(2026, 7, 6, 12)),
        (currentStreak: 2, totalDays: 2),
      );
    });

    test('同一天多条 → 去重 (1, 1)', () async {
      await entryAt('a', DateTime(2026, 7, 6, 8));
      await entryAt('b', DateTime(2026, 7, 6, 20));
      expect(
        await service.getRecordingDayStats(now: DateTime(2026, 7, 6)),
        (currentStreak: 1, totalDays: 1),
      );
    });

    test('不传 now 时使用 DateTime.now()（冒烟：返回 totalDays==已插入数）', () async {
      await entryAt('now1', DateTime.now());
      final r = await service.getRecordingDayStats();
      expect(r.totalDays, greaterThanOrEqualTo(1));
      expect(r.currentStreak, greaterThanOrEqualTo(1));
    });
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/diary_storage_service_test.dart`
Expected: FAIL — `getRecordingDayStats` 方法未定义。

- [ ] **Step 3: 写实现**

在 `lib/services/diary_storage_service.dart` 顶部 import 区追加（若尚无）：

```dart
import '../utils/recording_stats.dart';
```

在类 `DiaryStorageService` 内、`getPendingProcessingTasks()` 方法之后追加：

```dart
  /// 计算录音统计（连续天数 + 累计天数），基于所有 DiaryEntries.createdAt。
  ///
  /// 仅查 createdAt 列，内存去重计算。[now] 默认 `DateTime.now()`，
  /// 测试可注入固定时间。
  Future<({int currentStreak, int totalDays})> getRecordingDayStats({
    DateTime? now,
  }) async {
    final rows = await (_db.selectOnly(_db.diaryEntries)
          ..addColumns([_db.diaryEntries.createdAt]))
        .get();
    final times = rows.map(
      (r) => DateTime.fromMillisecondsSinceEpoch(
        r.read(_db.diaryEntries.createdAt)!,
      ),
    );
    return computeRecordingStats(
      recordingTimes: times,
      now: now ?? DateTime.now(),
    );
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/diary_storage_service_test.dart`
Expected: PASS（含新增 group 全部用例）。

- [ ] **Step 5: format + analyze**

Run: `dart format lib/services/diary_storage_service.dart test/diary_storage_service_test.dart`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: commit**

```bash
git add lib/services/diary_storage_service.dart test/diary_storage_service_test.dart
git commit -m "feat: DiaryStorageService 新增 getRecordingDayStats

仅查 createdAt 列，复用 computeRecordingStats 纯函数；支持注入 now 便于测试。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: design tokens + StreakBadge 组件 + widget 测试

**Files:**
- Modify: `lib/design_tokens.dart`（在 `WarmTokens` 类内追加 6 个 token）
- Create: `lib/widgets/streak_badge.dart`
- Test: `test/widgets/streak_badge_test.dart`

**Interfaces:**
- Produces: `StreakBadge` widget，签名见下方 Step 3。

视觉规格（来自 spec）：
- 数字 amber `0xFFC8862A` 30px w800；中间灰 `0xFFB6A48C` 15px；上下行淡灰 `0xFFD4C6B0` 12px letterSpacing 2；逗号 `0xFFDDD0BD`；三行 height 1.15 紧贴；中文逗号。
- 「您已经」左对齐、「录制语音日记」右对齐到数字行右边缘 → 用 `IntrinsicWidth` + `CrossAxisAlignment.stretch` + `textAlign`。
- chip 态：bg `0xFFFFF3E0` + border `0xFFF0D9A8` 0.5，圆角 10，padding 4×9。
- 动画：duration 600ms，curve `Curves.easeInOutCubic`。
- idle 对齐 `Alignment(0, -0.5)`，compact 对齐 `Alignment.topLeft`（compact 时再内嵌 `EdgeInsets.only(left:20, top:14)`）。
- compact scale 0.62；前后缀 AnimatedOpacity 1.0→0.0。
- `total == 0`：渲染鼓励文案「开始第一篇语音日记吧」替代数字三行（动画行为相同）。

- [ ] **Step 1: 追加 design tokens**

在 `lib/design_tokens.dart` 的 `WarmTokens` 类内（`failedText` 之后）追加：

```dart
  // === StreakBadge 专用 ===
  /// 数字（琥珀强调）
  static const Color streakAmber = Color(0xFFC8862A);

  /// 中间行灰文字（连续 / 累计 / 天）
  static const Color streakMidGray = Color(0xFFB6A48C);

  /// 上下行更淡灰（您已经 / 录制语音日记）
  static const Color streakLightGray = Color(0xFFD4C6B0);

  /// 逗号
  static const Color streakComma = Color(0xFFDDD0BD);

  /// compact chip 背景
  static const Color streakChipBg = Color(0xFFFFF3E0);

  /// compact chip 边框
  static const Color streakChipBorder = Color(0xFFF0D9A8);
```

- [ ] **Step 2: 写失败 widget 测试**

Create `test/widgets/streak_badge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/widgets/streak_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(child: Stack(children: [Positioned.fill(child: child)])),
      ),
    );

void main() {
  testWidgets('idle(compact=false) 渲染三行 + 两个琥珀数字', (tester) async {
    await tester.pumpWidget(_wrap(const StreakBadge(streak: 27, total: 40, compact: false)));
    await tester.pumpAndSettle();

    expect(find.text('您已经'), findsOneWidget);
    expect(find.text('录制语音日记'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('total==0 渲染鼓励文案、不渲染数字', (tester) async {
    await tester.pumpWidget(_wrap(const StreakBadge(streak: 0, total: 0, compact: false)));
    await tester.pumpAndSettle();

    expect(find.text('开始第一篇语音日记吧'), findsOneWidget);
    expect(find.text('您已经'), findsNothing);
  });

  testWidgets('compact=true：前后缀 opacity=0（隐藏），数字仍渲染', (tester) async {
    await tester.pumpWidget(_wrap(const StreakBadge(streak: 27, total: 40, compact: true)));
    await tester.pumpAndSettle();

    // 数字仍在树中
    expect(find.text('27'), findsOneWidget);
    // 前后缀被 AnimatedOpacity 置 0
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();
    expect(opacities, contains(0.0));
  });

  testWidgets('compact=true 且无数据：鼓励文案渲染', (tester) async {
    await tester.pumpWidget(_wrap(const StreakBadge(streak: 0, total: 0, compact: true)));
    await tester.pumpAndSettle();
    expect(find.text('开始第一篇语音日记吧'), findsOneWidget);
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `flutter test test/widgets/streak_badge_test.dart`
Expected: FAIL — `StreakBadge` 未定义 / import 失败。

- [ ] **Step 4: 写 StreakBadge 实现**

Create `lib/widgets/streak_badge.dart`:

```dart
import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 录音累计天数徽章。
///
/// 居中醒目形态（[compact]=false）：三行——「您已经」/ 数字行 / 「录制语音日记」，
/// 前两行左对齐、末行右对齐到数字行右边缘，整体由外层居中。
///
/// 缩略形态（[compact]=true）：整体缩到左上角，前后缀淡出，只剩数字行，
/// 带 chip 背景。
///
/// [total]==0 时（首次使用）改显示鼓励文案「开始第一篇语音日记吧」，
/// 动画行为不变。
class StreakBadge extends StatelessWidget {
  const StreakBadge({
    super.key,
    required this.streak,
    required this.total,
    required this.compact,
  });

  final int streak;
  final int total;
  final bool compact;

  static const _duration = Duration(milliseconds: 600);
  static const _curve = Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    return AnimatedAlign(
      alignment: compact ? Alignment.topLeft : const Alignment(0, -0.5),
      duration: _duration,
      curve: _curve,
      child: Padding(
        padding: compact
            ? const EdgeInsets.only(left: 20, top: 14)
            : EdgeInsets.zero,
        child: AnimatedScale(
          scale: compact ? 0.62 : 1.0,
          duration: _duration,
          curve: _curve,
          child: AnimatedContainer(
            duration: _duration,
            curve: _curve,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 9, vertical: 4)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: compact ? WarmTokens.streakChipBg : const Color(0x00000000),
              borderRadius: compact ? BorderRadius.circular(10) : BorderRadius.zero,
              border: compact
                  ? Border.all(color: WarmTokens.streakChipBorder, width: 0.5)
                  : Border.none,
            ),
            child: total == 0 ? _encourage() : _block(),
          ),
        ),
      ),
    );
  }

  Widget _encourage() {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: _duration,
      curve: _curve,
      child: Text(
        '开始第一篇语音日记吧',
        style: TextStyle(
          fontSize: 15,
          color: WarmTokens.streakMidGray,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _block() {
    final fadeOpacity = compact ? 0.0 : 1.0;
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedOpacity(
            opacity: fadeOpacity,
            duration: _duration,
            curve: _curve,
            child: Text(
              '您已经',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 12,
                color: WarmTokens.streakLightGray,
                letterSpacing: 2,
                height: 1.15,
              ),
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '连续', style: _midStyle()),
                TextSpan(text: '$streak', style: _numStyle()),
                TextSpan(text: '天', style: _midStyle()),
                TextSpan(text: '，', style: _commaStyle()),
                TextSpan(text: '累计', style: _midStyle()),
                TextSpan(text: '$total', style: _numStyle()),
                TextSpan(text: '天', style: _midStyle()),
              ],
            ),
            style: const TextStyle(height: 1.15),
          ),
          AnimatedOpacity(
            opacity: fadeOpacity,
            duration: _duration,
            curve: _curve,
            child: Text(
              '录制语音日记',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: WarmTokens.streakLightGray,
                letterSpacing: 2,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _numStyle() => const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: WarmTokens.streakAmber,
      );

  TextStyle _midStyle() => const TextStyle(
        fontSize: 15,
        color: WarmTokens.streakMidGray,
      );

  TextStyle _commaStyle() => const TextStyle(
        fontSize: 15,
        color: WarmTokens.streakComma,
      );
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/widgets/streak_badge_test.dart`
Expected: PASS（全部 4 用例）。

- [ ] **Step 6: format + analyze**

Run: `dart format lib/design_tokens.dart lib/widgets/streak_badge.dart test/widgets/streak_badge_test.dart`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: commit**

```bash
git add lib/design_tokens.dart lib/widgets/streak_badge.dart test/widgets/streak_badge_test.dart
git commit -m "feat: 新增 StreakBadge 组件与专用色 token

纯展示组件，内部用 AnimatedAlign/Scale/Container/Opacity 实现 idle↔compact 过渡。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: 接入 RecordingPage

**Files:**
- Modify: `lib/pages/recording_page.dart`

**Interfaces:**
- Consumes: `DiaryStorageService.getRecordingDayStats()`（Task 2）、`StreakBadge`（Task 3）
- Produces: 无（最终集成）

无自动化测试（RecordingPage 强依赖 FGS / 平台通道）；用 `./scripts/run_dev.sh` 手动验证。

- [ ] **Step 1: 改 body 为 Stack + 加载 stats + compact 标志位**

打开 `lib/pages/recording_page.dart`。

① 顶部 import 区追加（与已有 widget import 同区）：

```dart
import '../widgets/streak_badge.dart';
```

② 在 `_RecordingPageState` 字段区（`final _storageService = DiaryStorageService();` 附近）追加：

```dart
  ({int currentStreak, int totalDays})? _stats;
  bool _hasRecordedThisSession = false;
```

③ 在 `initState` 内、`ProcessingFgsController.schedule(...)` 之后追加：

```dart
    _loadStats();
```

并在类内新增方法（紧邻 `initState` 之后）：

```dart
  Future<void> _loadStats() async {
    final s = await _storageService.getRecordingDayStats();
    if (mounted) setState(() => _stats = s);
  }
```

④ 在 `_doStartRecording` 内、`setState(() => _state = RecordingState.recording);` 之后追加：

```dart
      if (!_hasRecordedThisSession) {
        _hasRecordedThisSession = true;
      }
```

⑤ 在 `_onTaskData` 的 `case 'recordingComplete':` 分支内、`if (entryId != null) { ... }` 之后追加刷新：

```dart
        await _loadStats();
```

⑥ 把 `build` 中的 `body:` 从 `Center(child: Padding(...))` 改为 `Stack`，原 `Center` 作为 Stack 第一个子，新增 StreakBadge 作为第二个子（覆盖在最上层）。原结构：

```dart
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [ /* 波形 / pill / 文本 / 按钮 / 设备 pill */ ],
            ),
          ),
        ),
```

改为：

```dart
        body: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [ /* 原 children 完全不动 */ ],
                ),
              ),
            ),
            if (_stats != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: StreakBadge(
                    streak: _stats!.currentStreak,
                    total: _stats!.totalDays,
                    compact: _hasRecordedThisSession,
                  ),
                ),
              ),
          ],
        ),
```

> 说明：`IgnorePointer` 保证徽章不拦截波形/按钮点击（徽章在最上层时仍透传触摸）。`_stats == null`（未加载完）时不渲染徽章，避免 `0/0` 闪现。

- [ ] **Step 2: format + analyze**

Run: `dart format lib/pages/recording_page.dart`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全量测试回归**

Run: `flutter test`
Expected: 全部 PASS（不应破坏既有测试）。

- [ ] **Step 4: 手动验证（真机/模拟器）**

Run: `./scripts/run_dev.sh`
逐项核对：
- [ ] 全新安装/无日记时：录音页顶部居中显示「开始第一篇语音日记吧」。
- [ ] 有历史日记时：居中三行，数字琥珀色，「您已经」左对齐、「录制语音日记」右对齐到数字行右缘。
- [ ] 点录音按钮：徽章在 ~600ms 内位移+缩小到左上角，前后缀淡出，剩 chip 数字行；波形变红、按钮变停止态。
- [ ] 停止录音：徽章**停留在左上角，不回到中间**。
- [ ] 录音处理完成（收到通知或几秒后）：左上角 chip 数字 +1（累计天数 +1；若昨天没录今天首次录，连续天数变 1）。
- [ ] 杀进程冷启动后重新进入：徽章再次居中醒目（`_hasRecordedThisSession` 重置）。

- [ ] **Step 5: commit**

```bash
git add lib/pages/recording_page.dart
git commit -m "feat: 录音页接入 StreakBadge

录音前居中醒目展示累计/连续天数；首次录音启动后单向缩到左上角 chip；
录音完成后刷新统计。无数据时显示鼓励文案。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review（写完后已检查）

- **Spec 覆盖**：数据计算（Task 1+2）、UI 结构 + 动画（Task 3+4）、单向 compact（Task 4 的 `_hasRecordedThisSession`）、stats 加载/刷新（Task 4）、边界情况（Task 1 测试覆盖空集/断档/同日多条/向后兼容昨天；Task 3 测试覆盖 total==0 鼓励文案）、视觉规格（Task 3 tokens + 实现）、组件边界（Task 3 纯展示、Task 4 状态在 page）、测试清单（Task 1/2/3 单测 + widget 测）均有对应任务。
- **占位符**：无 TBD/TODO；每步均含完整代码。
- **类型一致**：`computeRecordingStats` 返回记录类型 `({int currentStreak, int totalDays})` 在 Task 1/2/4 一致；`StreakBadge` 字段 `streak/total/compact` 在 Task 3 定义、Task 4 消费一致；`getRecordingDayStats({DateTime? now})` 签名在 Task 2 定义、Task 4 调用一致。

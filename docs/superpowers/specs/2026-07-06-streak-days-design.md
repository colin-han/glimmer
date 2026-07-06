# 录音累计天数显示

## 背景 / 目标

在录音主界面（`RecordingPage`）顶部展示一行轻量信息，强化"持续记录"的正反馈：

> 您已经
> 连续 27 天，累计 40 天
>        录制语音日记

- **录音开始前（app 刚启动、本 session 尚未录过音）**：信息以醒目形态居中显示在波形上方。
- **开始录音后**：信息**渐进缩小、位移到屏幕左上角**变成小 chip，把视觉空间让给波形 / 实时识别文本 / 录音按钮。
- **关键行为约束**：收缩是**单向**的。一旦本 session 内开始过一次录音，停止录音后信息**不再回到中间**，一直停留在左上角。只有重新冷启动 app 才会再次看到居中醒目形态。

## 数据计算（无新表）

基于现有 `DiaryEntries.createdAt` 计算，不新增数据库表、不新增列。

### 连续天数 `currentStreak`（口径：含今天且向后兼容昨天）

1. 取所有 `createdAt`（毫秒），折算成本地日期 `yyyy-MM-dd`，去重得到「有录音的日期集合」`S`。
2. 设 `today` = 今天本地日期，`yesterday` = 昨天本地日期。
3. 起点 `anchor`：
   - 若 `S` 含 `today` → `anchor = today`
   - 否则若 `S` 含 `yesterday` → `anchor = yesterday`
   - 否则 → `currentStreak = 0`（直接返回）
4. 从 `anchor` 起按天往前递减，统计连续命中 `S` 的天数，遇到第一个断档即停。

> 设计意图：今天还没录但昨天录了，streak 不归零（不打断积极性）；但若 anchor 的前一天不在 `S`，则 streak = 1。

### 累计天数 `totalDays`

`S` 的大小（去重后的日期数）。

### 计入标准

任何已创建的 entry（不论 `status` / `processingStage`）都视为"那天录过音"。录音这个动作本身即成立，不看后续处理成败。

### 查询

用 drift `selectOnly` 只取 `createdAt` 列，避免拉全行；在 Dart 内存里去重 + 计算。个人日记量级（百~千条），O(n) 足够，无需缓存或索引。

### API

`DiaryStorageService` 新增：

```dart
Future<({int currentStreak, int totalDays})> getRecordingDayStats();
```

计算逻辑保持纯函数式（集合 → 结果），便于单测。

## UI 结构

### 新组件 `StreakBadge`

文件：`lib/widgets/streak_badge.dart`

纯展示组件，输入：

```dart
class StreakBadge extends StatelessWidget {
  final int streak;
  final int total;
  final bool compact; // false=居中醒目三行；true=左上角 chip
  ...
}
```

不查数据、不感知录音状态——所有数据加载与 compact 判定都在 `RecordingPage`。

### RecordingPage.body 改造

从纯 `Column` 改为 `Stack`：

- **底层**：原有 `Column`（波形 → 天气/位置 pill → 实时文本 → 录音按钮 → 输入设备 pill），不变。
- **顶层**：`Positioned.fill` 包 `AnimatedAlign`，承载 `StreakBadge`。
  - `compact=false` → `Alignment(0, -0.5)`（水平居中、略高于视觉中心）
  - `compact=true` → `Alignment.topLeft`（贴 body 左上角，带 `EdgeInsets` 内边距）

### 动画

`compact` 由 `RecordingPage` 传入；`StreakBadge` 内部用隐式动画过渡，三者同一 duration / curve 同步触发：

| 元素 | idle 值 | compact 值 | 动画组件 |
|---|---|---|---|
| 整体对齐 | `Alignment(0, -0.5)` | `Alignment.topLeft` | `AnimatedAlign` |
| 缩放 | 1.0 | 0.62 | `AnimatedScale` |
| 「您已经」「录制语音日记」透明度 | 1.0 | 0.0 | `AnimatedOpacity` |
| 中间数字行 | 始终可见 | 始终可见（成为 chip 内容） | — |

- **时长**：`Duration(milliseconds: 600)`
- **曲线**：`Curves.easeInOutCubic`

> 注意：`AnimatedAlign` 的对齐参考系是整个 `Stack` body 区域，所以 `Alignment(0, -0.5)` 是相对 body 中心略偏上，与底层 Column 的波形拉开距离（mockup 中视觉间距约 120px）。

## 行为：compact 触发条件

`RecordingPage` 新增状态：

```dart
bool _hasRecordedThisSession = false;
```

- `_startRecording()` 成功（`_state` 切到 `RecordingState.recording`）时置 `true`。
- 传给 `StreakBadge` 的 compact 值：`_hasRecordedThisSession`。

> 一旦置 true，本 session 内不再回 false（停止录音、录音失败回 idle 都不重置）。冷启动重新初始化为 false，居中形态再次出现。这精确实现了"停止录音后仍停留在左上角"。

## 数据加载与刷新

- **首次加载**：`RecordingPage.initState` 异步 `_loadStats()` → `getRecordingDayStats()` → `setState`。未加载完前不渲染 `StreakBadge`（避免 `0/0` 闪一下）。
- **录音完成后刷新**：在 `recordingComplete` 回调里重新 `_loadStats()`。新 entry 落库后，左上角 chip 上的数字即时 +1。

## 边界情况

| 场景 | 表现 |
|---|---|
| 无任何日记（首次使用） | 不显示数字行，显示鼓励文案「开始第一篇语音日记吧」（位置同 streak 块）。录音过程中（未保存）仍显示鼓励文案；保存后刷新即显示真实数字。 |
| 0 天连续但累计 > 0（断签） | 正常显示「连续0天，累计X天」，数字 0 同样琥珀色 |
| 大数字（累计 1000+） | 字号不变，块自动加宽，整体仍按对齐居中 |
| 加载中 | 不渲染 streak（空白） |

## 视觉规格（design tokens）

| 元素 | 规格 |
|---|---|
| 数字 | `#c8862a`，30px，`FontWeight.w800` |
| 中间行灰文字（连续 / 累计 / 天） | `#b6a48c`，15px |
| 上下行（您已经 / 录制语音日记） | `#d4c6b0`，12px，`letterSpacing: 2` |
| 逗号 | `#ddd0bd` |
| 三行行高 | `height: 1.15`，无额外 margin（紧贴） |
| 中文逗号 `，` 分隔（不用 `·`） | — |
| 「录制语音日记」右对齐到数字行右边缘 | 三行作为一个 `inline-block` 整体居中 |
| chip 态（compact）背景 | `#fff3e0` + `#f0d9a8` 边框 0.5，圆角 10，内边距 4×9 |

> 颜色先用硬编码值，落地时若与 `design_tokens.dart`（`WarmTokens`）现有 token 命名一致则复用；新增色值在 `design_tokens.dart` 补 token。

## 组件边界小结

```
RecordingPage
  ├─ initState → _loadStats() → setState
  ├─ _startRecording → _hasRecordedThisSession = true
  ├─ _onTaskData(recordingComplete) → _loadStats() 刷新
  └─ build.body = Stack(
       Column(波形 / pill / 文本 / 按钮),         // 底层，不变
       Positioned.fill → AnimatedAlign → StreakBadge(streak, total, compact),
     )

DiaryStorageService
  └─ getRecordingDayStats() → (currentStreak, totalDays)

StreakBadge (StatelessWidget)
  └─ streak / total / compact → AnimatedAlign + AnimatedScale + AnimatedOpacity
```

## 测试

### 单元测试 `getRecordingDayStats`

| 场景 | 期望 |
|---|---|
| 空集 | `(0, 0)` |
| 只有今天 | `(1, 1)` |
| 今天 + 昨天 | `(2, 2)` |
| 只有昨天（今天没录） | `(1, 1)`（向后兼容） |
| 昨天 + 前天（今天没录） | `(2, 2)` |
| 今天 + 昨天 + 断 + 前天 | `(2, 2)`（断档后不往前数） |
| 同一天多条 entry | 去重，`(1, 1)` |
| 只有前天（今天、昨天都没） | `(0, 1)`（累计 1，连续 0） |

（"今天/昨天"用注入 `DateTime.now()` 的方式 mock，或抽出"以给定 now 计算"的纯函数。）

### Widget 测试 `StreakBadge`

- `compact=false` + 非零数据：渲染三行，含「您已经」「录制语音日记」、两个琥珀数字。
- `compact=true`：前缀/后缀 opacity=0（不可见或 DOM 中 opacity 0），中间数字行可见。
- `total==0`：渲染鼓励文案「开始第一篇语音日记吧」，不渲染数字。

## 非目标（YAGNI）

- 不做跨设备同步 / 云端 streak。
- 不做成就徽章、提醒、日历热力图等延伸（仅这一行信息）。
- 不持久化 `_hasRecordedThisSession`（冷启动重置是有意为之，非缺陷）。
- 不缓存 stats 到数据库（实时计算足够快）。

## 兼容性

- 不改 schema、不改文件格式，纯增量。无数据迁移，无破坏性操作。

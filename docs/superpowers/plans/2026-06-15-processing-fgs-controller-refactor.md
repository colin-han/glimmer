# Processing FGS 统一管理类重构 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 processing FGS 的启停/延时/状态/生命周期从 `RecordingPage` 收口到 `ProcessingFgsController`（唯一管理者），从根本上解决录音静默中断后台 processing 的缺陷。

**Architecture:** controller 持有可替换的 `ProcessingFgsBackend`（封装 FlutterForegroundTask + SettingsPage 平台依赖），暴露 `isRunning`/`hasActivity`/`start`/`schedule`/`stop`/`onStopped`。`stop` 合并取消延时 + 停 FGS + 等 FGS 真停（Completer）+ 3s 超时兜底。`RecordingPage` 移除所有 processing 字段/方法，改为委托 controller。

**Tech Stack:** Flutter / flutter_foreground_task / drift / flutter_test（+ fake_async 测 timer）。

完整设计见 `docs/superpowers/specs/2026-06-15-processing-fgs-controller-refactor-design.md`。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/services/processing_fgs_backend.dart` | 新建 | 封装 FlutterForegroundTask + SettingsPage 平台依赖的接口 + 真实实现 |
| `lib/services/processing_fgs_controller.dart` | 重写 | processing FGS 唯一管理者（状态/启停/延时/结束回调） |
| `lib/pages/recording_page.dart` | 改 | 移除 processing 字段/方法，委托 controller |
| `lib/pages/diary_detail_page.dart` | 改 | `_onTaskData` 结束消息调 `controller.onStopped()` |
| `test/processing_fgs_controller_test.dart` | 新建 | controller 状态机单测（fake backend + fakeAsync） |

**不改**：`recording_processor.dart`（ProcessingTaskHandler）、`fgs_runtime.dart`（仅复用，FgsRuntime 接口不变）。

---

## Task 1: `ProcessingFgsBackend` 接口 + controller 核心（start/状态/onStopped）

**Files:**
- Create: `lib/services/processing_fgs_backend.dart`
- Modify: `lib/services/processing_fgs_controller.dart`（重写）
- Test: `test/processing_fgs_controller_test.dart`（新建）

- [ ] **Step 1: 新建 `ProcessingFgsBackend` 接口 + 真实实现**

新建 `lib/services/processing_fgs_backend.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../pages/settings_page.dart' show SettingsPage;
import 'recording_processor.dart' show processingCallback;

/// 封装 ProcessingFgsController 的平台依赖（FlutterForegroundTask + SettingsPage），
/// 便于单测注入 fake。生产用 [FlutterForegroundTaskBackend]。
abstract interface class ProcessingFgsBackend {
  /// 启动 processing FGS（initCommunicationPort + stopService + delay + startService）。
  /// 返回 true 表示成功。
  Future<bool> startProcessingFgs();

  /// 停止 FGS（FlutterForegroundTask.stopService）。
  void stopFgs();

  /// 读取用户设置的 processing 延迟秒数（<=0 表示无延迟）。
  Future<int> getProcessingDelay();
}

class FlutterForegroundTaskBackend implements ProcessingFgsBackend {
  const FlutterForegroundTaskBackend();

  @override
  Future<bool> startProcessingFgs() async {
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(milliseconds: 500));
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '正在处理',
        notificationText: '语音日记 - 处理中...',
        callback: processingCallback,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('[ProcessingFgsBackend] 启动失败: ${result.error}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[ProcessingFgsBackend] 启动异常: $e');
      return false;
    }
  }

  @override
  void stopFgs() => FlutterForegroundTask.stopService();

  @override
  Future<int> getProcessingDelay() => SettingsPage.getProcessingDelay();
}
```

> `SettingsPage` 在 `lib/pages/settings_page.dart`，用 `import 'pages/settings_page.dart'`（从 services 目录）。若路径报错，调整为实际相对路径。

- [ ] **Step 2: 写 controller 失败测试**

新建 `test/processing_fgs_controller_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/fgs_runtime.dart';
import 'package:voice_diary/services/processing_fgs_backend.dart';
import 'package:voice_diary/services/processing_fgs_controller.dart';

/// 记录调用、可控返回的 fake backend。
class _FakeBackend implements ProcessingFgsBackend {
  bool startResult = true;
  int startCalls = 0;
  int stopCalls = 0;
  int delayValue = 0;

  @override
  Future<bool> startProcessingFgs() async {
    startCalls++;
    return startResult;
  }

  @override
  void stopFgs() => stopCalls++;

  @override
  Future<int> getProcessingDelay() async => delayValue;
}

void main() {
  late _FakeBackend backend;

  setUp(() {
    backend = _FakeBackend();
    ProcessingFgsController.backend = backend;
    ProcessingFgsController.resetForTesting();
    FgsRuntime.setNone();
  });
  tearDown(() {
    ProcessingFgsController.resetForTesting();
    ProcessingFgsController.backend = const FlutterForegroundTaskBackend();
  });

  group('isRunning / hasActivity', () {
    test('初始状态：isRunning=false, hasActivity=false', () {
      expect(ProcessingFgsController.isRunning, isFalse);
      expect(ProcessingFgsController.hasActivity, isFalse);
    });
  });

  group('start', () {
    test('mode==recording 时拒绝启动，返回 false', () async {
      FgsRuntime.setRecording();
      final result = await ProcessingFgsController.start();
      expect(result, isFalse);
      expect(backend.startCalls, 0);
      expect(ProcessingFgsController.isRunning, isFalse);
    });

    test('启动成功：isRunning=true, mode=processing', () async {
      backend.startResult = true;
      final result = await ProcessingFgsController.start();
      expect(result, isTrue);
      expect(backend.startCalls, 1);
      expect(ProcessingFgsController.isRunning, isTrue);
      expect(FgsRuntime.mode, FgsMode.processing);
    });

    test('启动失败：isRunning 保持 false', () async {
      backend.startResult = false;
      final result = await ProcessingFgsController.start();
      expect(result, isFalse);
      expect(ProcessingFgsController.isRunning, isFalse);
      expect(FgsRuntime.mode, FgsMode.none);
    });

    test('已 isRunning 时幂等，不重复启动', () async {
      await ProcessingFgsController.start();
      final result = await ProcessingFgsController.start();
      expect(result, isTrue);
      expect(backend.startCalls, 1); // 只调一次
    });
  });

  group('onStopped', () {
    test('清 isRunning + mode 回 none', () async {
      await ProcessingFgsController.start();
      ProcessingFgsController.onStopped();
      expect(ProcessingFgsController.isRunning, isFalse);
      expect(FgsRuntime.mode, FgsMode.none);
    });
  });
}
```

- [ ] **Step 3: 跑测试，确认失败**

Run: `flutter test test/processing_fgs_controller_test.dart`
Expected: FAIL — `resetForTesting` / `backend` setter 未定义（controller 还没重写）。

- [ ] **Step 4: 重写 `ProcessingFgsController`**

整个 `lib/services/processing_fgs_controller.dart` 替换为：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

import 'fgs_runtime.dart';
import 'processing_fgs_backend.dart';

/// Processing FGS 的唯一管理者：启停 / 延时调度 / 状态 / 结束回调。
///
/// 状态收口到本类（isRunning 唯一真相源），RecordingPage / DiaryDetailPage
/// 都通过本类交互，避免散落的状态标志导致误判（缺陷 1 的根因）。
class ProcessingFgsController {
  ProcessingFgsController._();

  /// 平台依赖（可替换，测试注入 fake）。
  @visibleForTesting
  static ProcessingFgsBackend backend = const FlutterForegroundTaskBackend();

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  /// 有 processing 活动（在跑 或 待延时启动），供录音方判断要不要 stop + 提示。
  static bool get hasActivity => _isRunning || _scheduledTimer != null;

  static Timer? _scheduledTimer;
  static Completer<void>? _stopCompleter;

  /// 立即启动 processing FGS（唯一启动入口）。
  /// mode==recording 时拒绝（别中断录音），返回 false。
  static Future<bool> start() async {
    if (FgsRuntime.mode == FgsMode.recording) return false;
    if (_isRunning) return true; // 幂等
    final ok = await backend.startProcessingFgs();
    if (!ok) return false;
    _isRunning = true;
    FgsRuntime.setProcessing();
    return true;
  }

  /// FGS 自然结束回调（processingDone/completed/failed）或 stop 超时后调。
  /// 由 RecordingPage / DiaryDetailPage 的 _onTaskData 在收到结束消息时调用。
  static void onStopped() {
    _isRunning = false;
    FgsRuntime.setNone();
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete(); // 通知 stop() 完成
    }
  }

  /// 测试用：重置所有状态。
  @visibleForTesting
  static void resetForTesting() {
    _isRunning = false;
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    _stopCompleter = null;
  }
}
```

> `stop` / `schedule` 在后续 task 加。此刻 controller 只有 start/onStopped/状态——现有调用方（详情页 `_reanalyze`、`RecordingPage._startProcessingFgs`）仍可用（start 行为等价于原版 + 状态维护）。

- [ ] **Step 5: 跑测试，确认通过**

Run: `flutter test test/processing_fgs_controller_test.dart`
Expected: 6 tests PASS。

- [ ] **Step 6: format + analyze**

Run:
```bash
dart format lib/services/processing_fgs_backend.dart lib/services/processing_fgs_controller.dart test/processing_fgs_controller_test.dart
flutter analyze
```
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/services/processing_fgs_backend.dart lib/services/processing_fgs_controller.dart test/processing_fgs_controller_test.dart
git commit -m "$(cat <<'EOF'
refactor: ProcessingFgsController 收口状态，引入 backend 隔离平台依赖

- 新建 ProcessingFgsBackend 接口（封装 FlutterForegroundTask + SettingsPage）
- controller 重写：isRunning/hasActivity 唯一真相源，start 维护状态，onStopped 清理
- 测试用 fake backend 覆盖状态机（6 测试）
- stop/schedule 在后续 task 加

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `stop()`（合并 cancelScheduled + 停 FGS + 等真停 + 超时兜底）

**Files:**
- Modify: `lib/services/processing_fgs_controller.dart`
- Test: `test/processing_fgs_controller_test.dart`

- [ ] **Step 1: 在测试文件追加 stop 测试**

在 `test/processing_fgs_controller_test.dart` 的 `main()` 内追加 group：

```dart
  group('stop', () {
    test('无活动时立即返回，不调 stopFgs', () async {
      await ProcessingFgsController.stop();
      expect(backend.stopCalls, 0);
    });

    test('isRunning 时调 stopFgs，等 onStopped 后返回', () async {
      await ProcessingFgsController.start();
      // start 后立刻 stop：onStopped 还没调，stop 应在等
      final stopFuture = ProcessingFgsController.stop();
      expect(backend.stopCalls, 1);
      // 模拟 FGS 真停（processingDone 到达 → onStopped）
      ProcessingFgsController.onStopped();
      await stopFuture; // 应解除等待
      expect(ProcessingFgsController.isRunning, isFalse);
    });

    test('onStopped 3s 未到达 → 超时强制清理', () async {
      await ProcessingFgsController.start();
      // 不调 onStopped，靠超时
      await ProcessingFgsController.stop().timeout(
        const Duration(seconds: 5),
      );
      expect(ProcessingFgsController.isRunning, isFalse);
      expect(FgsRuntime.mode, FgsMode.none);
    });
  });
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/processing_fgs_controller_test.dart`
Expected: FAIL — `stop` 方法未定义。

- [ ] **Step 3: 实现 `stop`**

在 `lib/services/processing_fgs_controller.dart` 的 `onStopped` 之前加：

```dart
  /// 停止 processing 的一切：取消待执行延时 + 停正在跑的 FGS + 等它真停。
  /// 调用方 await 返回后，FGS 槽已释放，可立即启动录音 FGS。
  /// 幂等：无活动时立即返回。
  static Future<void> stop() async {
    _scheduledTimer?.cancel(); // 合并的 cancelScheduled
    _scheduledTimer = null;

    if (!_isRunning) return; // 没在跑（只取消了 timer 或本就无活动）→ 无需等

    _stopCompleter = Completer<void>();
    backend.stopFgs(); // 触发 FGS onDestroy → processingDone → onStopped
    await _stopCompleter!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        // 兜底：FGS 被杀没发 processingDone → 强制清理，避免录音卡死
        _isRunning = false;
        FgsRuntime.setNone();
      },
    );
    _stopCompleter = null;
  }
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/processing_fgs_controller_test.dart`
Expected: 9 tests PASS（原 6 + stop 3）。

> 超时测试会真实等待 3s，整个测试套件慢约 3s，可接受。

- [ ] **Step 5: format + analyze + Commit**

```bash
dart format lib/services/processing_fgs_controller.dart test/processing_fgs_controller_test.dart
flutter analyze
git add lib/services/processing_fgs_controller.dart test/processing_fgs_controller_test.dart
git commit -m "$(cat <<'EOF'
feat: ProcessingFgsController.stop 合并取消延时+停 FGS+等真停+超时兜底

stop 内部：cancelScheduled + stopService + 等 onStopped（Completer）+
3s 超时强制清理（覆盖 mode 卡住）。调用方 await 后 FGS 槽已释放。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `schedule()`（延时启动）

**Files:**
- Modify: `lib/services/processing_fgs_controller.dart`
- Test: `test/processing_fgs_controller_test.dart`

- [ ] **Step 1: 追加 schedule 测试**

在测试文件 import 区加：

```dart
import 'package:fake_async/fake_async.dart';
```

在 `main()` 内追加 group：

```dart
  group('schedule', () {
    test('delay<=0 且非 startup → 立即 start', () async {
      backend.delayValue = 0;
      await ProcessingFgsController.schedule();
      expect(backend.startCalls, 1);
      expect(ProcessingFgsController.isRunning, isTrue);
      expect(ProcessingFgsController.hasActivity, isTrue);
    });

    test('delay<=0 且 startup → 5s 后 start', () {
      fakeAsync((async) {
        backend.delayValue = 0;
        ProcessingFgsController.schedule(isStartup: true);
        expect(backend.startCalls, 0); // 还没到时间
        async.elapse(const Duration(seconds: 5));
        expect(backend.startCalls, 1);
      });
    });

    test('delay>0 → delay 秒后 start', () {
      fakeAsync((async) {
        backend.delayValue = 10;
        ProcessingFgsController.schedule();
        expect(backend.startCalls, 0);
        async.elapse(const Duration(seconds: 10));
        expect(backend.startCalls, 1);
      });
    });

    test('hasActivity 在 scheduled 期间为 true', () {
      fakeAsync((async) {
        backend.delayValue = 10;
        ProcessingFgsController.schedule();
        expect(ProcessingFgsController.hasActivity, isTrue); // 有待执行 timer
        async.elapse(const Duration(seconds: 10));
      });
    });
  });
```

> `fake_async` 是 Dart SDK 自带（无需加依赖），flutter_test 传递依赖。

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/processing_fgs_controller_test.dart`
Expected: FAIL — `schedule` 未定义。

- [ ] **Step 3: 实现 `schedule`**

在 `lib/services/processing_fgs_controller.dart` 的 `stop` 之后、`onStopped` 之前加：

```dart
  /// 延时启动（录音后 / app 启动恢复）。读 backend.getProcessingDelay。
  /// isStartup=true 时 delay<=0 默认 5s；否则立即（delay<=0 直接 start）。
  static Future<void> schedule({bool isStartup = false}) async {
    _scheduledTimer?.cancel();
    final delay = await backend.getProcessingDelay();
    final seconds = (delay <= 0) ? (isStartup ? 5 : 0) : delay;
    if (seconds == 0) {
      await start();
      return;
    }
    _scheduledTimer = Timer(Duration(seconds: seconds), () {
      _scheduledTimer = null;
      start(); // start 内部检查 mode==recording，延时到期时若用户在录音则不启动
    });
  }
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/processing_fgs_controller_test.dart`
Expected: 13 tests PASS（原 9 + schedule 4）。

- [ ] **Step 5: format + analyze + Commit**

```bash
dart format lib/services/processing_fgs_controller.dart test/processing_fgs_controller_test.dart
flutter analyze
git add lib/services/processing_fgs_controller.dart test/processing_fgs_controller_test.dart
git commit -m "$(cat <<'EOF'
feat: ProcessingFgsController.schedule 延时启动（录音后/启动恢复）

读 backend.getProcessingDelay；delay<=0 时 startup 默认 5s、否则立即。
timer 回调调 start（内部 mode==recording 拒绝）。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `RecordingPage` 收口（移除 processing 字段/方法，委托 controller）

**Files:**
- Modify: `lib/pages/recording_page.dart`

> UI + 平台代码，无单测。靠 `flutter analyze` + Task 6 手动验证。

- [ ] **Step 1: 移除 processing 字段**

删除 `lib/pages/recording_page.dart` 第 43-45 行的字段块：

```dart
  // Processing FGS 状态跟踪
  Timer? _processingDelayTimer;
  bool _isProcessingFgsRunning = false;
```

（整块删除。`dart:async` 的 `Timer` import 若仅此处用到可保留——`schedule` 的 timer 已移到 controller，但 `StreamController` 等仍用 dart:async，保留 import。）

- [ ] **Step 2: `initState` 改用 controller.schedule**

把 `initState`（约 47-53 行）：

```dart
  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _refreshProcessingCount();
    _scheduleStartupRecovery();
  }
```

改为：

```dart
  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _refreshProcessingCount();
    ProcessingFgsController.schedule(isStartup: true);
  }
```

- [ ] **Step 3: `dispose` 移除 timer cancel**

把 `dispose`（约 55-63 行）：

```dart
  @override
  void dispose() {
    _processingDelayTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _amplitudeController.close();
    _realtimeScrollController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
```

改为（删除 `_processingDelayTimer?.cancel();` 一行）：

```dart
  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _amplitudeController.close();
    _realtimeScrollController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
```

- [ ] **Step 4: `_onTaskData` 的结束消息改调 `onStopped`**

把 `_onTaskData` 的 `recordingComplete` / `processingDone` / `completed|failed` 三个 case 改为委托 controller。

`recordingComplete` case（约 99-102 行）：

```dart
      case 'recordingComplete':
        // 录音完成，延迟启动 Processing FGS
        FgsRuntime.setNone();
        _scheduleProcessingFgs();
```

改为：

```dart
      case 'recordingComplete':
        // 录音完成，延迟启动 Processing FGS
        ProcessingFgsController.schedule();
```

`processingDone` case（约 103-110 行）：

```dart
      case 'processingDone':
        // Processing FGS 结束（无论是否有条目被处理）
        FgsRuntime.setNone();
        _isProcessingFgsRunning = false;
        _refreshProcessingCount();
        if (_state == RecordingState.processing) {
          _doStartRecording();
        }
```

改为：

```dart
      case 'processingDone':
        // Processing FGS 结束（无论是否有条目被处理）
        ProcessingFgsController.onStopped();
        _refreshProcessingCount();
```

`completed|failed` case（约 111-120 行）：

```dart
      case 'completed':
      case 'failed':
        // 处理完成或失败时刷新 Badge 数量
        FgsRuntime.setNone();
        _isProcessingFgsRunning = false;
        _refreshProcessingCount();
        if (_state == RecordingState.processing) {
          // 用户在等待 Processing FGS 停止后启动录音
          _doStartRecording();
        }
```

改为：

```dart
      case 'completed':
      case 'failed':
        // 处理完成或失败时刷新 Badge 数量
        ProcessingFgsController.onStopped();
        _refreshProcessingCount();
```

> 移除了 `if (_state == processing) _doStartRecording()`——这部分由 `_startRecording` 里的 `await ProcessingFgsController.stop()` 接管（Step 5）。

- [ ] **Step 5: `_startRecording` 改用 controller**

把 `_startRecording`（约 189-202 行）：

```dart
  Future<void> _startRecording() async {
    // 取消待执行的延迟定时器（用户在延迟窗口内重新录音）
    _processingDelayTimer?.cancel();
    _processingDelayTimer = null;

    if (_isProcessingFgsRunning) {
      // Processing FGS 正在运行 → 显示加载状态，停止 Processing FGS，等待回调后自动启动录音
      setState(() => _state = RecordingState.processing);
      FlutterForegroundTask.stopService();
      return;
    }

    await _doStartRecording();
  }
```

改为：

```dart
  Future<void> _startRecording() async {
    // 有 processing 活动（在跑 or 待延时启动）→ 停掉并等它停稳
    if (ProcessingFgsController.hasActivity) {
      setState(() => _state = RecordingState.processing);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已暂停后台处理，录音结束后自动继续')),
      );
      await ProcessingFgsController.stop(); // 内部取消 timer + 停 FGS + 等停（含超时兜底）
    }
    await _doStartRecording();
  }
```

- [ ] **Step 6: 删除被收口的方法**

删除 `_scheduleStartupRecovery`（约 252-255 行）、`_scheduleStartupRecoveryWithDelay`（约 257-266 行）、`_scheduleProcessingFgs`（约 268-281 行）、`_startProcessingFgs`（约 283-291 行）这 4 个方法（整段删除）。

- [ ] **Step 7: format + analyze**

Run:
```bash
dart format lib/pages/recording_page.dart
flutter analyze
```
Expected: No issues found.（若有 `dart:async` 的 `Timer` unused 警告，检查是否还有其他用到——`StreamController`、`Duration` 等仍在用，import 通常保留；若 analyze 报 unused 则删除 `import 'dart:async';`。）

- [ ] **Step 8: Commit**

```bash
git add lib/pages/recording_page.dart
git commit -m "$(cat <<'EOF'
refactor: RecordingPage 移除 processing 状态，全部委托 ProcessingFgsController

- 移除 _isProcessingFgsRunning / _processingDelayTimer 字段
- 移除 _startProcessingFgs / _scheduleProcessingFgs / _scheduleStartupRecovery
- initState 改调 controller.schedule(isStartup: true)
- _onTaskData 结束消息改调 controller.onStopped()
- _startRecording 改用 controller.hasActivity + await controller.stop()
  （stop 内部等 FGS 真停，不再 return 等回调）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `DiaryDetailPage` `_onTaskData` 接入 `controller.onStopped()`

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: import controller**

在 `lib/pages/diary_detail_page.dart` 顶部 import 区确认有（Task 4 阶段已加过，若无则加）：

```dart
import '../services/processing_fgs_controller.dart';
```

> 详情页之前为 `_reanalyze` 已 import 此文件。确认存在即可。

- [ ] **Step 2: `_onTaskData` 三处结束消息改调 `onStopped`**

把 `_onTaskData`（约 100-115 行）的三处 `FgsRuntime.setNone()` 替换为 `ProcessingFgsController.onStopped()`（onStopped 内部已含 setNone + 清 isRunning + 解锁 stop）。

`completed` 分支：

```dart
    } else if (type == 'completed' && mounted) {
      // 处理完成，加载最终内容
      FgsRuntime.setNone();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
```

改为：

```dart
    } else if (type == 'completed' && mounted) {
      // 处理完成，加载最终内容
      ProcessingFgsController.onStopped();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
```

`processingDone` 分支：

```dart
    } else if (type == 'processingDone' && mounted) {
      // FGS 停止，标记为非活跃
      FgsRuntime.setNone();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
```

改为：

```dart
    } else if (type == 'processingDone' && mounted) {
      // FGS 停止，标记为非活跃
      ProcessingFgsController.onStopped();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
```

`failed` 分支：

```dart
    } else if (type == 'failed' && mounted) {
      // 处理失败：重置 mode + 显示失败横幅
      FgsRuntime.setNone();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
```

改为：

```dart
    } else if (type == 'failed' && mounted) {
      // 处理失败：重置 mode + 显示失败横幅
      ProcessingFgsController.onStopped();
      setState(() => _isActivelyProcessing = false);
      _loadContent();
```

- [ ] **Step 3: format + analyze + Commit**

```bash
dart format lib/pages/diary_detail_page.dart
flutter analyze
git add lib/pages/diary_detail_page.dart
git commit -m "$(cat <<'EOF'
refactor: DiaryDetailPage _onTaskData 结束消息走 controller.onStopped()

completed/processingDone/failed 三处改调 ProcessingFgsController.onStopped()
（内部含 setNone + 清 isRunning + 解锁 stop），与 RecordingPage 一致。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 全量验证与收尾

- [ ] **Step 1: 全量 analyze**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 2: 全量 test**

Run: `flutter test`
Expected: 所有测试 PASS（含新增的 `processing_fgs_controller_test` 13 个 + 既有测试）。

- [ ] **Step 3: 手动验证清单**

构建到设备（`./scripts/run_dev.sh` 或 `flutter run`），逐项验证：

- [ ] **核心修复**：详情页点「重新分析」→ processing 跑 → 立即回 RecordingPage 点录音 → toast「已暂停后台处理」→ 录音正常启动 → 录音结束后被中断的重新分析自动续跑（结果更新）
- [ ] **回归·正常录音**：录音 → 录音后处理流程正常（badge 计数、详情页结果）
- [ ] **回归·录音中重新分析**：录音中进详情页点重新分析 → toast「已加入处理队列」→ 录音结束后处理
- [ ] **回归·启动恢复**：杀 app 后有未完成 processing 条目 → 重启后延时自动恢复处理
- [ ] **延时设置生效**：SettingsPage 设置 processing delay → 录音后按该延时启动
- [ ] **失败重试仍工作**：failed 日记点「重新处理」→ 正常（_retry 未动）

- [ ] **Step 4: 若有 format 偏差补提交**

```bash
dart format .
flutter analyze
git add -A
git commit -m "style: 收尾格式化

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

否则跳过。

---

## Self-Review

（执行前由计划作者完成）

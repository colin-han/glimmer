# Processing FGS 统一管理类重构 — 设计文档

- 日期：2026-06-15
- 状态：待评审
- 关联缺陷：`docs/superpowers/bugs/2026-06-14-recording-interrupts-processing.md`（缺陷 1）

## 背景与问题

缺陷 1（录音静默中断后台 processing）的根因不是某一行代码，而是**架构问题**：processing FGS 的启停和状态散落在三处，没有单一真相源。

| 位置 | 维护的状态/逻辑 |
|---|---|
| `RecordingPage._isProcessingFgsRunning` | 局部标志，只跟踪"RecordingPage 自己启动的 processing" |
| `RecordingPage._startProcessingFgs` | 启动逻辑，与 `ProcessingFgsController.start` **重复** |
| `RecordingPage._scheduleProcessingFgs` / `_scheduleStartupRecovery` / `_processingDelayTimer` | 延时启动，散落在 RecordingPage |
| `FgsRuntime.mode` | 全局 mode，更新点分散在 RecordingPage + 详情页，与 `_isProcessingFgsRunning` 不同步 |

后果：RecordingPage 既管 recording 又维护一份 processing 状态，详情页（`ProcessingFgsController`）又管另一份，两者不同步 → 录音启动时误判"没有 processing 在跑" → 静默中断重新分析。

## 目标

把 processing FGS 的**启停 + 延时调度 + 状态 + 生命周期**全部收口到 `ProcessingFgsController` 一处。`RecordingPage` 不再维护任何 processing 状态。从架构上消除"状态散落"，而非在现有实现上打补丁。

## 范围

### 做

- `ProcessingFgsController` 升级为 processing FGS 唯一管理者（启动/延时启动/停止/状态/结束回调）
- `stop()` 合并 `cancelScheduled` + 停 FGS + 等待 FGS 真停 + 超时兜底
- `RecordingPage` 移除所有 processing 相关字段与方法，改为委托 controller
- 详情页 FGS 结束消息也走 `controller.onStopped()`
- `mode` 卡住（缺陷 8）的兜底融入 `stop()` 超时

### 不做（独立缺陷，另行处理）

- 缺陷 2（`_retry` 并发）：与 processing FGS 管理无关，独立修复
- 缺陷 3（`_retry` 不更新 status）：`_retry` 自身问题，独立修复
- 次要 #5（`_retry` setState 无 mounted）：独立修复

## 设计

### `ProcessingFgsController` 完整接口

```dart
class ProcessingFgsController {
  ProcessingFgsController._();

  // ─── 状态（唯一真相源，对外只读）──
  static bool _isRunning = false;
  static bool get isRunning => _isRunning;
  /// 有 processing 活动（在跑 或 待延时启动），供录音方判断要不要 stop + 提示
  static bool get hasActivity => _isRunning || _scheduledTimer != null;

  static Timer? _scheduledTimer;       // 延时启动 timer（内部管）
  static Completer<void>? _stopCompleter;  // stop 等待 onStopped 的桥

  // ─── 启动 ───

  /// 立即启动 processing FGS（唯一启动入口）。
  /// mode==recording 时拒绝（别中断录音），返回 false。
  static Future<bool> start() async {
    if (FgsRuntime.mode == FgsMode.recording) return false;
    if (_isRunning) return true;            // 已在跑，幂等
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.stopService();   // 清理可能残留的 FGS
      await Future.delayed(const Duration(milliseconds: 500));
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: '正在处理',
        notificationText: '语音日记 - 处理中...',
        callback: processingCallback,
      );
      if (result is ServiceRequestFailure) return false;
      _isRunning = true;
      FgsRuntime.setProcessing();
      return true;
    } catch (e) {
      debugPrint('[ProcessingFgsController] 启动异常: $e');
      return false;                          // 不抛给调用方
    }
  }

  /// 延时启动（录音后 / app 启动恢复）。读 SettingsPage.getProcessingDelay。
  /// isStartup=true 时 delay<=0 默认 5s；否则立即（delay<=0 直接 start）。
  static Future<void> schedule({bool isStartup = false}) async {
    _scheduledTimer?.cancel();
    final delay = await SettingsPage.getProcessingDelay();
    final seconds = (delay <= 0) ? (isStartup ? 5 : 0) : delay;
    if (seconds == 0) {
      await start();
      return;
    }
    _scheduledTimer = Timer(Duration(seconds: seconds), () {
      _scheduledTimer = null;
      start();   // start 内部检查 mode==recording，延时到期时若用户在录音则不启动
    });
  }

  // ─── 停止 ───

  /// 停止 processing 的一切：取消待执行延时 + 停正在跑的 FGS + 等它真停。
  /// 调用方 await 返回后，FGS 槽已释放，可立即启动录音 FGS。
  /// 幂等：无活动时立即返回。
  static Future<void> stop() async {
    _scheduledTimer?.cancel();         // 合并的 cancelScheduled
    _scheduledTimer = null;

    if (!_isRunning) return;           // 没在跑（只是取消了 timer，或本就无活动）→ 无需等

    _stopCompleter = Completer<void>();
    FlutterForegroundTask.stopService();   // 触发 FGS onDestroy → processingDone → onStopped
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

  // ─── 结束回调 ───

  /// FGS 自然结束（processingDone/completed/failed）或 stop 超时后调。
  /// 由 RecordingPage / DiaryDetailPage 的 _onTaskData 在收到结束消息时调用。
  static void onStopped() {
    _isRunning = false;
    FgsRuntime.setNone();
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete();      // 通知 stop() 完成
    }
  }
}
```

### `stop()` 一举解决三件事

1. **合并 cancelScheduled**：内部取消 `_scheduledTimer`，调用方不再需要单独方法
2. **封装「等 FGS 停」**：调用方 `await stop()` 后 FGS 槽已释放，不再需要"`setState processing` + return 等 processingDone 回调"的老模式
3. **mode 卡住兜底融入**：超时（3s）强制清理，processing FGS 被 OS 杀无回调时不再卡死录音

### `FgsRuntime` 角色重新划分

`FgsRuntime.mode`（none/recording/processing）仍是统一视图，但维护职责对称划分：

- `mode == recording`：由 **RecordingPage** 维护（启动录音 setRecording，结束 setNone）——供 `controller.start()` 判断"别中断录音"
- `mode == processing`：由 **controller** 维护（start 设、onStopped 设 none）——与 `isRunning` 同步

互斥判断对称：
- 启动 processing 前查 `FgsRuntime.mode == recording`
- 启动 recording 前查 `ProcessingFgsController.hasActivity`（在跑或待延时）

### `RecordingPage` 收口

移除所有 processing 相关字段与方法，改为委托 controller：

| RecordingPage 现有 | 改为 |
|---|---|
| `bool _isProcessingFgsRunning` 字段 | **移除** → 读 `ProcessingFgsController.isRunning` / `hasActivity` |
| `_startProcessingFgs()` 内联逻辑 | **移除** → `ProcessingFgsController.start()` |
| `_scheduleProcessingFgs()` | **移除** → `ProcessingFgsController.schedule()` |
| `_scheduleStartupRecovery()` / `_scheduleStartupRecoveryWithDelay()` | **移除** → `ProcessingFgsController.schedule(isStartup: true)` |
| `Timer? _processingDelayTimer` 字段 | **移除** → controller 内部 `_scheduledTimer` |
| `_startRecording` 里 `_processingDelayTimer?.cancel()` | → `await ProcessingFgsController.stop()`（幂等，含取消 timer） |
| `_onTaskData` 的 processingDone/completed/failed 分支 | → 调 `ProcessingFgsController.onStopped()`（不再承担"触发 _doStartRecording"职责） |

`_startRecording` 简化为：

```dart
Future<void> _startRecording() async {
  // 有 processing 活动（在跑 or 待延时启动）→ 停掉并等它停稳
  if (ProcessingFgsController.hasActivity) {
    setState(() => _state = RecordingState.processing);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已暂停后台处理，录音结束后自动继续')),
    );
    await ProcessingFgsController.stop();   // 内部取消 timer + 停 FGS + 等停（含超时兜底）
  }
  await _doStartRecording();
}
```

不再有"return 等 processingDone 回调"——`stop` 已 await 等完。

### 详情页收口

- `_reanalyze` 调 `ProcessingFgsController.start()`（已是这样，不变）
- `_onTaskData` 的 `completed` / `processingDone` / `failed` 分支：调 `ProcessingFgsController.onStopped()`（与 RecordingPage 一致，任一页面收到结束消息都通知 controller 清理状态）

## 数据流：录音中断重新分析

1. 详情页点重新分析 → `controller.start()` → processing FGS 跑（`isRunning=true`, `mode=processing`）
2. 用户切到 RecordingPage 点录音 → `_startRecording` 检查 `hasActivity==true` → setState processing + toast
3. `await controller.stop()` → 取消 timer + stopService → 等 `onStopped`（processingDone 到达任一页面触发）
4. `stop` 返回 → `_doStartRecording()` 启动录音 FGS（槽已释放）
5. 录音完成 → `controller.schedule()` → 延时后 `start()` → `getPendingEntries` 拾取被中断的重新分析 entry（靠 `processingStage` 续跑）

## 风险与权衡

- **录音优先取舍**：processing 被中断会浪费正在进行的 ASR/LLM API 调用，但录音是用户即时操作不应被后台任务阻塞几十秒。靠 `processingStage` 续跑不丢数据。已与用户确认。
- **超时 3s**：太短可能误判慢 onDestroy，太长用户干等。3s 是折中（onDestroy 通常秒级）。
- **Completer 跨 callback**：`stop` 与 `onStopped` 都在 main isolate，Completer 可靠工作；`onStopped` 有 `isCompleted` 防护避免重复 complete。
- **`schedule` 的 timer 回调不检查 RecordingPage._state**：改用 `start()` 内部的 `mode==recording` 检查（对称），controller 不依赖 RecordingPage 内部状态。

## 测试策略

- **单元测试** `ProcessingFgsController` 状态机（用 fake/stub 隔离 `FlutterForegroundTask` 平台调用）：
  - `start` 在 `mode==recording` 时返回 false、不启动
  - `start` 幂等（已 isRunning 时直接返回 true）
  - `stop` 取消 timer + 调 stopService + 等 onStopped
  - `stop` 超时兜底（onStopped 不调时，3s 后强制清理）
  - `schedule` 的 timer 触发后调 start
  - `hasActivity` 在 isRunning / scheduled / 都没有 时的值
- **手动验证**（FGS + 真实处理无法自动化）：
  - 重新分析中录音 → toast + 录音正常启动 + 录音后重新分析续跑
  - 正常录音 → 录音后处理不受影响（回归）
  - 录音中重新分析 → 拒绝 + 入队（回归）
- `flutter analyze` + `flutter test` 确保无回归

## 开放问题

- `FlutterForegroundTask.stopService()` 触发 onDestroy 到 main isolate 收到 processingDone 的延迟实测值，用于校准超时（3s 是否够）。实现时若发现 onDestroy 普遍 >3s，调大。
- 是否需要把 recording FGS 的管理也对称收口到一个 controller（本次不做，recording 与 UI 耦合紧，留待未来）。

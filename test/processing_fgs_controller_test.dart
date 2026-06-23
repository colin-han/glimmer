import 'package:fake_async/fake_async.dart';
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
  bool isServiceRunningValue = false;

  @override
  Future<bool> startProcessingFgs() async {
    startCalls++;
    return startResult;
  }

  @override
  void stopFgs() => stopCalls++;

  @override
  Future<int> getProcessingDelay() async => delayValue;

  @override
  Future<bool> isServiceRunning() async => isServiceRunningValue;
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
    test('mode==recording 时拒绝启动，返回 false（同步）', () {
      FgsRuntime.setRecording();
      final result = ProcessingFgsController.start();
      expect(result, isFalse);
      expect(backend.startCalls, 0);
      expect(ProcessingFgsController.isRunning, isFalse);
      expect(ProcessingFgsController.hasActivity, isFalse);
    });

    test('启动成功：start() 同步返回 true，Timer fire 后 isRunning=true', () {
      fakeAsync((async) {
        backend.startResult = true;
        final result = ProcessingFgsController.start();
        expect(result, isTrue);
        // start() 后同步设 _isStarting=true（hasActivity=true），但还没 _isRunning
        expect(ProcessingFgsController.isRunning, isFalse);
        expect(ProcessingFgsController.hasActivity, isTrue);
        expect(backend.startCalls, 0); // Timer 还没 fire
        expect(FgsRuntime.mode, FgsMode.processing); // 同步设
        async.elapse(const Duration(milliseconds: 500)); // Timer fire
        async.flushMicrotasks(); // 让 Timer 回调里的 await 完成
        expect(backend.startCalls, 1);
        expect(ProcessingFgsController.isRunning, isTrue);
        expect(ProcessingFgsController.hasActivity, isTrue);
        expect(FgsRuntime.mode, FgsMode.processing);
      });
    });

    test(
      '启动失败：Timer fire → startProcessingFgs false → isRunning=false, mode=none',
      () {
        fakeAsync((async) {
          backend.startResult = false;
          final result = ProcessingFgsController.start();
          expect(result, isTrue); // start() 仍同步返回 true（已进入 starting）
          expect(ProcessingFgsController.hasActivity, isTrue);
          async.elapse(const Duration(milliseconds: 500));
          async.flushMicrotasks();
          expect(backend.startCalls, 1);
          expect(ProcessingFgsController.isRunning, isFalse);
          expect(ProcessingFgsController.hasActivity, isFalse);
          expect(FgsRuntime.mode, FgsMode.none); // 启动失败回退
        });
      },
    );

    test('已 _isStarting 时幂等：第二次 start() 不再注册 Timer', () {
      fakeAsync((async) {
        backend.startResult = true;
        final first = ProcessingFgsController.start();
        expect(first, isTrue);
        expect(backend.startCalls, 0); // Timer 还没 fire
        final second = ProcessingFgsController.start(); // 幂等
        expect(second, isTrue);
        expect(backend.startCalls, 0); // 仍只等同一个 Timer
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(backend.startCalls, 1); // 只调一次
      });
    });

    test('已 _isRunning 时幂等：第二次 start() 不重复启动', () {
      fakeAsync((async) {
        backend.startResult = true;
        ProcessingFgsController.start();
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(backend.startCalls, 1);
        // 此时 _isRunning=true，再 start() 幂等
        final second = ProcessingFgsController.start();
        expect(second, isTrue);
        expect(backend.startCalls, 1); // 仍只一次
      });
    });

    test('FGS 已在跑（isServiceRunning）→ 标记 _isRunning，不调 startProcessingFgs', () {
      fakeAsync((async) {
        backend.isServiceRunningValue = true;
        final result = ProcessingFgsController.start();
        expect(result, isTrue);
        expect(backend.startCalls, 0); // Timer 还没 fire
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        // 不调 startProcessingFgs（避免其内部 stopService 中断）
        expect(backend.startCalls, 0);
        expect(ProcessingFgsController.isRunning, isTrue);
        expect(FgsRuntime.mode, FgsMode.processing);
      });
    });
  });

  group('onStopped', () {
    test('清 isRunning + mode 回 none', () {
      fakeAsync((async) {
        ProcessingFgsController.start();
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(ProcessingFgsController.isRunning, isTrue);
        ProcessingFgsController.onStopped();
        expect(ProcessingFgsController.isRunning, isFalse);
        expect(FgsRuntime.mode, FgsMode.none);
      });
    });
  });

  group('stop', () {
    test('无活动时立即返回，不调 stopFgs', () {
      fakeAsync((async) {
        ProcessingFgsController.stop();
        async.flushMicrotasks();
        expect(backend.stopCalls, 0);
      });
    });

    test('start 后 stop（Timer 期间）→ cancel，FGS 不启动（竞态修复核心）', () {
      fakeAsync((async) {
        ProcessingFgsController.start();
        expect(ProcessingFgsController.hasActivity, isTrue); // _isStarting=true
        // 还没到 500ms，Timer 未 fire
        async.elapse(const Duration(milliseconds: 100));
        expect(backend.startCalls, 0);
        // stop() cancel Timer（FGS 不启动）
        ProcessingFgsController.stop();
        async.flushMicrotasks(); // 让 stop 的 await 完成
        expect(
          ProcessingFgsController.hasActivity,
          isFalse,
        ); // _isStarting=false
        expect(backend.startCalls, 0); // startProcessingFgs 没调
        expect(backend.stopCalls, 0); // FGS 没启动，不需要 stopFgs
        expect(FgsRuntime.mode, FgsMode.none); // cancel 时回退
        // 推进过原 Timer 时间，确认 Timer 已被 cancel（不再 fire）
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(backend.startCalls, 0); // 仍然没调
        expect(ProcessingFgsController.isRunning, isFalse);
      });
    });

    test('isRunning 时调 stopFgs，等 onStopped 后返回', () {
      fakeAsync((async) {
        ProcessingFgsController.start();
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(ProcessingFgsController.isRunning, isTrue);
        // start 后 stop：onStopped 还没调，stop 应在等
        final stopFuture = ProcessingFgsController.stop();
        expect(backend.stopCalls, 1);
        // 模拟 FGS 真停（processingDone 到达 → onStopped）
        ProcessingFgsController.onStopped();
        async.flushMicrotasks();
        stopFuture; // 应已解除等待
        async.flushMicrotasks();
        expect(ProcessingFgsController.isRunning, isFalse);
      });
    });

    test('onStopped 3s 未到达 → 超时强制清理', () {
      fakeAsync((async) {
        ProcessingFgsController.start();
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(ProcessingFgsController.isRunning, isTrue);
        // 不调 onStopped，靠超时
        ProcessingFgsController.stop();
        async.elapse(const Duration(seconds: 5)); // 推进过 3s 超时
        async.flushMicrotasks();
        expect(ProcessingFgsController.isRunning, isFalse);
        expect(FgsRuntime.mode, FgsMode.none);
      });
    });
  });

  group('schedule', () {
    test('delay<=0 且非 startup → 立即 start（_isStarting）', () {
      fakeAsync((async) {
        backend.delayValue = 0;
        ProcessingFgsController.schedule();
        async.flushMicrotasks(); // 让 await getProcessingDelay 完成、start() 同步生效
        // start() 同步设 _isStarting=true，Timer 还没 fire
        expect(ProcessingFgsController.isRunning, isFalse);
        expect(ProcessingFgsController.hasActivity, isTrue); // _isStarting
        async.elapse(const Duration(milliseconds: 500)); // start Timer fire
        async.flushMicrotasks();
        expect(backend.startCalls, 1);
        expect(ProcessingFgsController.isRunning, isTrue);
        expect(ProcessingFgsController.hasActivity, isTrue);
      });
    });

    test('delay<=0 且 startup → 5s 后 start', () {
      fakeAsync((async) {
        backend.delayValue = 0;
        ProcessingFgsController.schedule(isStartup: true);
        async.flushMicrotasks(); // 让 await getProcessingDelay 完成、timer 注册
        expect(backend.startCalls, 0); // 还没到时间
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks(); // 让 scheduledTimer 的 start() Timer 注册
        expect(backend.startCalls, 0); // start 只设 _isStarting，还没 fire
        async.elapse(
          const Duration(milliseconds: 500),
        ); // start 的 500ms Timer fire
        async.flushMicrotasks();
        expect(backend.startCalls, 1);
      });
    });

    test('delay>0 → delay 秒后 start', () {
      fakeAsync((async) {
        backend.delayValue = 10;
        ProcessingFgsController.schedule();
        async.flushMicrotasks(); // 让 await getProcessingDelay 完成、timer 注册
        expect(backend.startCalls, 0);
        async.elapse(const Duration(seconds: 10));
        async
            .flushMicrotasks(); // scheduledTimer 的 start() 同步执行 → 注册 500ms Timer
        expect(backend.startCalls, 0); // start 只设 _isStarting，还没 fire
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(backend.startCalls, 1);
      });
    });

    test('hasActivity 在 scheduled 期间为 true', () {
      fakeAsync((async) {
        backend.delayValue = 10;
        ProcessingFgsController.schedule();
        async.flushMicrotasks(); // 让 await getProcessingDelay 完成、timer 注册
        expect(
          ProcessingFgsController.hasActivity,
          isTrue,
        ); // 有待执行 scheduledTimer
        async.elapse(const Duration(seconds: 10));
      });
    });

    test('hasActivity 在 start 500ms 窗口（_isStarting）期间为 true', () {
      fakeAsync((async) {
        backend.delayValue = 0;
        ProcessingFgsController.schedule();
        async.flushMicrotasks(); // start() 同步执行 → _isStarting=true
        expect(ProcessingFgsController.hasActivity, isTrue); // _isStarting=true
        expect(ProcessingFgsController.isRunning, isFalse);
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(ProcessingFgsController.isRunning, isTrue);
      });
    });
  });
}

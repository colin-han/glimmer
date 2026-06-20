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

    test('FGS 已在跑（isServiceRunning）→ 标记状态返回 true，不重复启动', () async {
      backend.isServiceRunningValue = true;
      final result = await ProcessingFgsController.start();
      expect(result, isTrue);
      expect(
        backend.startCalls,
        0,
      ); // 不调 startProcessingFgs（避免其内部 stopService 中断）
      expect(ProcessingFgsController.isRunning, isTrue);
      expect(FgsRuntime.mode, FgsMode.processing);
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
      await ProcessingFgsController.stop().timeout(const Duration(seconds: 5));
      expect(ProcessingFgsController.isRunning, isFalse);
      expect(FgsRuntime.mode, FgsMode.none);
    });
  });

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
        async.flushMicrotasks(); // 让 await getProcessingDelay 完成、timer 注册
        expect(backend.startCalls, 0); // 还没到时间
        async.elapse(const Duration(seconds: 5));
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
        expect(backend.startCalls, 1);
      });
    });

    test('hasActivity 在 scheduled 期间为 true', () {
      fakeAsync((async) {
        backend.delayValue = 10;
        ProcessingFgsController.schedule();
        async.flushMicrotasks(); // 让 await getProcessingDelay 完成、timer 注册
        expect(ProcessingFgsController.hasActivity, isTrue); // 有待执行 timer
        async.elapse(const Duration(seconds: 10));
      });
    });
  });
}

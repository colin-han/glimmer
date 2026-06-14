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

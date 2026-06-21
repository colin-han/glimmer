import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voice_diary/main.dart';
import 'package:voice_diary/services/database/app_database.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/processing_fgs_backend.dart';
import 'package:voice_diary/services/processing_fgs_controller.dart';
import 'package:voice_diary/services/processing_task_store.dart';

/// 不触发真实 FGS 平台调用的 fake backend（widget 启动测试用）。
class _NoopBackend implements ProcessingFgsBackend {
  @override
  Future<bool> startProcessingFgs() async => false;
  @override
  void stopFgs() {}
  @override
  Future<int> getProcessingDelay() async => 0;
  @override
  Future<bool> isServiceRunning() async => false;
}

void main() {
  testWidgets('应用能正常启动', (WidgetTester tester) async {
    // RecordingPage initState 订阅全局 processingTaskStore，需预先初始化。
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    ProcessingFgsController.backend = _NoopBackend();
    ProcessingFgsController.resetForTesting();
    processingTaskStore = ProcessingTaskStore(
      storage: DiaryStorageService.forTesting(db),
    );

    await tester.pumpWidget(const VoiceDiaryApp());

    expect(find.text('语音日记'), findsOneWidget);

    // pump 一下让 schedule(isStartup) 的异步（getProcessingDelay）解析完，
    // 创建延迟 Timer；随后 resetForTesting 取消它，避免 "Timer is still pending"。
    await tester.pump();
    ProcessingFgsController.resetForTesting();
    ProcessingFgsController.backend = const FlutterForegroundTaskBackend();

    await db.close();
  });
}

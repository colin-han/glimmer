import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'design_tokens.dart';
import 'pages/recording_page.dart';
import 'services/diary_storage_service.dart';
import 'services/migration_service.dart';
import 'services/processing_task_store.dart';
import 'services/storage_migration_service.dart';
import 'services/tos_upload_service.dart';

/// 全局 task store（main isolate 单例）。UI/入口通过此访问。
late final ProcessingTaskStore processingTaskStore;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'recording_service',
      channelName: '录音服务',
      channelDescription: '语音日记录音服务正在运行',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
    ),
  );
  final migrationService = StorageMigrationService();
  await migrationService.runMigrations();

  // 全局 task store 初始化：从 DB 加载活跃 task + 注册 FGS 消息回调
  processingTaskStore = ProcessingTaskStore(storage: DiaryStorageService());
  await processingTaskStore.loadFromDb();
  processingTaskStore.startListening();

  // 异步执行历史 WAV → OGG + TOS 迁移（不阻塞 UI）
  _runTosMigrationIfNeeded();

  runApp(const VoiceDiaryApp());
}

Future<void> _runTosMigrationIfNeeded() async {
  if (await MigrationService.isMigrated()) return;
  try {
    final storage = DiaryStorageService();
    final tos = TosUploadService();
    final migration = MigrationService(storage, tos);
    final count = await migration.migrateUnuploadedEntries();
    if (count > 0) {
      debugPrint('[迁移] 完成: 迁移了 $count 条日记');
    }
    tos.close();
  } catch (e) {
    debugPrint('[迁移] 跳过: $e');
  }
}

class VoiceDiaryApp extends StatelessWidget {
  const VoiceDiaryApp({super.key});

  static const _isDev = bool.fromEnvironment('dev', defaultValue: false);
  static const _worktree = String.fromEnvironment('worktree');

  @override
  Widget build(BuildContext context) {
    final watermark = _worktree.isNotEmpty ? 'DEV $_worktree' : 'DEV';
    return MaterialApp(
      title: '语音日记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: WarmTokens.seedColor,
        useMaterial3: true,
      ),
      home: const RecordingPage(),
      builder: (context, child) {
        if (!_isDev || child == null) return child!;
        return Stack(
          children: [
            child,
            Positioned(
              left: 16,
              bottom: 32,
              child: IgnorePointer(
                child: Text(
                  watermark,
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: WarmTokens.warmMuted.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

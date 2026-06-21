import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';
import 'models/processing_task.dart';
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
  _runDailySummaryIfNeeded();

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
  final yesterday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 1));
  final key = dateKey(yesterday);
  return lastGenDate == key ? null : key;
}

/// 异步执行：每天首次打开 app 时自动为「昨天」生成每日总结。
/// 仿 _runTosMigrationIfNeeded，fire-and-forget，不阻塞 UI。
///
/// 通过 task 表判断是否已生成（不再依赖 DailySummaries.status）：
/// - 若该 date 已有 completed/active task，跳过（更新 gen date）
/// - 否则入队 daily_summary task
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

    // 查 task 表：若该 date 已有 task（completed 不重复生成；active 不重复入队），跳过
    final existingTask = await storage.getLatestProcessingTask(target);
    if (existingTask != null) {
      await prefs.setString('last_daily_summary_gen_date', target);
      return;
    }

    // 入队 daily_summary task（store 内部会触发 FGS）
    await processingTaskStore.enqueueTask(
      taskType: TaskType.dailySummary,
      refId: target,
    );

    await prefs.setString('last_daily_summary_gen_date', target);
  } catch (e) {
    debugPrint('[DailySummary] 启动钩子跳过: $e');
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

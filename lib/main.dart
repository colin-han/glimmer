import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'pages/recording_page.dart';
import 'services/storage_migration_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');
  final migrationService = StorageMigrationService();
  await migrationService.runMigrations();
  runApp(const VoiceDiaryApp());
}

class VoiceDiaryApp extends StatelessWidget {
  const VoiceDiaryApp({super.key});

  static const _isDev = bool.fromEnvironment('dev', defaultValue: false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '语音日记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
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
                  'DEV',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey.withValues(alpha: 0.08),
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

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');
  runApp(const VoiceDiaryApp());
}

class VoiceDiaryApp extends StatelessWidget {
  const VoiceDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '语音日记',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('语音日记 v1')),
      ),
    );
  }
}

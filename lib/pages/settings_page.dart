import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_title.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const _ttsEnabledKey = 'tts_enabled';

  static Future<bool> isTtsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ttsEnabledKey) ?? true;
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _ttsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await SettingsPage.isTtsEnabled();
    if (mounted) {
      setState(() => _ttsEnabled = enabled);
    }
  }

  Future<void> _toggleTts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsPage._ttsEnabledKey, value);
    setState(() => _ttsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(title: '设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('语音播报'),
            subtitle: const Text('录音完成后播报处理结果'),
            value: _ttsEnabled,
            onChanged: _toggleTts,
          ),
        ],
      ),
    );
  }
}

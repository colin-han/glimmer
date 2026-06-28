import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_title.dart';
import 'api_log_page.dart';
import 'favorite_locations_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const _ttsEnabledKey = 'tts_enabled';
  static const _processingDelayKey = 'processing_delay_seconds';

  static Future<bool> isTtsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ttsEnabledKey) ?? true;
  }

  /// 获取处理延迟秒数，默认 5 秒。0 表示立即处理。
  static Future<int> getProcessingDelay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_processingDelayKey) ?? 5;
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _ttsEnabled = true;
  double _processingDelay = 5;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await SettingsPage.isTtsEnabled();
    final delay = await SettingsPage.getProcessingDelay();
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _ttsEnabled = enabled;
        _processingDelay = delay.toDouble();
        _version = '${info.version} (${info.buildNumber})';
      });
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
          ListTile(
            title: const Text('处理延迟'),
            subtitle: Text(
              _processingDelay <= 0
                  ? '录音结束后立即处理'
                  : '录音结束后 ${_processingDelay.toInt()} 秒开始处理',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('0秒', style: Theme.of(context).textTheme.bodySmall),
                Expanded(
                  child: Slider(
                    value: _processingDelay,
                    min: 0,
                    max: 30,
                    divisions: 30,
                    label: '${_processingDelay.toInt()} 秒',
                    onChanged: (value) {
                      setState(() => _processingDelay = value);
                    },
                    onChangeEnd: (value) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt(
                        SettingsPage._processingDelayKey,
                        value.toInt(),
                      );
                    },
                  ),
                ),
                Text('30秒', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('常用位置'),
            subtitle: const Text('家、公司等，录音接近时显示名称'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FavoriteLocationsPage(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(title: const Text('版本'), subtitle: Text(_version)),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('API 日志'),
            subtitle: const Text('查看最近的处理日志与消费记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ApiLogPage()));
            },
          ),
        ],
      ),
    );
  }
}

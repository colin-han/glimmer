import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../services/api_log_service.dart';
import '../services/database/app_database.dart';

/// API 日志查看页面（后门入口，从日记列表页搜索 "log" 进入）。
class ApiLogPage extends StatefulWidget {
  const ApiLogPage({super.key});

  @override
  State<ApiLogPage> createState() => _ApiLogPageState();
}

class _ApiLogPageState extends State<ApiLogPage> {
  final _logService = ApiLogService();
  List<ApiLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await _logService.getRecentLogs(limit: 300);
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 日志'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Text('暂无日志',
                      style: TextStyle(
                          fontSize: 15, color: WarmTokens.warmMuted)))
              : RefreshIndicator(
                  onRefresh: _loadLogs,
                  color: WarmTokens.warmAmber,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return _buildLogCard(_logs[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildLogCard(ApiLog log) {
    final time = DateTime.fromMillisecondsSinceEpoch(log.createdAt);
    final timeStr =
        '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

    final isSuccess = log.status == 'success';
    final isError = log.status == 'error';
    final isStep = log.apiType == 'step';

    // 状态颜色
    final statusColor = isError
        ? WarmTokens.failedAccent
        : isSuccess
            ? Colors.green
            : WarmTokens.warmMuted;

    // 背景
    final bgColor = isError
        ? WarmTokens.failedBg
        : WarmTokens.warmCardBg;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WarmTokens.warmDivider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：时间 + 状态
          Row(
            children: [
              Text(timeStr,
                  style: TextStyle(
                      fontSize: 11,
                      color: WarmTokens.warmMuted,
                      fontFamily: 'monospace')),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(log.status,
                    style: TextStyle(
                        fontSize: 10,
                        color: statusColor,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第二行：apiType · step
          Row(
            children: [
              Text(isStep ? 'STEP' : log.apiType,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: WarmTokens.warmBrown,
                      fontFamily: 'monospace')),
              Text(' · ',
                  style: TextStyle(
                      fontSize: 12, color: WarmTokens.warmMuted)),
              Text(log.step,
                  style: TextStyle(
                      fontSize: 12,
                      color: WarmTokens.warmBrown,
                      fontFamily: 'monospace')),
              if (log.durationMs != null) ...[
                Text(' · ',
                    style: TextStyle(
                        fontSize: 12, color: WarmTokens.warmMuted)),
                Text('${log.durationMs}ms',
                    style: TextStyle(
                        fontSize: 12,
                        color: WarmTokens.warmMuted,
                        fontFamily: 'monospace')),
              ],
            ],
          ),
          // 第三行：diaryId（缩写）
          const SizedBox(height: 2),
          Text('diary: ${_shortId(log.diaryId)}',
              style: TextStyle(
                  fontSize: 10,
                  color: WarmTokens.warmMuted,
                  fontFamily: 'monospace')),
          // Token 用量
          if (log.promptTokens != null || log.completionTokens != null) ...[
            const SizedBox(height: 2),
            Text(
                'tokens: ${log.promptTokens ?? 0}↑ ${log.completionTokens ?? 0}↓'
                '${log.cachedTokens != null ? ' (cached: ${log.cachedTokens})' : ''}'
                '${log.reasoningTokens != null ? ' (reasoning: ${log.reasoningTokens})' : ''}',
                style: TextStyle(
                    fontSize: 10,
                    color: WarmTokens.warmMuted,
                    fontFamily: 'monospace')),
          ],
          // 费用
          if (log.estimatedCost != null) ...[
            const SizedBox(height: 2),
            Text('cost: ¥${log.estimatedCost!.toStringAsFixed(4)}',
                style: TextStyle(
                    fontSize: 10,
                    color: WarmTokens.warmAmber,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500)),
          ],
          // 音频时长
          if (log.audioDurationSeconds != null) ...[
            const SizedBox(height: 2),
            Text('audio: ${log.audioDurationSeconds}s',
                style: TextStyle(
                    fontSize: 10,
                    color: WarmTokens.warmMuted,
                    fontFamily: 'monospace')),
          ],
          // 错误信息
          if (log.errorMessage != null) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: WarmTokens.failedAccent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(log.errorMessage!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      color: WarmTokens.failedAccent,
                      fontFamily: 'monospace')),
            ),
          ],
        ],
      ),
    );
  }

  String _shortId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}…';
  }
}

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
      appBar: AppBar(title: const Text('API 日志')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
          ? Center(
              child: Text(
                '暂无日志',
                style: TextStyle(fontSize: 15, color: WarmTokens.warmMuted),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadLogs,
              color: WarmTokens.warmAmber,
              child: _buildGroupedList(),
            ),
    );
  }

  /// 按天分组渲染，每组标题显示该组总预估消费额
  Widget _buildGroupedList() {
    // 按日期分组（_logs 已按时间倒序，分组与组内均保持倒序）
    final groups = <String, List<ApiLog>>{};
    for (final log in _logs) {
      final time = DateTime.fromMillisecondsSinceEpoch(log.createdAt);
      final key =
          '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(log);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: groups.entries.expand((group) {
        final totalCost = group.value.fold<double>(
          0,
          (sum, l) => sum + (l.estimatedCost ?? 0),
        );
        return [
          _buildGroupHeader(group.key, totalCost),
          ...group.value.map((log) => _buildLogCard(log)),
        ];
      }).toList(),
    );
  }

  Widget _buildGroupHeader(String dateKey, double totalCost) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8, left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: WarmTokens.warmAmber,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDateLabel(dateKey),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WarmTokens.warmMuted,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          if (totalCost > 0)
            Text(
              '合计 ¥${totalCost.toStringAsFixed(4)}',
              style: TextStyle(
                fontSize: 11,
                color: WarmTokens.warmAmber,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateLabel(String dateKey) {
    final parts = dateKey.split('-');
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(date).inDays;
    final monthDay = '${date.month}月${date.day}日';
    if (diff == 0) return '今天（$monthDay）';
    if (diff == 1) return '昨天（$monthDay）';
    return monthDay;
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
    final bgColor = isError ? WarmTokens.failedBg : WarmTokens.warmCardBg;

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
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: WarmTokens.warmMuted,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.status,
                  style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第二行：apiType · step
          Row(
            children: [
              Text(
                isStep ? 'STEP' : log.apiType,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: WarmTokens.warmBrown,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                ' · ',
                style: TextStyle(fontSize: 12, color: WarmTokens.warmMuted),
              ),
              Text(
                log.step,
                style: TextStyle(
                  fontSize: 12,
                  color: WarmTokens.warmBrown,
                  fontFamily: 'monospace',
                ),
              ),
              if (log.durationMs != null) ...[
                Text(
                  ' · ',
                  style: TextStyle(fontSize: 12, color: WarmTokens.warmMuted),
                ),
                Text(
                  '${log.durationMs}ms',
                  style: TextStyle(
                    fontSize: 12,
                    color: WarmTokens.warmMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
          // 第三行：diaryId（缩写）
          const SizedBox(height: 2),
          Text(
            'diary: ${_shortId(log.diaryId)}',
            style: TextStyle(
              fontSize: 10,
              color: WarmTokens.warmMuted,
              fontFamily: 'monospace',
            ),
          ),
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
                fontFamily: 'monospace',
              ),
            ),
          ],
          // 费用
          if (log.estimatedCost != null) ...[
            const SizedBox(height: 2),
            Text(
              'cost: ¥${log.estimatedCost!.toStringAsFixed(4)}',
              style: TextStyle(
                fontSize: 10,
                color: WarmTokens.warmAmber,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          // 音频时长
          if (log.audioDurationSeconds != null) ...[
            const SizedBox(height: 2),
            Text(
              'audio: ${log.audioDurationSeconds}s',
              style: TextStyle(
                fontSize: 10,
                color: WarmTokens.warmMuted,
                fontFamily: 'monospace',
              ),
            ),
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
              child: Text(
                log.errorMessage!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: WarmTokens.failedAccent,
                  fontFamily: 'monospace',
                ),
              ),
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

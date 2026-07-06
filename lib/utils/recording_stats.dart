/// 录音统计：根据有录音的时间点集合 + 当前时间，计算连续天数与累计天数。
///
/// - [totalDays]：所有录音按本地日期去重后的天数。
/// - [currentStreak]：含今天且向后兼容昨天——
///   集合含「今天」则从今天起往前数；今天没有、含「昨天」则从昨天起往前数；
///   都没有则返回 0。
library;

/// 把 [dt] 折算为本地日期的 'yyyy-MM-dd' key（与具体时分秒无关）。
String _dateKey(DateTime dt) {
  final l = dt.toLocal();
  return '${l.year}-'
      '${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')}';
}

/// 计算录音统计。
///
/// 纯函数（不查 DB、不读系统时钟），便于单测。`now` 由调用方注入。
({int currentStreak, int totalDays}) computeRecordingStats({
  required Iterable<DateTime> recordingTimes,
  required DateTime now,
}) {
  final days = <String>{};
  for (final t in recordingTimes) {
    days.add(_dateKey(t));
  }
  final totalDays = days.length;
  if (totalDays == 0) return (currentStreak: 0, totalDays: 0);

  final nowLocal = now.toLocal();
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final anchor = days.contains(_dateKey(today))
      ? today
      : (days.contains(_dateKey(yesterday)) ? yesterday : null);

  if (anchor == null) return (currentStreak: 0, totalDays: totalDays);

  var streak = 0;
  var cur = anchor;
  while (days.contains(_dateKey(cur))) {
    streak++;
    cur = cur.subtract(const Duration(days: 1));
  }
  return (currentStreak: streak, totalDays: totalDays);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/utils/recording_stats.dart';

void main() {
  // 固定 now，所有用例围绕 2026-07-06（周二）。
  final now = DateTime(2026, 7, 6, 12, 0);

  ({int currentStreak, int totalDays}) stats(List<DateTime> times) =>
      computeRecordingStats(recordingTimes: times, now: now);

  test('空集合 → (0, 0)', () {
    expect(stats([]), (currentStreak: 0, totalDays: 0));
  });

  test('只有今天 → (1, 1)', () {
    expect(stats([DateTime(2026, 7, 6, 8, 0)]), (
      currentStreak: 1,
      totalDays: 1,
    ));
  });

  test('今天 + 昨天 → (2, 2)', () {
    expect(stats([DateTime(2026, 7, 6), DateTime(2026, 7, 5)]), (
      currentStreak: 2,
      totalDays: 2,
    ));
  });

  test('只有昨天（今天没录）→ 向后兼容，(1, 1)', () {
    expect(stats([DateTime(2026, 7, 5)]), (currentStreak: 1, totalDays: 1));
  });

  test('昨天 + 前天（今天没录）→ (2, 2)', () {
    expect(stats([DateTime(2026, 7, 5), DateTime(2026, 7, 4)]), (
      currentStreak: 2,
      totalDays: 2,
    ));
  });

  test('今天 + 昨天 + 断档 + 前天 → 断档后不往前数，(2, 2)', () {
    expect(
      stats([DateTime(2026, 7, 6), DateTime(2026, 7, 5), DateTime(2026, 7, 3)]),
      (currentStreak: 2, totalDays: 3),
    );
  });

  test('同一天多条 entry → 去重，(1, 1)', () {
    expect(stats([DateTime(2026, 7, 6, 8), DateTime(2026, 7, 6, 20)]), (
      currentStreak: 1,
      totalDays: 1,
    ));
  });

  test('只有前天（今/昨都没）→ 累计 1，连续 0', () {
    expect(stats([DateTime(2026, 7, 4)]), (currentStreak: 0, totalDays: 1));
  });

  test('长连续：今天起往前 5 天 → (5, 5)', () {
    expect(
      stats([
        DateTime(2026, 7, 6),
        DateTime(2026, 7, 5),
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 3),
        DateTime(2026, 7, 2),
      ]),
      (currentStreak: 5, totalDays: 5),
    );
  });
}

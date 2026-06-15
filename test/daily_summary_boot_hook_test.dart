import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/main.dart';

void main() {
  group('dailySummaryTargetDate', () {
    test('今天未为昨天生成 → 返回昨天 key', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      expect(dailySummaryTargetDate(lastGenDate: null, now: now), '2026-06-13');
    });

    test('今天已为昨天生成（last == 昨天）→ 返回 null', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      expect(
        dailySummaryTargetDate(lastGenDate: '2026-06-13', now: now),
        isNull,
      );
    });

    test('last 是更早日期（多天未打开）→ 仍只返回昨天，不回填更早', () {
      final now = DateTime(2026, 6, 14, 10, 30);
      expect(
        dailySummaryTargetDate(lastGenDate: '2026-06-10', now: now),
        '2026-06-13',
      );
    });

    test('跨年/跨月正确', () {
      final now = DateTime(2026, 1, 2, 0, 5);
      expect(dailySummaryTargetDate(lastGenDate: null, now: now), '2026-01-01');
    });
  });

  test('dateKey 零填充', () {
    expect(dateKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(dateKey(DateTime(2026, 6, 13)), '2026-06-13');
  });
}

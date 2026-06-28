import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/daily_summary.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/weather_condition.dart';

DiaryEntry _entry({
  required DateTime createdAt,
  String? weatherIcon,
  String? weatherText,
  String? temperature,
  String? locationName,
}) {
  return DiaryEntry(
    id: createdAt.millisecondsSinceEpoch.toString(),
    title: 't',
    folderPath: '/x',
    durationSeconds: 0,
    createdAt: createdAt,
    weatherIcon: weatherIcon,
    weatherText: weatherText,
    temperature: temperature,
    locationName: locationName,
  );
}

void main() {
  group('buildDayFullText', () {
    test('多篇按顺序拼接，分隔标记含序号与 HH:mm', () {
      final text = buildDayFullText([
        (createdAt: DateTime(2026, 6, 13, 9, 5), text: '早上好'),
        (createdAt: DateTime(2026, 6, 13, 14, 30), text: '下午开会了'),
      ]);
      expect(text, contains('### 第 1 段 · 09:05'));
      expect(text, contains('早上好'));
      expect(text, contains('### 第 2 段 · 14:30'));
      expect(text, contains('下午开会了'));
    });

    test('空列表返回空字符串', () {
      expect(buildDayFullText(const []), '');
    });

    test('去除片段首尾空白', () {
      final text = buildDayFullText([
        (createdAt: DateTime(2026, 6, 13, 9), text: '  带空白  '),
      ]);
      expect(text, contains('带空白'));
      expect(text, isNot(contains('  带空白')));
    });
  });

  group('shouldDegrade', () {
    test('等于阈值不降级（> 才降级）', () {
      expect(shouldDegrade('a' * 25000), isFalse);
    });
    test('超过阈值降级', () {
      expect(shouldDegrade('a' * 25001), isTrue);
    });
  });

  group('buildDaySummariesText', () {
    test('降级拼接各篇 summary，含标题', () {
      final text = buildDaySummariesText([
        (createdAt: DateTime(2026, 6, 13, 9), title: '早晨', summary: '晨跑'),
      ]);
      expect(text, contains('### 第 1 段 · 09:00（早晨）'));
      expect(text, contains('晨跑'));
    });
  });

  group('aggregateDayWeather', () {
    test('天气取众数 icon、温度取 min~max、地点取众数', () {
      final agg = aggregateDayWeather([
        _entry(
          createdAt: DateTime(2026, 6, 13, 9),
          weatherIcon: '104',
          weatherText: '阴',
          temperature: '18',
          locationName: '海淀区',
        ),
        _entry(
          createdAt: DateTime(2026, 6, 13, 14),
          weatherIcon: '104',
          weatherText: '阴',
          temperature: '25',
          locationName: '海淀区',
        ),
        _entry(
          createdAt: DateTime(2026, 6, 13, 20),
          weatherIcon: '100',
          weatherText: '晴',
          temperature: '22',
          locationName: '朝阳区',
        ),
      ]);
      expect(
        agg.condition,
        WeatherCondition.overcast,
      ); // 104 出现 2 次 > 100 的 1 次
      expect(agg.tempMin, 18);
      expect(agg.tempMax, 25);
      expect(agg.tempDisplay, '18°~25°');
      expect(agg.locationName, '海淀区');
      expect(agg.isEmpty, isFalse);
    });

    test('温度全相同只显示单值', () {
      final agg = aggregateDayWeather([
        _entry(createdAt: DateTime(2026, 6, 13, 9), temperature: '24'),
        _entry(createdAt: DateTime(2026, 6, 13, 14), temperature: '24'),
      ]);
      expect(agg.tempDisplay, '24°');
    });

    test('无任何天气数据时 isEmpty', () {
      final agg = aggregateDayWeather([
        _entry(createdAt: DateTime(2026, 6, 13, 9)),
      ]);
      expect(agg.isEmpty, isTrue);
      expect(agg.tempDisplay, '');
    });

    test('非数字温度被忽略', () {
      final agg = aggregateDayWeather([
        _entry(createdAt: DateTime(2026, 6, 13, 9), temperature: 'abc'),
        _entry(createdAt: DateTime(2026, 6, 13, 14), temperature: '20'),
      ]);
      expect(agg.tempMin, 20);
      expect(agg.tempMax, 20);
    });

    test('display 含 emoji 标签', () {
      final agg = aggregateDayWeather([
        _entry(
          createdAt: DateTime(2026, 6, 13, 9),
          weatherIcon: '104',
          temperature: '20',
          locationName: '海淀区',
        ),
      ]);
      expect(agg.display, '海淀区  ☁️ 阴  20°');
    });
  });

  group('DailySummaryData', () {
    test('toJson / fromJson 往返保持字段', () {
      final original = DailySummaryData(
        version: 1,
        date: '2026-06-13',
        title: '标题',
        summary: '## 正文',
        outline: '播报',
        sourceEntryIds: const ['uuid1', 'uuid2'],
        degraded: true,
      );
      final restored = DailySummaryData.fromJson(original.toJson());
      expect(restored.version, 1);
      expect(restored.date, '2026-06-13');
      expect(restored.title, '标题');
      expect(restored.summary, '## 正文');
      expect(restored.outline, '播报');
      expect(restored.sourceEntryIds, ['uuid1', 'uuid2']);
      expect(restored.degraded, isTrue);
    });

    test('fromJson 容错：缺字段降级为默认值', () {
      final restored = DailySummaryData.fromJson({});
      expect(restored.version, 1);
      expect(restored.title, '');
      expect(restored.degraded, isFalse);
      expect(restored.sourceEntryIds, isEmpty);
    });
  });
}

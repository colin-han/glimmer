import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/daily_summary.dart';

void main() {
  test('DayWeatherSummary.display 拼接地点/emoji/温度', () {
    const w = DayWeatherSummary(
      locationName: '海淀区',
      weatherIcon: '104',
      weatherText: '阴',
      tempMin: 18,
      tempMax: 25,
    );
    expect(w.display, contains('海淀区'));
    expect(w.display, contains('☁️')); // weatherEmoji('104') == '☁️'
    expect(w.display, contains('18°~25°'));
  });

  test('display 无数据返回空字符串', () {
    const w = DayWeatherSummary();
    expect(w.display, '');
  });
}

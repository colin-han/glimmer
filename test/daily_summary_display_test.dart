import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/daily_summary.dart';
import 'package:voice_diary/models/weather_condition.dart';

void main() {
  test('DayWeatherSummary.display 拼接地点/emoji标签/温度', () {
    const w = DayWeatherSummary(
      locationName: '海淀区',
      condition: WeatherCondition.overcast,
      tempMin: 18,
      tempMax: 25,
    );
    expect(w.display, '海淀区  ☁️ 阴  18°~25°');
  });

  test('display 无数据返回空字符串', () {
    const w = DayWeatherSummary();
    expect(w.display, '');
  });
}

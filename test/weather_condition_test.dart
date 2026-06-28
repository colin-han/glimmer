import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/weather_condition.dart';

void main() {
  group('fromQweatherCode', () {
    // (和风代码, 期望枚举)
    const cases = <(String, WeatherCondition)>[
      // sunny
      ('100', WeatherCondition.sunny), ('150', WeatherCondition.sunny),
      // cloudy
      ('101', WeatherCondition.cloudy), ('102', WeatherCondition.cloudy),
      ('103', WeatherCondition.cloudy), ('151', WeatherCondition.cloudy),
      // overcast
      ('104', WeatherCondition.overcast),
      // shower
      ('300', WeatherCondition.shower),
      // thunder
      ('301', WeatherCondition.thunder), ('302', WeatherCondition.thunder),
      ('303', WeatherCondition.thunder), ('304', WeatherCondition.thunder),
      // drizzle
      ('305', WeatherCondition.drizzle), ('309', WeatherCondition.drizzle),
      // rain
      ('306', WeatherCondition.rain), ('307', WeatherCondition.rain),
      ('308', WeatherCondition.rain), ('310', WeatherCondition.rain),
      ('311', WeatherCondition.rain), ('312', WeatherCondition.rain),
      ('313', WeatherCondition.rain), ('314', WeatherCondition.rain),
      ('315', WeatherCondition.rain), ('399', WeatherCondition.rain),
      // lightSnow
      ('400', WeatherCondition.lightSnow), ('404', WeatherCondition.lightSnow),
      ('405', WeatherCondition.lightSnow), ('406', WeatherCondition.lightSnow),
      ('407', WeatherCondition.lightSnow), ('408', WeatherCondition.lightSnow),
      // heavySnow
      ('401', WeatherCondition.heavySnow), ('402', WeatherCondition.heavySnow),
      ('403', WeatherCondition.heavySnow), ('409', WeatherCondition.heavySnow),
      ('499', WeatherCondition.heavySnow),
      // fog
      ('500', WeatherCondition.fog), ('501', WeatherCondition.fog),
      ('502', WeatherCondition.fog), ('503', WeatherCondition.fog),
      ('504', WeatherCondition.fog), ('507', WeatherCondition.fog),
      ('508', WeatherCondition.fog), ('509', WeatherCondition.fog),
      ('510', WeatherCondition.fog), ('511', WeatherCondition.fog),
      ('512', WeatherCondition.fog), ('513', WeatherCondition.fog),
      ('514', WeatherCondition.fog), ('515', WeatherCondition.fog),
      // unknown
      ('900', WeatherCondition.unknown), ('901', WeatherCondition.unknown),
      ('999', WeatherCondition.unknown),
    ];

    for (final (code, expected) in cases) {
      test('和风代码 $code -> $expected', () {
        expect(WeatherCondition.fromQweatherCode(code), expected);
      });
    }

    test('表外未知代码 -> unknown', () {
      expect(
        WeatherCondition.fromQweatherCode('777'),
        WeatherCondition.unknown,
      );
      expect(WeatherCondition.fromQweatherCode(''), WeatherCondition.unknown);
    });
  });

  group('fromAmapText', () {
    test('晴/多云/阴', () {
      expect(WeatherCondition.fromAmapText('晴'), WeatherCondition.sunny);
      expect(WeatherCondition.fromAmapText('多云'), WeatherCondition.cloudy);
      expect(WeatherCondition.fromAmapText('少云'), WeatherCondition.cloudy);
      expect(WeatherCondition.fromAmapText('阴'), WeatherCondition.overcast);
    });

    test('雷阵雨优先于阵雨/雨（顺序验证）', () {
      expect(WeatherCondition.fromAmapText('雷阵雨'), WeatherCondition.thunder);
      expect(WeatherCondition.fromAmapText('阵雨'), WeatherCondition.shower);
      expect(WeatherCondition.fromAmapText('小雨'), WeatherCondition.drizzle);
      expect(WeatherCondition.fromAmapText('毛毛雨'), WeatherCondition.drizzle);
      expect(WeatherCondition.fromAmapText('中雨'), WeatherCondition.rain);
      expect(WeatherCondition.fromAmapText('大雨'), WeatherCondition.rain);
      expect(WeatherCondition.fromAmapText('暴雨'), WeatherCondition.rain);
      expect(WeatherCondition.fromAmapText('冻雨'), WeatherCondition.rain);
    });

    test('雨夹雪优先于雨/雪单独命中', () {
      expect(WeatherCondition.fromAmapText('雨夹雪'), WeatherCondition.lightSnow);
      expect(WeatherCondition.fromAmapText('雨雪'), WeatherCondition.lightSnow);
    });

    test('雪细分', () {
      expect(WeatherCondition.fromAmapText('小雪'), WeatherCondition.lightSnow);
      expect(WeatherCondition.fromAmapText('小到中雪'), WeatherCondition.lightSnow);
      expect(WeatherCondition.fromAmapText('中雪'), WeatherCondition.heavySnow);
      expect(WeatherCondition.fromAmapText('大雪'), WeatherCondition.heavySnow);
      expect(WeatherCondition.fromAmapText('中到大雪'), WeatherCondition.heavySnow);
      expect(WeatherCondition.fromAmapText('暴雪'), WeatherCondition.heavySnow);
    });

    test('雾霾沙尘', () {
      expect(WeatherCondition.fromAmapText('雾'), WeatherCondition.fog);
      expect(WeatherCondition.fromAmapText('霾'), WeatherCondition.fog);
      expect(WeatherCondition.fromAmapText('扬沙'), WeatherCondition.fog);
      expect(WeatherCondition.fromAmapText('浮尘'), WeatherCondition.fog);
    });

    test('未知文字 -> unknown', () {
      expect(WeatherCondition.fromAmapText(''), WeatherCondition.unknown);
      expect(WeatherCondition.fromAmapText('龙卷风'), WeatherCondition.unknown);
    });
  });

  group('displayPart', () {
    test('全部枚举拼接 emoji + 标签', () {
      const cases = <(WeatherCondition, String)>[
        (WeatherCondition.sunny, '☀️ 晴'),
        (WeatherCondition.cloudy, '🌤️ 多云'),
        (WeatherCondition.overcast, '☁️ 阴'),
        (WeatherCondition.drizzle, '🌦️ 小雨'),
        (WeatherCondition.rain, '🌧️ 中大雨'),
        (WeatherCondition.shower, '🌦️ 阵雨'),
        (WeatherCondition.thunder, '⛈️ 雷雨'),
        (WeatherCondition.lightSnow, '🌨️ 小雪'),
        (WeatherCondition.heavySnow, '❄️ 大雪'),
        (WeatherCondition.fog, '🌫️ 雾霾沙尘'),
      ];
      for (final (condition, expected) in cases) {
        expect(
          condition.displayPart,
          expected,
          reason: '${condition.name}.displayPart',
        );
      }
    });
    test('unknown 为空字符串', () {
      expect(WeatherCondition.unknown.displayPart, '');
    });
  });
}

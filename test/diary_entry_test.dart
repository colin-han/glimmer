import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/models/weather_condition.dart';

DiaryEntry _entry({
  WeatherCondition? weatherCondition,
  String? weatherIcon,
  String? temperature,
  String? locationName,
}) {
  return DiaryEntry(
    id: '1',
    title: 't',
    folderPath: '/x',
    durationSeconds: 0,
    createdAt: DateTime(2026, 6, 28),
    weatherCondition: weatherCondition,
    weatherIcon: weatherIcon,
    temperature: temperature,
    locationName: locationName,
  );
}

void main() {
  group('effectiveCondition', () {
    test('优先 weatherCondition', () {
      final e = _entry(
        weatherCondition: WeatherCondition.rain,
        weatherIcon: '104',
      );
      expect(e.effectiveCondition, WeatherCondition.rain);
    });

    test('weatherCondition 为空时从 weatherIcon 兜底', () {
      expect(
        _entry(weatherIcon: '104').effectiveCondition,
        WeatherCondition.overcast,
      );
      expect(
        _entry(weatherIcon: '305').effectiveCondition,
        WeatherCondition.drizzle,
      );
    });

    test('两者都空返回 null', () {
      expect(_entry().effectiveCondition, isNull);
    });
  });

  group('copyWith', () {
    test('copyWith 保留 weatherCondition（不丢失）', () {
      final e = _entry(weatherCondition: WeatherCondition.rain);
      final updated = e.copyWith(title: '新标题');
      expect(updated.title, '新标题');
      expect(updated.weatherCondition, WeatherCondition.rain);
    });
  });

  group('weatherDisplay', () {
    test('地名 + emoji标签 + 温度', () {
      final e = _entry(
        locationName: '北京大学',
        weatherCondition: WeatherCondition.shower,
        temperature: '24',
      );
      expect(e.weatherDisplay, '北京大学  🌦️ 阵雨  24°');
    });

    test('unknown 不显示天气片段', () {
      final e = _entry(
        weatherCondition: WeatherCondition.unknown,
        temperature: '24',
      );
      expect(e.weatherDisplay, '24°');
    });

    test('无天气数据返回空', () {
      expect(_entry().weatherDisplay, '');
    });
  });
}

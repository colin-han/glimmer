/// 统一天气状况枚举（DB 与 UI 唯一表示）。
///
/// 由和风数字代码（历史数据）或高德天气文字（实时查询）映射而来。
/// `unknown` 不参与显示（emoji/label 为空）。
enum WeatherCondition {
  sunny, // 晴 ☀️
  cloudy, // 多云 🌤️
  overcast, // 阴 ☁️
  drizzle, // 小雨 🌦️
  rain, // 中大雨 🌧️
  shower, // 阵雨 🌦️
  thunder, // 雷雨 ⛈️
  lightSnow, // 小雪 🌨️
  heavySnow, // 大雪 ❄️
  fog, // 雾霾沙尘 🌫️
  unknown; // 无法识别（不显示）

  String get emoji => switch (this) {
    WeatherCondition.sunny => '☀️',
    WeatherCondition.cloudy => '🌤️',
    WeatherCondition.overcast => '☁️',
    WeatherCondition.drizzle => '🌦️',
    WeatherCondition.rain => '🌧️',
    WeatherCondition.shower => '🌦️',
    WeatherCondition.thunder => '⛈️',
    WeatherCondition.lightSnow => '🌨️',
    WeatherCondition.heavySnow => '❄️',
    WeatherCondition.fog => '🌫️',
    WeatherCondition.unknown => '',
  };

  String get label => switch (this) {
    WeatherCondition.sunny => '晴',
    WeatherCondition.cloudy => '多云',
    WeatherCondition.overcast => '阴',
    WeatherCondition.drizzle => '小雨',
    WeatherCondition.rain => '中大雨',
    WeatherCondition.shower => '阵雨',
    WeatherCondition.thunder => '雷雨',
    WeatherCondition.lightSnow => '小雪',
    WeatherCondition.heavySnow => '大雪',
    WeatherCondition.fog => '雾霾沙尘',
    WeatherCondition.unknown => '',
  };

  /// 显示片段：「emoji 标签」；unknown 为空。
  String get displayPart =>
      (emoji.isEmpty && label.isEmpty) ? '' : '$emoji $label';

  /// 和风天气数字代码 → 枚举（migration + 运行时兜底）。未知代码归 unknown。
  static WeatherCondition fromQweatherCode(String code) =>
      _qweatherMap[code] ?? WeatherCondition.unknown;

  /// 高德天气文字 → 枚举（有序关键字匹配，先具体后通用）。
  static WeatherCondition fromAmapText(String text) {
    if (text.contains('雷')) return WeatherCondition.thunder;
    if (text.contains('雨夹雪') || text.contains('雨雪')) {
      return WeatherCondition.lightSnow;
    }
    if (text.contains('阵雨')) return WeatherCondition.shower;
    if (text.contains('毛毛雨') || text.contains('小雨')) {
      return WeatherCondition.drizzle;
    }
    if (text.contains('冻雨')) return WeatherCondition.rain;
    if (text.contains('中雨') || text.contains('大雨') || text.contains('暴雨')) {
      return WeatherCondition.rain;
    }
    if (text.contains('雨')) return WeatherCondition.rain;
    if (text.contains('大雪') || text.contains('暴雪') || text.contains('中到大雪')) {
      return WeatherCondition.heavySnow;
    }
    if (text.contains('小到中雪')) return WeatherCondition.lightSnow;
    if (text.contains('中雪')) return WeatherCondition.heavySnow;
    if (text.contains('小雪') || text.contains('阵雪')) {
      return WeatherCondition.lightSnow;
    }
    if (text.contains('雪')) return WeatherCondition.lightSnow;
    if (text.contains('雾') ||
        text.contains('霾') ||
        text.contains('沙') ||
        text.contains('尘') ||
        text.contains('浮')) {
      return WeatherCondition.fog;
    }
    if (text.contains('晴')) return WeatherCondition.sunny;
    if (text.contains('多云') || text.contains('少云')) {
      return WeatherCondition.cloudy;
    }
    if (text.contains('阴')) return WeatherCondition.overcast;
    return WeatherCondition.unknown;
  }

  static const Map<String, WeatherCondition> _qweatherMap = {
    '100': WeatherCondition.sunny,
    '150': WeatherCondition.sunny,
    '101': WeatherCondition.cloudy,
    '102': WeatherCondition.cloudy,
    '103': WeatherCondition.cloudy,
    '151': WeatherCondition.cloudy,
    '104': WeatherCondition.overcast,
    '300': WeatherCondition.shower,
    '301': WeatherCondition.thunder,
    '302': WeatherCondition.thunder,
    '303': WeatherCondition.thunder,
    '304': WeatherCondition.thunder,
    '305': WeatherCondition.drizzle,
    '309': WeatherCondition.drizzle,
    '306': WeatherCondition.rain,
    '307': WeatherCondition.rain,
    '308': WeatherCondition.rain,
    '310': WeatherCondition.rain,
    '311': WeatherCondition.rain,
    '312': WeatherCondition.rain,
    '313': WeatherCondition.rain,
    '314': WeatherCondition.rain,
    '315': WeatherCondition.rain,
    '399': WeatherCondition.rain,
    '400': WeatherCondition.lightSnow,
    '404': WeatherCondition.lightSnow,
    '405': WeatherCondition.lightSnow,
    '406': WeatherCondition.lightSnow,
    '407': WeatherCondition.lightSnow,
    '408': WeatherCondition.lightSnow,
    '401': WeatherCondition.heavySnow,
    '402': WeatherCondition.heavySnow,
    '403': WeatherCondition.heavySnow,
    '409': WeatherCondition.heavySnow,
    '499': WeatherCondition.heavySnow,
    '500': WeatherCondition.fog,
    '501': WeatherCondition.fog,
    '502': WeatherCondition.fog,
    '503': WeatherCondition.fog,
    '504': WeatherCondition.fog,
    '507': WeatherCondition.fog,
    '508': WeatherCondition.fog,
    '509': WeatherCondition.fog,
    '510': WeatherCondition.fog,
    '511': WeatherCondition.fog,
    '512': WeatherCondition.fog,
    '513': WeatherCondition.fog,
    '514': WeatherCondition.fog,
    '515': WeatherCondition.fog,
    '900': WeatherCondition.unknown,
    '901': WeatherCondition.unknown,
    '999': WeatherCondition.unknown,
  };
}

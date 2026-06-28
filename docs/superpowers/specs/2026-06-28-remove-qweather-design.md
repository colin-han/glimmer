# 移除和风天气，统一为天气枚举（改用高德天气）

日期：2026-06-28
分支：feature/re-processing

## 背景

App 原先用**和风天气（QWeather）**获取天气实况 + 城市名（`weather_service.dart`），同时用**高德地图（AMap）**做位置逆地理（POI/地址，`amap_service.dart`）。

近期引入高德后，高德也提供天气查询能力（`/v3/weather/weatherInfo`），与和风天气功能重叠，维护两套天气相关 SDK/Key/代码成本高。本设计**移除和风天气**，天气能力改由高德提供。

核心难点：和风与高德的天气数据表示不同——

- 和风返回**数字图标代码**（如 `100`=晴、`104`=阴、`305`=小雨），并存入 SQLite `weather_icon` 列；`diary_entry.dart` 用「和风代码→emoji」映射表渲染。
- 高德天气返回**文字描述**（如"晴"、"阵雨"、"小雪"），**无图标代码**；且查询需 `adcode`（行政区划编码），不能用经纬度直查。

为统一新旧数据的天气表示，引入**封闭的 `WeatherCondition` 枚举**（英文），作为数据库与 UI 的唯一天气表示；通过 drift migration 把历史 `weather_icon`（和风代码）一次性映射到该枚举。

## 目标

1. 移除和风天气全部代码、依赖、环境变量、构建校验。
2. 天气实况改由高德获取（复用 `AMAP_WEB_KEY`）。
3. 引入 `WeatherCondition` 枚举，数据库与 UI 统一使用该枚举。
4. drift migration 把历史 `weather_icon`（和风代码）映射到枚举，历史数据无缝兼容、不丢失。
5. UI 天气显示改为 `emoji + 中文标签 + 温度`。
6. 保持向后兼容（v1.0.0 基线），不删列、不破坏历史数据。

## 非目标

- 不改变位置解析逻辑（`LocationResolver` 的常用位置/高德 POI/地址优先级不变）。
- 不重写已存储的历史天气数据列（`weather_icon`/`weather_text` 保留不删，仅新增枚举列并回填）。
- 不重新查询历史记录的天气（时间已过，无法还原；只做格式映射）。

## 核心设计

### 1. `WeatherCondition` 枚举

新建 `lib/models/weather_condition.dart`。封闭枚举，自带 emoji 与中文标签，并提供两个**纯函数**映射（无副作用、可单测）：

```dart
enum WeatherCondition {
  sunny,     // 晴      ☀️
  cloudy,    // 多云    🌤️
  overcast,  // 阴      ☁️
  drizzle,   // 小雨    🌦️
  rain,      // 中大雨  🌧️
  shower,    // 阵雨    🌦️
  thunder,   // 雷雨    ⛈️
  lightSnow, // 小雪    🌨️
  heavySnow, // 大雪    ❄️
  fog,       // 雾霾沙尘 🌫️
  unknown;   // 无法识别（emoji/label 为空，不参与显示）

  String get emoji; // unknown 返回 ''
  String get label; // unknown 返回 ''；其余见上表

  /// 显示用片段：emoji + label，如 '🌦️ 阵雨'；unknown 返回 ''
  String get displayPart => emoji.isEmpty && label.isEmpty ? '' : '$emoji $label';

  /// 和风数字代码 → 枚举（migration + 运行时兜底用）
  static WeatherCondition fromQweatherCode(String code);

  /// 高德天气文字 → 枚举（实时查询用，关键字有序匹配）
  static WeatherCondition fromAmapText(String text);
}
```

> 说明：`drizzle`（小雨）与 `shower`（阵雨）共用 🌦️ emoji，靠中文标签区分——这正是引入「中文标签」显示的价值。

#### 1.1 和风代码 → 枚举（`fromQweatherCode`）

完整映射表（覆盖现有 `_weatherEmojiMap` 全部 53 个 key）：

| 枚举 | 和风代码 |
|---|---|
| `sunny` | 100, 150 |
| `cloudy` | 101, 102, 103, 151 |
| `overcast` | 104 |
| `shower` | 300 |
| `thunder` | 301, 302, 303, 304 |
| `drizzle` | 305, 309 |
| `rain` | 306, 307, 308, 310, 311, 312, 313, 314, 315, 399 |
| `lightSnow` | 400, 404, 405, 406, 407, 408 |
| `heavySnow` | 401, 402, 403, 409, 499 |
| `fog` | 500, 501, 502, 503, 504, 507, 508, 509, 510, 511, 512, 513, 514, 515 |
| `unknown` | 900, 901, 999，以及表外任意未知代码 |

> 雨夹雪类（404/405/406）归 `lightSnow`（含雪成分）。

#### 1.2 高德文字 → 枚举（`fromAmapText`）

**有序**关键字匹配，先具体后通用，命中即返回：

1. 含「雷」→ `thunder`（如雷阵雨、雷暴）
2. 含「雨夹雪」或「雨雪」→ `lightSnow`
3. 含「阵雨」→ `shower`
4. 含「毛毛雨」或「小雨」→ `drizzle`
5. 含「冻雨」→ `rain`
6. 含「中雨/大雨/暴雨」→ `rain`
7. 含「雨」→ `rain`（兜底）
8. 含「大雪/暴雪/大到暴雪/中到大雪」→ `heavySnow`
9. 含「中雪」→ `heavySnow`
10. 含「小雪/阵雪/小到中雪」→ `lightSnow`
11. 含「雪」→ `lightSnow`（兜底）
12. 含「雾/霾/沙/尘/浮」→ `fog`
13. 含「晴」→ `sunny`
14. 含「多云/少云」→ `cloudy`
15. 含「阴」→ `overcast`
16. 其余 → `unknown`

> 顺序保证「雷阵雨」命中 `thunder` 而非 `shower`/`rain`，「雨夹雪」命中 `lightSnow` 而非被「雨」或「雪」抢先。

### 2. SQLite 变更（drift migration，schema 9 → 10）

**`lib/services/database/tables.dart`**：新增列，**保留**旧列不删（CLAUDE.md 禁止删列）。用 `TypeConverter` 让 drift 自动处理枚举 ↔ String（与现有 `MapConverter` 同模式），`DiaryEntry` 直接持有 `WeatherCondition?`，无需手动 `byName`：

```dart
/// WeatherCondition ↔ 枚举名（英文 String）
class WeatherConditionConverter extends TypeConverter<WeatherCondition, String> {
  const WeatherConditionConverter();
  @override
  WeatherCondition fromSql(String fromDb) =>
      WeatherCondition.values.byName(fromDb);
  @override
  String toSql(WeatherCondition value) => value.name;
}

// DiaryEntries 表内：
TextColumn get weatherCondition =>
    text().map(const WeatherConditionConverter()).nullable()(); // 新增
TextColumn get weatherIcon => text().nullable()();      // 保留（不再写入）
TextColumn get weatherText => text().nullable()();      // 保留（不再写入）
TextColumn get temperature => text().nullable()();      // 不变
```

**`lib/services/database/app_database.dart`**：

- `schemaVersion` 改为 `10`。
- `onUpgrade` 新增 `if (from < 10)` 块，遵循现有幂等模式：
  - 幂等添加 `weather_condition` 列（`_columnExists` 检测）。
  - 调用新方法 `_migrateWeatherCondition()` 回填数据。

`_migrateWeatherCondition()` 逻辑（参照现有 `_migrateStatusToTasks()` 的「遍历行 + UPDATE」模式）：

```dart
Future<void> _migrateWeatherCondition() async {
  final rows = await customSelect(
    "SELECT id, weather_icon FROM diary_entries "
    "WHERE weather_condition IS NULL AND weather_icon IS NOT NULL",
  ).get();
  for (final r in rows) {
    final icon = r.read<String>('weather_icon');
    final condition = WeatherCondition.fromQweatherCode(icon);
    await customStatement(
      "UPDATE diary_entries SET weather_condition = ? WHERE id = ?",
      [condition.name, r.read<String>('id')],
    );
  }
}
```

- 幂等：`WHERE weather_condition IS NULL`，重跑安全（drift 真失败不推进 user_version，下次重试）。
- 含和风代码的旧行全部回填为枚举名（含 `unknown`）；`weather_icon` 为 NULL 的行跳过（本就无天气）。
- 枚举以 `condition.name`（英文，如 `heavySnow`）存入，读取时 `WeatherCondition.values.byName(...)`。

### 3. 高德天气接入（`lib/services/amap_service.dart`）

新增方法 `fetchWeatherByLocation(double lat, double lon)`，返回 `({WeatherCondition condition, String temperature})?`（失败/未配置返回 null）：

1. 复用现有 Dio 与 `AMAP_WEB_KEY`。
2. 调 regeo（`/v3/geocode/regeo`，`extensions=base`）取 `regeocode.addressComponent.adcode`。
3. 用 adcode 调 `/v3/weather/weatherInfo`（`extensions=base`），取 `lives[0]` 的 `weather`（文字）与 `temperature`。
4. `WeatherCondition.fromAmapText(weather)` → 枚举，与 temperature 一起返回。
5. 失败（HTTP 错误、status≠1、lives 空、未配置 key）返回 null，不抛异常（符合项目异常规范，与 `nearestPoiOrAddress` 一致）。

> adcode 获取需要一次 regeo；位置解析 `LocationResolver` 也会调一次 regeo。两者在录音期间并行「即发即忘」，各调一次 regeo + 天气再调一次 weatherInfo，高德配额充足，可接受。不为此引入跨方法结果共享（YAGNI）。

`AmapService.nearestPoiOrAddress()` 与 `LocationResolver` **保持不变**。

### 4. `DiaryEntry` 模型变更（`lib/models/diary_entry.dart`）

- 新增字段：`final WeatherCondition? weatherCondition;`（加到构造函数参数；天气创建后不可变，**不进 `copyWith`**）。
- **保留** `weatherIcon`/`weatherText` 字段（不删，承载历史数据；新数据不再写入）。
- 删除：`_weatherEmojiMap`（和风代码→emoji 映射表）与 `weatherEmoji()` 静态方法。
- `weatherDisplay` 改为基于枚举：

  ```dart
  String get weatherDisplay {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    final c = effectiveCondition;
    if (c != null && c.displayPart.isNotEmpty) parts.add(c.displayPart);
    if (temperature != null) parts.add('$temperature°');
    return parts.join('  ');
  }
  ```

- 新增运行时兜底 getter（双保险，应对 migration 极端遗漏）：

  ```dart
  WeatherCondition? get effectiveCondition =>
      weatherCondition ??
      (weatherIcon != null ? WeatherCondition.fromQweatherCode(weatherIcon!) : null);
  ```

### 5. UI 适配（显示格式：`emoji + 中文标签 + 温度`）

天气显示统一用 `WeatherCondition.displayPart`（`🌦️ 阵雨`）+ 温度。涉及：

- **`recording_page.dart`**：录音中天气 pill，从原 `${emoji} ${temp}°` 改为 `${condition.displayPart} ${temp}°`；消息回调改为接收 `{condition, temperature}`。
- **`widgets/detail/detail_info_bar.dart`**：天气区显示 `emoji + label`，温度带 `°C`/`°`。
- **`diary_list_page.dart`**：用 `entry.weatherDisplay`（已含新格式），无需单独改。
- **`models/daily_summary.dart`**：
  - `DayWeatherSummary` 字段 `weatherIcon`/`weatherText` → 改为 `WeatherCondition? condition`。
  - `display`：`{地名}  {condition.displayPart}  {tempMin°~tempMax°}`。
  - `isEmpty`、`tempDisplay` 逻辑相应调整。
  - `aggregateDayWeather()`：按 `effectiveCondition`（众数，用 `condition.name` 作 key）统计，温度仍 min~max。
- **`daily_summary_page.dart`**：使用改后的 `DayWeatherSummary.display`。

### 6. 移除和风天气

- 删除文件：`lib/services/weather_service.dart`（含 `WeatherLocation` 类）。
- **`lib/services/recording_task_handler.dart`**：
  - 移除 `WeatherService` 实例与 `_weatherLocation` 字段。
  - `_fetchWeatherInBackground()`：天气获取改调 `AmapService.fetchWeatherByLocation()`；位置解析不变。
  - 天气就绪消息改为 `{'type': 'weather', 'condition': w.condition.name, 'temperature': w.temperature}`。
  - `createEntry`：`weatherCondition: _weather?.condition`、`temperature: _weather?.temperature`，不再写 `weatherIcon`/`weatherText`。`locationName` 仍取 `_resolvedLocationName`（移除 `_weatherLocation?.locationName` 兜底，因高德天气不带地名）。
- **环境变量**：
  - `.env.local.example`：删除 `# 和风天气` 段及 `QWEATHER_TOKEN`/`QWEATHER_HOST` 两行；保留 `AMAP_WEB_KEY`。
  - `.env.local`：提示用户自行删除 `QWEATHER_*`（不入库，不代改）。
  - `scripts/build.sh`：`REQUIRED_ENV_VARS` 数组删除 `QWEATHER_TOKEN`；第 13 行注释中关于「QWEATHER_HOST 有默认值」的说明一并删除。
  - `CLAUDE.md`：环境变量清单删除 `QWEATHER_TOKEN` 条目。

## 数据兼容性

- **不删列**：`weather_icon`/`weather_text` 保留，承载历史数据，符合 v1.0.0 兼容基线。
- **不丢数据**：历史行经 migration 回填 `weather_condition`；运行时 `effectiveCondition` 兜底。
- **schema 迁移**：通过 drift migration（schema 9→10），新列 nullable，幂等可重试。
- **无破坏性操作**：不 DROP TABLE、不 DELETE 无 WHERE。
- 新数据只写 `weather_condition` + `temperature`；旧列对老记录只读保留。

## 涉及文件清单

新增：
- `lib/models/weather_condition.dart`

修改：
- `lib/services/database/tables.dart`（+`weatherCondition` 列）
- `lib/services/database/app_database.dart`（schema 10 + `_migrateWeatherCondition`；**改后需 `dart run build_runner build`**）
- `lib/services/amap_service.dart`（+`fetchWeatherByLocation`）
- `lib/models/diary_entry.dart`（+`weatherCondition`、`effectiveCondition`、改 `weatherDisplay`、删和风映射表）
- `lib/models/daily_summary.dart`（`DayWeatherSummary` 改枚举、`aggregateDayWeather` 改统计）
- `lib/services/recording_task_handler.dart`（改用高德天气）
- `lib/pages/recording_page.dart`（天气 pill + 消息）
- `lib/pages/daily_summary_page.dart`（聚合显示）
- `lib/widgets/detail/detail_info_bar.dart`（天气显示）
- `.env.local.example`（删 QWEATHER）
- `scripts/build.sh`（`REQUIRED_ENV_VARS` 删 QWEATHER_TOKEN）
- `CLAUDE.md`（环境变量清单删 QWEATHER_TOKEN）

删除：
- `lib/services/weather_service.dart`

## 测试策略

纯函数 + migration 优先单测（无网络依赖）：

1. **`fromQweatherCode`**：逐一覆盖上表全部 53 个和风代码 + 几个表外未知代码（断言 → `unknown`）。
2. **`fromAmapText`**：覆盖"晴/多云/阴/小雨/中雨/大雨/阵雨/雷阵雨/雨夹雪/小雪/中雪/大雪/暴雪/雾/霾/扬沙/浮尘/空串/乱码"，重点验证匹配顺序（雷阵雨→thunder、雨夹雪→lightSnow）。
3. **`WeatherCondition.displayPart`**：各枚举 emoji+label 拼接正确；`unknown` 为空。
4. **migration**：构造内存库，插入若干带 `weather_icon`（和风代码）的旧行，跑 migration，断言 `weather_condition` 正确回填、幂等（再跑不重复 UPDATE/不报错）、`weather_icon` 原值保留。
5. 手动验证：dev 构建后录音，确认天气 pill 与详情页显示 `emoji 标签 温度`；旧记录天气正常显示。

## 验收标准

- `flutter analyze` 无 issue；改动文件 `dart format` 通过。
- 现有历史记录天气在迁移后正常显示（枚举渲染，无空缺）。
- 新录音天气来自高德，显示格式为 `emoji + 中文标签 + 温度`。
- 全代码库无 `QWEATHER` / `weather_service` / 和风映射表残留。
- `scripts/build.sh` 不再校验 `QWEATHER_TOKEN`，prod 可正常编译（需 `.env.local` 实际删除 QWEATHER 后）。

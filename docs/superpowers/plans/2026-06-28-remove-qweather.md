# 移除和风天气、统一为天气枚举 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除和风天气（QWeather），天气能力改由高德提供；引入 `WeatherCondition` 枚举统一新旧天气数据表示，drift migration 把历史和风代码映射到枚举，UI 显示 `emoji + 中文标签 + 温度`。

**Architecture:** 新建封闭枚举 `WeatherCondition`（自带 emoji/中文标签 + 两个纯函数映射：和风代码→枚举、高德文字→枚举）。drift schema 9→10 加 `weather_condition` 列（TypeConverter）+ 数据回填。`AmapService` 新增天气查询（regeo 取 adcode → weatherInfo 取实况）。各 UI 改用枚举派生显示。最后删除和风服务与映射表、清理环境变量。

**Tech Stack:** Flutter, drift（+ build_runner）, dio, flutter_test + mocktail。

参考设计：`docs/superpowers/specs/2026-06-28-remove-qweather-design.md`

---

## File Structure

| 文件 | 责任 | 操作 |
|---|---|---|
| `lib/models/weather_condition.dart` | 天气枚举 + emoji/标签 + 和风代码/高德文字→枚举映射 | Create |
| `lib/services/database/tables.dart` | `weatherCondition` 列 + `WeatherConditionConverter` | Modify |
| `lib/services/database/app_database.dart` | schema 10 + `_migrateWeatherCondition` | Modify |
| `lib/services/database/app_database.g.dart` | drift 生成 | Regenerate |
| `lib/services/amap_service.dart` | +`fetchWeatherByLocation`（高德天气） | Modify |
| `lib/models/diary_entry.dart` | +`weatherCondition`/`effectiveCondition`，改 `weatherDisplay`，最后删和风映射 | Modify |
| `lib/services/diary_storage_service.dart` | model↔row 转换同步 `weatherCondition`（2 写 + 4 读） | Modify |
| `lib/models/daily_summary.dart` | `DayWeatherSummary` 改枚举，`aggregateDayWeather` 改统计 | Modify |
| `lib/widgets/detail/detail_info_bar.dart` | 天气显示改枚举 | Modify |
| `lib/services/recording_task_handler.dart` | 改用高德天气，删和风依赖 | Modify |
| `lib/pages/recording_page.dart` | 天气 pill + 消息改枚举 | Modify |
| `lib/services/weather_service.dart` | 和风服务 | Delete |
| `.env.local.example` / `scripts/build.sh` / `CLAUDE.md` | 删 `QWEATHER_*` | Modify |
| `test/weather_condition_test.dart` | 枚举映射单测 | Create |
| `test/weather_migration_test.dart` | drift migration 集成测 | Create |

---

## Task 1: WeatherCondition 枚举与映射（TDD）

**Files:**
- Create: `lib/models/weather_condition.dart`
- Test: `test/weather_condition_test.dart`

- [ ] **Step 1: 写失败测试（和风代码映射全覆盖）**

Create `test/weather_condition_test.dart`:

```dart
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
      expect(WeatherCondition.fromQweatherCode('777'), WeatherCondition.unknown);
      expect(WeatherCondition.fromQweatherCode(''), WeatherCondition.unknown);
    });
  });

  group('fromAmapText', () {
    test('晴/多云/阴', () {
      expect(WeatherCondition.fromAmapText('晴'), WeatherCondition.sunny);
      expect(WeatherCondition.fromAmapText('多云'), WeatherCondition.cloudy);
      expect(WeatherCondition.fromAmapText('阴'), WeatherCondition.overcast);
    });

    test('雷阵雨优先于阵雨/雨（顺序验证）', () {
      expect(WeatherCondition.fromAmapText('雷阵雨'), WeatherCondition.thunder);
      expect(WeatherCondition.fromAmapText('阵雨'), WeatherCondition.shower);
      expect(WeatherCondition.fromAmapText('小雨'), WeatherCondition.drizzle);
      expect(WeatherCondition.fromAmapText('中雨'), WeatherCondition.rain);
      expect(WeatherCondition.fromAmapText('大雨'), WeatherCondition.rain);
      expect(WeatherCondition.fromAmapText('暴雨'), WeatherCondition.rain);
    });

    test('雨夹雪优先于雨/雪单独命中', () {
      expect(WeatherCondition.fromAmapText('雨夹雪'), WeatherCondition.lightSnow);
    });

    test('雪细分', () {
      expect(WeatherCondition.fromAmapText('小雪'), WeatherCondition.lightSnow);
      expect(WeatherCondition.fromAmapText('中雪'), WeatherCondition.heavySnow);
      expect(WeatherCondition.fromAmapText('大雪'), WeatherCondition.heavySnow);
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
    test('各枚举拼接 emoji + 标签', () {
      expect(WeatherCondition.sunny.displayPart, '☀️ 晴');
      expect(WeatherCondition.shower.displayPart, '🌦️ 阵雨');
      expect(WeatherCondition.thunder.displayPart, '⛈️ 雷雨');
      expect(WeatherCondition.heavySnow.displayPart, '❄️ 大雪');
    });
    test('unknown 为空字符串', () {
      expect(WeatherCondition.unknown.displayPart, '');
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/weather_condition_test.dart`
Expected: 编译失败（`weather_condition.dart` 不存在 / `WeatherCondition` 未定义）。

- [ ] **Step 3: 实现 `WeatherCondition`**

Create `lib/models/weather_condition.dart`:

```dart
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
        WeatherCondition.rain => '大雨',
        WeatherCondition.shower => '阵雨',
        WeatherCondition.thunder => '雷雨',
        WeatherCondition.lightSnow => '小雪',
        WeatherCondition.heavySnow => '大雪',
        WeatherCondition.fog => '雾霾',
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
    if (text.contains('中雨') ||
        text.contains('大雨') ||
        text.contains('暴雨')) {
      return WeatherCondition.rain;
    }
    if (text.contains('雨')) return WeatherCondition.rain;
    if (text.contains('大雪') ||
        text.contains('暴雪') ||
        text.contains('中到大雪')) {
      return WeatherCondition.heavySnow;
    }
    if (text.contains('中雪')) return WeatherCondition.heavySnow;
    if (text.contains('小雪') || text.contains('阵雪') || text.contains('小到中雪')) {
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
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/weather_condition_test.dart`
Expected: `All tests passed!`（60+ 个 case）。

- [ ] **Step 5: 格式化 + 分析 + 提交**

Run: `dart format lib/models/weather_condition.dart test/weather_condition_test.dart && flutter analyze`
Expected: `No issues found!`

```bash
git add lib/models/weather_condition.dart test/weather_condition_test.dart
git commit -m "$(cat <<'EOF'
feat: 新增 WeatherCondition 枚举与天气映射

引入统一天气枚举（11 类细分雨雪），含和风代码→枚举、高德文字→枚举
两个纯函数映射，自带 emoji 与中文标签。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: drift schema 9→10 与 weather_condition 回填（TDD）

**Files:**
- Modify: `lib/services/database/tables.dart`
- Modify: `lib/services/database/app_database.dart`
- Regenerate: `lib/services/database/app_database.g.dart`
- Test: `test/weather_migration_test.dart`

- [ ] **Step 1: 写失败测试（migration 回填 + 幂等）**

Create `test/weather_migration_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('onUpgrade 9→10：含和风代码的行 weather_condition 被回填', () async {
    // 内存库 onCreate 已建 v10 全表（weather_condition 列存在但为空）
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
          "created_at, weather_icon, status, processing_stage) "
          "VALUES ('a','t','/a',1,0,'104','completed','uploading')",
    );
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
          "created_at, weather_icon, status, processing_stage) "
          "VALUES ('b','t','/b',1,0,'305','completed','uploading')",
    );
    // 无和风代码的行
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
          "created_at, status, processing_stage) "
          "VALUES ('c','t','/c',1,0,'completed','uploading')",
    );

    // 手动触发 onUpgrade（from=9）
    await db.migration.onUpgrade?.call(db.createMigrator(), 9, 10);

    final a = await db
        .customSelect(
          "SELECT weather_condition, weather_icon FROM diary_entries WHERE id='a'",
        )
        .getSingle();
    expect(a.read<String>('weather_condition'), 'overcast');
    expect(a.readNullable<String>('weather_icon'), '104'); // 旧列保留

    final b = await db
        .customSelect(
          "SELECT weather_condition FROM diary_entries WHERE id='b'",
        )
        .getSingle();
    expect(b.read<String>('weather_condition'), 'drizzle');

    final c = await db
        .customSelect(
          "SELECT weather_condition FROM diary_entries WHERE id='c'",
        )
        .getSingle();
    expect(c.readNullable<String>('weather_condition'), isNull);
  });

  test('onUpgrade 幂等：重复执行不报错、不重复改写', () async {
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
          "created_at, weather_icon, status, processing_stage) "
          "VALUES ('a','t','/a',1,0,'100','completed','uploading')",
    );
    await db.migration.onUpgrade?.call(db.createMigrator(), 9, 10);
    await db.migration.onUpgrade?.call(db.createMigrator(), 9, 10); // 再跑一次
    final a = await db
        .customSelect(
          "SELECT weather_condition FROM diary_entries WHERE id='a'",
        )
        .getSingle();
    expect(a.read<String>('weather_condition'), 'sunny');
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/weather_migration_test.dart`
Expected: 失败（`weather_condition` 列不存在 / `weatherIcon` 列在 raw insert 中可能不存在报错）。

- [ ] **Step 3: tables.dart 加列 + TypeConverter**

Modify `lib/services/database/tables.dart`：

在文件顶部 import 后（`MapConverter` 之后）新增 converter：

```dart
import '../models/weather_condition.dart';

/// WeatherCondition ↔ 枚举名（英文 String）
class WeatherConditionConverter
    extends TypeConverter<WeatherCondition, String> {
  const WeatherConditionConverter();
  @override
  WeatherCondition fromSql(String fromDb) =>
      WeatherCondition.values.byName(fromDb);
  @override
  String toSql(WeatherCondition value) => value.name;
}
```

在 `DiaryEntries` 表的 `weatherIcon` 列上方新增（保留 `weatherIcon`/`weatherText` 不删）：

```dart
  TextColumn get weatherCondition =>
      text().map(const WeatherConditionConverter()).nullable()();
  TextColumn get weatherIcon => text().nullable()();
  TextColumn get weatherText => text().nullable()();
```

- [ ] **Step 4: app_database.dart 升 schema + 加回填**

Modify `lib/services/database/app_database.dart`：

1. 顶部加 import：`import '../models/weather_condition.dart';`
2. `int get schemaVersion => 9;` 改为 `int get schemaVersion => 10;`
3. 在 `onUpgrade` 的 `if (from < 9) { ... }` 块之后、闭合之前，新增：

```dart
      if (from < 10) {
        if (!await _columnExists('diary_entries', 'weather_condition')) {
          await m.addColumn(diaryEntries, diaryEntries.weatherCondition);
        }
        await _migrateWeatherCondition();
      }
```

4. 在 `_migrateStatusToTasks()` 方法之后新增（同级）：

```dart
  /// 回填 weather_condition：把历史 weather_icon（和风代码）映射到枚举。
  /// 幂等：仅处理 weather_condition IS NULL 的行。
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

- [ ] **Step 5: 重新生成 drift 代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 成功生成 `app_database.g.dart`，无报错。

- [ ] **Step 6: 运行 migration 测试 + 全部测试，确认通过**

Run: `flutter test test/weather_migration_test.dart`
Expected: `All tests passed!`

Run: `flutter test`
Expected: 全部既有测试通过（无回归）。

- [ ] **Step 7: 格式化 + 分析 + 提交**

Run: `dart format lib/services/database/tables.dart lib/services/database/app_database.dart && flutter analyze`
Expected: `No issues found!`

```bash
git add lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/database/app_database.g.dart test/weather_migration_test.dart
git commit -m "$(cat <<'EOF'
feat: drift schema 9→10，新增 weather_condition 列并回填历史数据

新增 WeatherConditionConverter（TypeConverter），diary_entries 增加
weather_condition 列；migration 把历史和风代码映射到枚举（幂等），
保留旧 weather_icon/weather_text 列不删。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: DiaryEntry 加 weatherCondition 字段与 effectiveCondition（TDD-辅助）

**Files:**
- Modify: `lib/models/diary_entry.dart`
- Modify: `lib/services/diary_storage_service.dart`
- Test: `test/diary_entry_test.dart`（新增）

> 说明：本任务**暂不删除** `_weatherEmojiMap`/`weatherEmoji`（仍被 detail/daily_summary/recording_page 引用），只新增字段并切换 `weatherDisplay` 数据源。删除留到 Task 7（此时引用方已全部改完）。

- [ ] **Step 1: 写失败测试（effectiveCondition + weatherDisplay）**

Create `test/diary_entry_test.dart`:

```dart
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
      expect(_entry(weatherIcon: '104').effectiveCondition,
          WeatherCondition.overcast);
      expect(_entry(weatherIcon: '305').effectiveCondition,
          WeatherCondition.drizzle);
    });

    test('两者都空返回 null', () {
      expect(_entry().effectiveCondition, isNull);
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
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/diary_entry_test.dart`
Expected: 编译失败（`weatherCondition` 字段 / `effectiveCondition` 未定义）。

- [ ] **Step 3: diary_entry.dart 加字段 + 改 weatherDisplay**

Modify `lib/models/diary_entry.dart`：

1. 顶部 import：`import 'weather_condition.dart';`
2. 字段区（`weatherIcon` 上方）新增：

```dart
  final WeatherCondition? weatherCondition;
  final String? weatherIcon;
```

3. 构造函数参数（`this.weatherIcon,` 上方）新增 `this.weatherCondition,`
4. `copyWith` **不改**（天气不可变；现有 copyWith 不含天气字段，保持现状）。
5. 替换 `weatherDisplay` getter（保留 `weatherEmoji`/`_weatherEmojiMap` 不动）：

```dart
  /// 天气摘要文本，如 "海淀区  🌦️ 阵雨  24°"，无天气时返回空字符串
  String get weatherDisplay {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    final c = effectiveCondition;
    if (c != null && c.displayPart.isNotEmpty) parts.add(c.displayPart);
    if (temperature != null) parts.add('$temperature°');
    return parts.join('  ');
  }

  /// 有效天气：优先 weatherCondition，为空则从历史 weather_icon 兜底。
  WeatherCondition? get effectiveCondition => weatherCondition ??
      (weatherIcon != null
          ? WeatherCondition.fromQweatherCode(weatherIcon!)
          : null);
```

> `weatherEmoji()` 与 `_weatherEmojiMap` 暂时保留（Task 7 删除）。

- [ ] **Step 4: diary_storage_service.dart 同步 weatherCondition 读写**

Modify `lib/services/diary_storage_service.dart`，共 6 处：

- 第 58-59 行（`createEntry` 的 companion）：在 `weatherIcon: Value(entry.weatherIcon),` 上方加：

```dart
        weatherCondition: Value(entry.weatherCondition),
        weatherIcon: Value(entry.weatherIcon),
```

- 第 82-83 行（`updateEntry` 的 companion）：同上加 `weatherCondition: Value(entry.weatherCondition),`
- 第 259、286、542、574 行附近（4 处 `DiaryEntry(` 从 `r` 构造）：在每处 `weatherIcon: r.weatherIcon,` 上方加：

```dart
            weatherCondition: r.weatherCondition,
            weatherIcon: r.weatherIcon,
```

（用编辑器定位每个 `weatherIcon: r.weatherIcon,` 出现处，逐一加。共 4 处，分别在 `getAllEntries`/`getEntryById` 及两个分页/查询方法内。）

- [ ] **Step 5: 运行测试，确认通过**

Run: `flutter test test/diary_entry_test.dart`
Expected: `All tests passed!`

Run: `flutter test`
Expected: 全部通过（daily_summary_test 仍用 weatherIcon 字段，未受影响）。

- [ ] **Step 6: 格式化 + 分析 + 提交**

Run: `dart format lib/models/diary_entry.dart lib/services/diary_storage_service.dart test/diary_entry_test.dart && flutter analyze`
Expected: `No issues found!`

```bash
git add lib/models/diary_entry.dart lib/services/diary_storage_service.dart test/diary_entry_test.dart
git commit -m "$(cat <<'EOF'
feat: DiaryEntry 新增 weatherCondition 字段与 effectiveCondition 兜底

model↔row 转换同步读写 weather_condition；weatherDisplay 改用枚举
派生（emoji+标签+温度），保留 effectiveCondition 从历史 weather_icon
兜底。和风映射表暂留，待引用方迁移后删除。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: DailySummary 聚合改用 weatherCondition（TDD）

**Files:**
- Modify: `lib/models/daily_summary.dart`
- Modify: `test/daily_summary_test.dart`（既有，更新断言）

- [ ] **Step 1: 更新既有测试为枚举语义**

Modify `test/daily_summary_test.dart`：

1. import 加 `import 'package:voice_diary/models/weather_condition.dart';`
2. `aggregateDayWeather` 组里第 1 个测试「天气取众数…」的断言替换：

```dart
      expect(agg.condition, WeatherCondition.overcast); // 104 出现 2 次 > 100 的 1 次
      expect(agg.tempMin, 18);
      expect(agg.tempMax, 25);
      expect(agg.tempDisplay, '18°~25°');
      expect(agg.locationName, '海淀区');
      expect(agg.isEmpty, isFalse);
```

（删除 `expect(agg.weatherIcon, '104');` 与 `expect(agg.weatherText, '阴');` 两行。）

3. 在该组末尾追加 display 测试：

```dart
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
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/daily_summary_test.dart`
Expected: 失败（`agg.condition` 不存在 / `DayWeatherSummary.weatherIcon` 已删报错）。

- [ ] **Step 3: 改 DayWeatherSummary 与 aggregateDayWeather**

Modify `lib/models/daily_summary.dart`：

1. 顶部 import：`import 'weather_condition.dart';`（与既有 `diary_entry.dart` import 同区）
2. 替换 `DayWeatherSummary` 类的字段、构造、isEmpty、display（`tempDisplay`/`tempMin`/`tempMax` 保留）：

```dart
class DayWeatherSummary {
  final String? locationName;
  final WeatherCondition? condition;
  final num? tempMin;
  final num? tempMax;

  const DayWeatherSummary({
    this.locationName,
    this.condition,
    this.tempMin,
    this.tempMax,
  });

  bool get isEmpty =>
      locationName == null &&
      condition == null &&
      tempMin == null &&
      tempMax == null;

  /// 温度展示：无数据→''；全相同→'24°'；有差异→'18°~25°'。
  String get tempDisplay {
    if (tempMin == null || tempMax == null) return '';
    if (tempMin == tempMax) return '${tempMin!.round()}°';
    return '${tempMin!.round()}°~${tempMax!.round()}°';
  }

  /// 聚合天气的展示文本，如 '海淀区  ☁️ 阴  18°~25°'；无数据返回 ''。
  String get display {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    if (condition != null && condition!.displayPart.isNotEmpty) {
      parts.add(condition!.displayPart);
    }
    if (tempDisplay.isNotEmpty) parts.add(tempDisplay);
    return parts.join('  ');
  }
}
```

3. 替换 `aggregateDayWeather`（注释改为按 condition 统计）：

```dart
/// 聚合一天各篇录音的天气：地点众数 + 天气众数（按 effectiveCondition 统计）+ 温度 min~max。
/// 详情页现算，不入库；全无数据时返回 isEmpty 的对象。
DayWeatherSummary aggregateDayWeather(List<DiaryEntry> entries) {
  final locCounts = <String, int>{};
  final conditionCounts = <WeatherCondition, int>{};
  final temps = <num>[];

  for (final e in entries) {
    final loc = e.locationName;
    if (loc != null && loc.isNotEmpty) {
      locCounts[loc] = (locCounts[loc] ?? 0) + 1;
    }
    final c = e.effectiveCondition;
    if (c != null) {
      conditionCounts[c] = (conditionCounts[c] ?? 0) + 1;
    }
    final temp = e.temperature;
    if (temp != null && temp.isNotEmpty) {
      final n = num.tryParse(temp);
      if (n != null) temps.add(n);
    }
  }

  final conditionMode = _modeKeyCondition(conditionCounts);

  num? tempMin;
  num? tempMax;
  if (temps.isNotEmpty) {
    temps.sort();
    tempMin = temps.first;
    tempMax = temps.last;
  }

  return DayWeatherSummary(
    locationName: _modeKey(locCounts),
    condition: conditionMode,
    tempMin: tempMin,
    tempMax: tempMax,
  );
}

/// 取频次最高的 WeatherCondition（众数）；空 map 返回 null；平局取先出现的。
WeatherCondition? _modeKeyCondition(Map<WeatherCondition, int> counts) {
  if (counts.isEmpty) return null;
  var bestKey = counts.keys.first;
  var bestCount = counts[bestKey]!;
  counts.forEach((k, v) {
    if (v > bestCount) {
      bestKey = k;
      bestCount = v;
    }
  });
  return bestKey;
}
```

> 既有 `_modeKey(Map<String,int>)` 仍被 `locCounts` 使用，保留不删。

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/daily_summary_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 格式化 + 分析 + 提交**

Run: `dart format lib/models/daily_summary.dart test/daily_summary_test.dart && flutter analyze`
Expected: `No issues found!`

```bash
git add lib/models/daily_summary.dart test/daily_summary_test.dart
git commit -m "$(cat <<'EOF'
refactor: 每日总结天气聚合改用 WeatherCondition

DayWeatherSummary 以 condition 取代 weatherIcon/weatherText；
aggregateDayWeather 按 effectiveCondition 众数统计，display 输出
emoji+标签+温度。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: detail_info_bar 天气显示改用枚举

**Files:**
- Modify: `lib/widgets/detail/detail_info_bar.dart`

- [ ] **Step 1: 替换天气片段构造**

Modify `lib/widgets/detail/detail_info_bar.dart` 第 32-42 行（`// 天气` 块）替换为：

```dart
    // 天气
    final condition = entry.effectiveCondition;
    if (condition != null && condition.displayPart.isNotEmpty) {
      parts.add(_InfoItem(icon: null, text: condition.displayPart));
    }
```

- [ ] **Step 2: 移除 now-unused 的 weatherEmoji 引用**

确认 `DiaryEntry.weatherEmoji` 在本文件不再被引用（上一步已移除唯一引用）。import `diary_entry.dart` 仍需保留（`entry.formattedDate` 等仍用）。无需改动 import。

- [ ] **Step 3: 分析确认无残留引用**

Run: `flutter analyze lib/widgets/detail/detail_info_bar.dart`
Expected: `No issues found!`

- [ ] **Step 4: 格式化 + 提交**

Run: `dart format lib/widgets/detail/detail_info_bar.dart`

```bash
git add lib/widgets/detail/detail_info_bar.dart
git commit -m "$(cat <<'EOF'
refactor: 详情信息栏天气改用 WeatherCondition 显示

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 高德天气接入 + 录音流程切换（核心）

**Files:**
- Modify: `lib/services/amap_service.dart`
- Modify: `lib/services/recording_task_handler.dart`
- Modify: `lib/pages/recording_page.dart`

- [ ] **Step 1: AmapService 新增 fetchWeatherByLocation**

Modify `lib/services/amap_service.dart`：

1. 顶部 import：`import '../models/weather_condition.dart';`
2. 在类内（`nearestPoiOrAddress` 方法之后）新增：

```dart
  /// 高德天气实况：先 regeo 取 adcode，再 weatherInfo 取实况。
  /// 返回 (condition, temperature)；未配置/失败返回 null，不抛异常。
  Future<({WeatherCondition condition, String temperature})?>
      fetchWeatherByLocation(double lat, double lon) async {
    _ensureInitialized();
    final key = _key;
    if (key == null || key.isEmpty) {
      debugPrint('[高德天气] 未配置 AMAP_WEB_KEY，跳过');
      return null;
    }

    try {
      final locParam = '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}';

      // 1. regeo 取 adcode
      final regeo = await _dio.get(
        'https://restapi.amap.com/v3/geocode/regeo',
        queryParameters: {
          'key': key,
          'location': locParam,
          'extensions': 'base',
          'output': 'json',
        },
      );
      if (regeo.data['status']?.toString() != '1') {
        debugPrint('[高德天气] regeo 失败 body=${regeo.data}');
        return null;
      }
      final adcode = regeo.data['regeocode']?['addressComponent']?['adcode'];
      if (adcode == null || adcode.toString().isEmpty) {
        debugPrint('[高德天气] regeo 无 adcode');
        return null;
      }

      // 2. weatherInfo 取实况
      final resp = await _dio.get(
        'https://restapi.amap.com/v3/weather/weatherInfo',
        queryParameters: {
          'key': key,
          'city': adcode.toString(),
          'extensions': 'base',
          'output': 'json',
        },
      );
      if (resp.data['status']?.toString() != '1') {
        debugPrint('[高德天气] weatherInfo 失败 body=${resp.data}');
        return null;
      }
      final lives = resp.data['lives'] as List?;
      if (lives == null || lives.isEmpty) return null;
      final live = lives[0] as Map<String, dynamic>;
      final weatherText = (live['weather'] ?? '').toString();
      final temperature = (live['temperature'] ?? '').toString();
      if (weatherText.isEmpty && temperature.isEmpty) return null;
      return (
        condition: WeatherCondition.fromAmapText(weatherText),
        temperature: temperature,
      );
    } on DioException catch (e) {
      debugPrint(
        '[高德天气] HTTP 错误: status=${e.response?.statusCode}, body=${e.response?.data}',
      );
      return null;
    } catch (e) {
      debugPrint('[高德天气] 解析失败: $e');
      return null;
    }
  }
```

- [ ] **Step 2: recording_task_handler 改用高德天气**

Modify `lib/services/recording_task_handler.dart`：

1. 删 import：`import 'weather_service.dart';`（第 19 行）。新增 import：`import '../models/weather_condition.dart';`
2. 字段区（第 38-39 行附近）：把 `final _weatherService = WeatherService();` 删除；把 `final _locationResolver = LocationResolver(AmapService());` 改为共享同一 AmapService：

```dart
  final _amapService = AmapService();
  late final _locationResolver = LocationResolver(_amapService);
```

3. 字段（第 55 行）：`WeatherLocation? _weatherLocation;` 替换为：

```dart
  ({WeatherCondition condition, String temperature})? _weather;
```

4. `_fetchWeatherInBackground` 内（第 194-215 行）：把 `weatherFuture` 与天气就绪回调替换为：

```dart
        // 天气（高德） 与 位置解析 并行（两者只依赖 lat/lon）
        final weatherFuture = _amapService.fetchWeatherByLocation(
          loc.lat,
          loc.lon,
        );
        final resolveFuture = _locationResolver.resolve(
          lat: loc.lat,
          lon: loc.lon,
          favorites: favorites,
        );

        // 天气就绪 → 发天气消息（condition + temperature）
        weatherFuture.then((w) {
          if (w == null) return;
          _weather = w;
          _sendToMain({
            'type': 'weather',
            'condition': w.condition.name,
            'temperature': w.temperature,
          });
        });

        // 位置就绪 → 发位置消息
        resolveFuture.then((name) {
          _resolvedLocationName = name;
          _sendToMain({'type': 'location', 'locationName': name ?? ''});
        });
```

5. `createEntry`（第 280-284 行）天气字段替换为：

```dart
            weatherCondition: _weather?.condition,
            temperature: _weather?.temperature,
            locationName: _resolvedLocationName,
```

（删除原 `weatherIcon`/`weatherText` 行；删除 `_weatherLocation?.locationName` 兜底——高德天气不带地名，地名完全由 `_resolvedLocationName` 决定。）

- [ ] **Step 3: recording_page 改消息处理与 pill 显示**

Modify `lib/pages/recording_page.dart`：

1. 删 import（第 19 行）：`import '../services/weather_service.dart';`
2. 字段（第 42 行）：`WeatherLocation? _currentWeatherLocation;` 替换为：

```dart
  WeatherCondition? _currentCondition;
  String? _currentTemperature;
```

3. `_onTaskData` 的 `case 'weather':`（第 97-105 行）替换为：

```dart
      case 'weather':
        setState(() {
          _currentCondition = WeatherCondition.values.byName(
            data['condition'] as String,
          );
          _currentTemperature = data['temperature'] as String?;
        });
```

4. `_stopRecording` 重置（第 266 行）：`_currentWeatherLocation = null;` 替换为：

```dart
          _currentCondition = null;
          _currentTemperature = null;
```

5. 天气 pill 显示条件与内容（第 349-367 行）替换。先把条件里 `_currentWeatherLocation != null` 改为 `_currentCondition != null`：

```dart
                if (_state == RecordingState.recording &&
                    ((_currentLocationName != null &&
                            _currentLocationName!.isNotEmpty) ||
                        _currentCondition != null)) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (_currentLocationName != null &&
                          _currentLocationName!.isNotEmpty)
                        _infoPill(_currentLocationName!),
                      if (_currentCondition != null &&
                          _currentCondition!.displayPart.isNotEmpty)
                        _infoPill(
                          '${_currentCondition!.displayPart} ${_currentTemperature ?? ''}°',
                        ),
                    ],
                  ),
                ],
```

6. 顶部 import 加：`import '../models/weather_condition.dart';`

- [ ] **Step 4: 分析确认（此时仍可编译，weatherEmoji 引用还剩 daily_summary.dart 已在 Task4 清除、本任务已清除 recording_page/detail）**

Run: `flutter analyze`
Expected: `No issues found!`（`weather_service.dart` 已无 import 引用；`weatherEmoji` 此刻仅剩 diary_entry 自身定义，无外部引用）。

- [ ] **Step 5: 运行全部测试**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: 格式化 + 提交**

Run: `dart format lib/services/amap_service.dart lib/services/recording_task_handler.dart lib/pages/recording_page.dart`

```bash
git add lib/services/amap_service.dart lib/services/recording_task_handler.dart lib/pages/recording_page.dart
git commit -m "$(cat <<'EOF'
feat: 天气改由高德提供，录音流程接入高德天气

AmapService 新增 fetchWeatherByLocation（regeo 取 adcode → weatherInfo
取实况）；recording_task_handler 与 recording_page 改用高德天气，
消息传 condition + temperature，pill 显示 emoji+标签+温度。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 删除和风服务与和风映射表

**Files:**
- Delete: `lib/services/weather_service.dart`
- Modify: `lib/models/diary_entry.dart`

- [ ] **Step 1: 确认无残留引用**

Run: `grep -rn "weather_service\|WeatherService\|WeatherLocation\|fetchWeatherAndLocation\|weatherEmoji\|_weatherEmojiMap" lib/`
Expected: 仅剩 `lib/models/diary_entry.dart` 内 `weatherEmoji`/`_weatherEmojiMap` 定义（无外部引用）。`weather_service.dart` 仅自身定义，无 import。

若仍有引用：回到对应 Task 修复后再继续。

- [ ] **Step 2: 删除 weather_service.dart**

Run: `git rm lib/services/weather_service.dart`

- [ ] **Step 3: diary_entry.dart 删除和风映射表**

Modify `lib/models/diary_entry.dart`：删除 `weatherEmoji` 静态方法与整个 `_weatherEmojiMap` 常量（约第 97-153 行），即：

```dart
  /// 和风天气图标代码 → emoji 映射
  static String? weatherEmoji(String iconCode) => _weatherEmojiMap[iconCode];

  static const _weatherEmojiMap = { ... };  // 整个 map
```

删除后该文件不再有和风相关代码。

- [ ] **Step 4: 分析 + 全部测试**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` + `All tests passed!`

- [ ] **Step 5: 格式化 + 提交**

Run: `dart format lib/models/diary_entry.dart`

```bash
git add lib/models/diary_entry.dart
git commit -m "$(cat <<'EOF'
chore: 删除和风天气服务与和风代码→emoji 映射表

weather_service.dart 已无引用，和风映射表已被枚举取代，一并移除。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: 清理和风环境变量与构建校验

**Files:**
- Modify: `.env.local.example`
- Modify: `scripts/build.sh`
- Modify: `CLAUDE.md`

- [ ] **Step 1: .env.local.example 删除和风段**

Modify `.env.local.example`：删除以下 3 行：

```
# 和风天气（天气 + 逆地理编码）
QWEATHER_TOKEN=your_qweather_token_here
QWEATHER_HOST=devapi.qweather.com
```

保留 `# 高德地图 Web 服务…` 与 `AMAP_WEB_KEY=...`，并把注释补全为「位置地标逆地理 + 天气实况」：

```
# 高德地图 Web 服务（位置地标逆地理 + 天气实况）
AMAP_WEB_KEY=your_amap_web_key_here
```

- [ ] **Step 2: build.sh 移除 QWEATHER_TOKEN 校验**

Modify `scripts/build.sh`：

1. `REQUIRED_ENV_VARS` 数组中删除 `QWEATHER_TOKEN` 一行。
2. 第 13 行注释 `# WORKTREE 仅 dev flavor 使用、QWEATHER_HOST 有默认值，故不列入。` 改为 `# WORKTREE 仅 dev flavor 使用，故不列入。`

- [ ] **Step 3: CLAUDE.md 环境变量清单删除 QWEATHER_TOKEN**

Modify `CLAUDE.md`：

1. 「prod 必需变量」清单删除 `- QWEATHER_TOKEN — 和风天气（天气 + 逆地理编码）` 整行。
2. 该清单的 `- AMAP_WEB_KEY — 高德地图（位置地标逆地理）` 改为 `- AMAP_WEB_KEY — 高德地图（位置地标逆地理 + 天气实况）`。
3. 该清单下方 `> QWEATHER_HOST 有默认值、WORKTREE 仅 dev flavor 使用，故未列入 prod 必需项。` 改为 `> WORKTREE 仅 dev flavor 使用，故未列入 prod 必需项。`
4. 若 CLAUDE.md 其他处提及和风/QWEATHER，一并清理（搜索 `QWEATHER`/`和风`）。

- [ ] **Step 4: 确认全库无 QWEATHER 残留**

Run: `grep -rn "QWEATHER\|qweather\|和风" lib/ scripts/ CLAUDE.md .env.local.example`
Expected: 无输出（.env.local 实际文件由用户自行删除，不在版本控制内，可忽略）。

- [ ] **Step 5: 提交**

```bash
git add .env.local.example scripts/build.sh CLAUDE.md
git commit -m "$(cat <<'EOF'
chore: 移除和风天气环境变量与 prod 构建校验

.env.local.example、scripts/build.sh 的 REQUIRED_ENV_VARS、CLAUDE.md
清单同步移除 QWEATHER_TOKEN/QWEATHER_HOST，AMAP_WEB_KEY 注释补全
含天气实况用途。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: 全量验证

- [ ] **Step 1: 全量格式化 + 分析**

Run: `dart format lib/ test/ && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 3: 搜索和风残留**

Run: `grep -rni "qweather\|和风\|weather_service\|weatherEmoji\|WeatherLocation" lib/ test/`
Expected: 无输出。

- [ ] **Step 4: 手动验证（dev 构建）**

Run: `./scripts/run_dev.sh`

验证项：
1. 启动不崩（migration 自动执行，历史记录天气正常）。
2. 录音 → 录音中天气 pill 显示 `🌦️ 阵雨 24°` 格式（取决于当前真实天气）。
3. 录音结束 → 详情页 DetailInfoBar 显示天气片段 + 温度。
4. 列表页天气摘要为 `地名 emoji标签 温度°`。
5. 每日总结页 AppBar 显示聚合天气。
6. 历史记录（迁移前已有 weather_icon 的）天气仍正常显示（枚举渲染，非空）。

> 若 `.env.local` 仍含 `QWEATHER_TOKEN`，提示用户手动删除（不影响运行，仅冗余）。

- [ ] **Step 5（可选）: prod 编译校验**

确认 `.env.local` 已删除 `QWEATHER_*` 后：

Run: `./scripts/build.sh`
Expected: 编译成功（`REQUIRED_ENV_VARS` 不再要求 QWEATHER_TOKEN）。

---

## 自审 Checklist（执行前已通过）

- [x] spec 每节均有对应 task（枚举 Task1、migration Task2、DiaryEntry Task3、daily_summary Task4、detail Task5、高德接入/录音 Task6、删和风 Task7、环境变量 Task8、验证 Task9）。
- [x] 无占位符：所有代码步骤含完整代码。
- [x] 类型一致：`WeatherCondition`、`effectiveCondition`、`fetchWeatherByLocation` 返回类型 `({WeatherCondition condition, String temperature})?`、`DayWeatherSummary.condition` 在各 task 间命名一致。
- [x] 编译顺序：`weatherEmoji` 删除放在所有引用方（daily_summary/detail/recording_page）迁移之后（Task 7），中间任务均可编译。

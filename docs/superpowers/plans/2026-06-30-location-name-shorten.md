# 位置信息精简（缩短为纯地标名）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 高德 POI 为空时不再返回冗长完整地址，改为用结构化字段去行政前缀的纯地标名；历史日记一并重新解析变短。

**Architecture:** 生成时精简——在 `AmapService` 抽出 3 个公开纯函数（`stripAdminPrefix`/`truncatePoiName`/`parseRegeoForLocation`），`nearestPoiOrAddress` 发完请求直接调 `parseRegeoForLocation` 返回精简名。历史数据复用 `LocationResolveMigration`，把一次性 bool 标志升级为版本化守卫（`_currentVersion=2`），所有设备首启重跑一次自动用新逻辑重解析。不改 schema、不改 UI、不改 `LocationResolver`。

**Tech Stack:** Flutter / Dart、dio（高德 HTTP）、SharedPreferences（迁移标志）、mocktail（测试）。

**提交约定（每个 task 通用）：** 提交前对改动文件运行 `dart format <files>`，运行 `flutter analyze` 至 `No issues found!`，再执行 task 末尾的 `git commit`。commit message 用中文。**仅本地 commit，不 push。**

**并行执行：** Task 1（`amap_service.dart`）与 Task 2（`location_resolve_migration.dart`）改动文件完全不重叠，可派两个 subagent **并行执行**。

**与 spec 的差异（测试策略优化）：** spec §8 原写「mock dio 测 `nearestPoiOrAddress`」，但 `AmapService` 内部硬编码 `_dio = Dio(...)` 不可注入、mock 网络层成本高。本计划改为把解析逻辑抽成纯函数 `parseRegeoForLocation`，测纯函数（无需 mock dio），`nearestPoiOrAddress` 仅作 IO 薄壳。同时把 spec 中的私有 `_truncatePoiName` 改为公开 `truncatePoiName` 以便测试访问。目标与行为与 spec 完全一致，仅测试手段更优。

---

## File Structure

**修改：**
- `lib/services/amap_service.dart` — 新增 3 个公开纯函数 + `nearestPoiOrAddress` 改调 `parseRegeoForLocation`
- `lib/services/location_resolve_migration.dart` — bool 标志 → 版本化守卫

**新增：**
- `test/amap_service_test.dart` — 纯函数单测（`stripAdminPrefix`/`truncatePoiName`/`parseRegeoForLocation`）

**更新：**
- `test/location_resolve_migration_test.dart` — 新增「遗留旧 bool 标志仍判定未完成」测试

**不改：** `location_resolver.dart`、`recording_task_handler.dart`、`main.dart`、所有 UI、`tables.dart`/`app_database.dart`（无 schema 变更）、`fetchWeatherByLocation`。

---

### Task 1: AmapService 位置精简

**Files:**
- Modify: `lib/services/amap_service.dart`
- Create: `test/amap_service_test.dart`

- [ ] **Step 1: 写失败测试（stripAdminPrefix + truncatePoiName）**

创建 `test/amap_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/amap_service.dart';

void main() {
  group('stripAdminPrefix', () {
    test('去掉省/区前缀，保留核心（直辖市）', () {
      expect(
        stripAdminPrefix(
          '北京市朝阳区建国门外大街1号中国国际贸易中心',
          province: '北京市',
          city: <String>[],
          district: '朝阳区',
        ),
        '建国门外大街1号中国国际贸易中心',
      );
    });

    test('普通地级市剥离省+市+区', () {
      expect(
        stripAdminPrefix(
          '陕西省西安市雁塔区高新路1号',
          province: '陕西省',
          city: '西安市',
          district: '雁塔区',
        ),
        '高新路1号',
      );
    });

    test('直辖市 city 为空字符串不报错', () {
      expect(
        stripAdminPrefix(
          '天津市和平区南京路1号',
          province: '天津市',
          city: '',
          district: '和平区',
        ),
        '南京路1号',
      );
    });

    test('剥离后为空 → 回退 district', () {
      expect(
        stripAdminPrefix(
          '北京市朝阳区',
          province: '北京市',
          city: <String>[],
          district: '朝阳区',
        ),
        '朝阳区',
      );
    });

    test('district 也剥离后为空 → 回退 formatted', () {
      expect(
        stripAdminPrefix(
          '北京市',
          province: '北京市',
          city: <String>[],
          district: '',
        ),
        '北京市',
      );
    });

    test('不以 province 开头 → 原样 trim 返回', () {
      expect(
        stripAdminPrefix(
          '星巴克国贸店',
          province: '北京市',
          city: <String>[],
          district: '朝阳区',
        ),
        '星巴克国贸店',
      );
    });

    test('前缀均为 null → 仅 trim', () {
      expect(stripAdminPrefix('  中关村大街1号  '), '中关村大街1号');
    });
  });

  group('truncatePoiName', () {
    test('恰好 12 字符不截断', () {
      expect(truncatePoiName('123456789012'), '123456789012');
    });

    test('13 字符截断为前 11 + …', () {
      expect(truncatePoiName('1234567890123'), '12345678901…');
    });

    test('中文短名原样返回', () {
      expect(truncatePoiName('中国贸易中心'), '中国贸易中心');
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/amap_service_test.dart`
Expected: FAIL — `stripAdminPrefix` / `truncatePoiName` 未定义（`Error: Method not found`）。

- [ ] **Step 3: 实现 stripAdminPrefix + _cityString + truncatePoiName**

在 `lib/services/amap_service.dart` 文件顶部、`class AmapService` 声明**之前**，新增以下顶层纯函数：

```dart
// === 位置名精简纯函数（不依赖 dio，便于单测）===

/// POI 名最大字符数（超出截断）。
const int kPoiNameMaxLength = 12;

/// POI 名超长截断：超 [max] 字符则取前 max-1 字 + 「…」。
String truncatePoiName(String name, {int max = kPoiNameMaxLength}) {
  if (name.length > max) return '${name.substring(0, max - 1)}…';
  return name;
}

/// 高德 city 字段归一化为 nullable String。
/// 高德对直辖市返回空数组 [] 或空串，普通市返回市名。
String? _cityString(dynamic city) {
  if (city == null) return null;
  if (city is List) return city.isEmpty ? null : city.first?.toString();
  if (city is String && city.isNotEmpty) return city;
  return null;
}

/// 从 formatted_address 头部依次剥离 province/city/district 行政前缀。
/// 剥离后为空则回退 district，仍空则返回原 formatted（保证非空）。
String stripAdminPrefix(
  String formatted, {
  String? province,
  dynamic city,
  String? district,
}) {
  final cityStr = _cityString(city);
  var result = formatted;
  for (final prefix in [province, cityStr, district]) {
    if (prefix != null && prefix.isNotEmpty && result.startsWith(prefix)) {
      result = result.substring(prefix.length);
    }
  }
  result = result.trim();
  if (result.isEmpty) {
    return (district != null && district.isNotEmpty) ? district : formatted;
  }
  return result;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/amap_service_test.dart`
Expected: PASS（全部 stripAdminPrefix / truncatePoiName 用例）。

- [ ] **Step 5: 追加 parseRegeoForLocation 失败测试**

在 `test/amap_service_test.dart` 的 `main()` 内追加一个 group：

```dart
  group('parseRegeoForLocation', () {
    // 构造高德 regeo 响应的辅助函数
    Map<String, dynamic> regeo({
      List<Map<String, dynamic>>? pois,
      String formatted = '',
      String province = '',
      dynamic city,
      String district = '',
      String status = '1',
    }) =>
        {
          'status': status,
          'regeocode': {
            if (pois != null) 'pois': pois,
            'formatted_address': formatted,
            'addressComponent': {
              'province': province,
              'city': city ?? <String>[],
              'district': district,
            },
          },
        };

    test('POI 命中 → 返回 POI 名', () {
      final data = regeo(pois: [
        {'name': '星巴克(国贸店)'},
      ]);
      expect(parseRegeoForLocation(data), '星巴克(国贸店)');
    });

    test('POI 名超长 → 截断', () {
      final data = regeo(pois: [
        {'name': '1234567890123'},
      ]);
      expect(parseRegeoForLocation(data), '12345678901…');
    });

    test('POI 为空、formatted 含省市区 → 去前缀核心', () {
      final data = regeo(
        formatted: '北京市朝阳区建国门外大街1号中国国际贸易中心',
        province: '北京市',
        city: <String>[],
        district: '朝阳区',
      );
      expect(parseRegeoForLocation(data), '建国门外大街1号中国国际贸易中心');
    });

    test('POI name 为空串 → 走 formatted 去前缀', () {
      final data = regeo(
        pois: [
          {'name': ''},
        ],
        formatted: '陕西省西安市雁塔区高新路1号',
        province: '陕西省',
        city: '西安市',
        district: '雁塔区',
      );
      expect(parseRegeoForLocation(data), '高新路1号');
    });

    test('addressComponent 缺失 → formatted 原样返回（降级）', () {
      final data = {
        'status': '1',
        'regeocode': {
          'formatted_address': '某市某区某路1号',
        },
      };
      expect(parseRegeoForLocation(data), '某市某区某路1号');
    });

    test('status≠1 → null', () {
      expect(
        parseRegeoForLocation({'status': '0', 'info': 'INVALID_USER_KEY'}),
        isNull,
      );
    });

    test('regeocode 缺失 → null', () {
      expect(parseRegeoForLocation({'status': '1'}), isNull);
    });

    test('POI 空 + formatted 空 → null', () {
      expect(parseRegeoForLocation(regeo()), isNull);
    });
  });
```

- [ ] **Step 6: 跑测试确认失败**

Run: `flutter test test/amap_service_test.dart`
Expected: FAIL — `parseRegeoForLocation` 未定义。

- [ ] **Step 7: 实现 parseRegeoForLocation**

在 `lib/services/amap_service.dart` 的 `stripAdminPrefix` 函数之后、`class AmapService` 之前，新增：

```dart
/// 从高德 regeo 完整响应解析精简位置名：
/// ① POI 命中 → POI 名（超长截断）
/// ② POI 为空 → formatted_address 去行政前缀
/// 无数据 / status≠1 / 字段缺失降级失败 → null。纯函数，不依赖 dio。
String? parseRegeoForLocation(Map<String, dynamic> data) {
  if (data['status']?.toString() != '1') return null;
  final regeocode = data['regeocode'] as Map<String, dynamic>?;
  if (regeocode == null) return null;
  final addrComp = regeocode['addressComponent'] as Map<String, dynamic>?;

  final pois = regeocode['pois'] as List?;
  if (pois != null && pois.isNotEmpty) {
    final name = (pois[0]['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return truncatePoiName(name);
  }

  final formatted = (regeocode['formatted_address'] as String?)?.trim() ?? '';
  if (formatted.isEmpty) return null;
  return stripAdminPrefix(
    formatted,
    province: addrComp?['province']?.toString(),
    city: addrComp?['city'],
    district: addrComp?['district']?.toString(),
  );
}
```

- [ ] **Step 8: 跑测试确认通过**

Run: `flutter test test/amap_service_test.dart`
Expected: PASS（全部用例）。

- [ ] **Step 9: 改造 nearestPoiOrAddress 调 parseRegeoForLocation**

将 `lib/services/amap_service.dart` 中 `nearestPoiOrAddress` 方法体替换为（保留方法签名、`_ensureInitialized`、key 校验、DioException/catch 不变，仅把原手动解析 pois/formatted_address 的段落改为调纯函数）：

```dart
  /// 取最近 POI 名；POI 为空则取去前缀的 formatted_address；失败/未配置返回 null。
  Future<String?> nearestPoiOrAddress(double lat, double lon) async {
    _ensureInitialized();
    final key = _key;
    if (key == null || key.isEmpty) {
      debugPrint('[高德] 未配置 AMAP_WEB_KEY，跳过逆地理');
      return null;
    }

    try {
      final locParam = '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}';
      debugPrint('[高德] 请求 regeo: loc=$locParam');
      final resp = await _dio.get(
        'https://restapi.amap.com/v3/geocode/regeo',
        queryParameters: {
          'key': key,
          'location': locParam,
          'radius': 1000,
          'extensions': 'base',
          'output': 'json',
        },
      );

      final data = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : <String, dynamic>{};
      final result = parseRegeoForLocation(data);
      if (result == null && data['status']?.toString() != '1') {
        debugPrint('[高德] regeo 失败 status=${data['status']}, body=$data');
      }
      return result;
    } on DioException catch (e) {
      debugPrint(
        '[高德] HTTP 错误: status=${e.response?.statusCode}, body=${e.response?.data}',
      );
      return null;
    } catch (e) {
      debugPrint('[高德] 解析失败: $e');
      return null;
    }
  }
```

> `fetchWeatherByLocation` 方法保持不变。

- [ ] **Step 10: 跑全量测试确认无回归**

Run: `flutter test test/amap_service_test.dart test/location_resolver_test.dart`
Expected: PASS（`location_resolver_test` mock 的是 `AmapService` 整体，不受内部改动影响；amap 纯函数测试全绿）。

- [ ] **Step 11: 格式化 + 静态分析**

Run: `dart format lib/services/amap_service.dart test/amap_service_test.dart`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 12: 提交**

```bash
git add lib/services/amap_service.dart test/amap_service_test.dart
git commit -m "$(cat <<'EOF'
feat: 位置信息精简为纯地标名

高德 POI 为空时不再返回完整 formatted_address，改用结构化字段
（province/city/district）确定性去行政前缀，只留核心地标名；
POI 名超 12 字截断。抽出 stripAdminPrefix/truncatePoiName/
parseRegeoForLocation 三个纯函数便于单测，nearestPoiOrAddress
改为发请求后调纯函数。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: LocationResolveMigration 版本化守卫

**Files:**
- Modify: `lib/services/location_resolve_migration.dart`
- Update: `test/location_resolve_migration_test.dart`

- [ ] **Step 1: 写失败测试（遗留旧 bool 标志仍判定未完成）**

在 `test/location_resolve_migration_test.dart` 的 `main()` 内、最后一个测试之后追加：

```dart
  test('遗留旧 bool 标志位时，版本化守卫仍判定未完成（需重跑）', () async {
    // 模拟已发布设备：v1 迁移跑过，遗留旧的 bool 标志 true
    SharedPreferences.setMockInitialValues({
      'location_resolve_migration_done': true,
    });
    // 新版本化守卫读 _versionKey（不存在→0），0 < 2 → 未完成，需重跑
    expect(await LocationResolveMigration.isDone(), isFalse);
  });

  test('run 成功后写入当前版本，isDone 为 true', () async {
    SharedPreferences.setMockInitialValues({});
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => const []);

    await migration.run();

    expect(await LocationResolveMigration.isDone(), isTrue);
  });
```

> 现有 4 个测试（`setUp` 用 `SharedPreferences.setMockInitialValues({})`）在版本化改动后语义不变，仍应通过：成功→isDone true、失败→isDone false。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/location_resolve_migration_test.dart`
Expected: 第一个新测试 FAIL — 旧实现读 bool `_doneKey`=true → `isDone()` 返回 true，断言 `isFalse` 失败。

- [ ] **Step 3: 实现版本化守卫**

修改 `lib/services/location_resolve_migration.dart`：

(a) 把常量
```dart
  static const _doneKey = 'location_resolve_migration_done';
```
替换为版本化常量：
```dart
  static const _versionKey = 'location_resolve_migration_version';
  static const int _currentVersion = 2; // 本次精简 = v2
```

(b) 把 `isDone` 方法
```dart
  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_doneKey) ?? false;
  }
```
替换为：
```dart
  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getInt(_versionKey) ?? 0;
    return done >= _currentVersion;
  }
```

(c) 把 `run()` 末尾的完成标记
```dart
    if (failed == 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_doneKey, true);
    }
```
替换为：
```dart
    if (failed == 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_versionKey, _currentVersion);
    }
```

> 旧的 bool key `location_resolve_migration_done` 不再读写。已发布设备上残留的该 bool 值不影响新逻辑（新代码只读 `_versionKey`，默认 0 < 2 → 触发重跑）。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/location_resolve_migration_test.dart`
Expected: PASS（含 2 个新测试 + 现有 4 个测试，共 6 个）。

- [ ] **Step 5: 格式化 + 静态分析**

Run: `dart format lib/services/location_resolve_migration.dart test/location_resolve_migration_test.dart`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/location_resolve_migration.dart test/location_resolve_migration_test.dart
git commit -m "$(cat <<'EOF'
feat: 位置回填迁移升级为版本化守卫

将一次性 bool 标志升级为版本化（_currentVersion=2），使已跑过
v1 的设备在本次发布后重跑一次迁移，用新的位置精简逻辑重新解析
全部历史日记的 locationName。run() 逻辑不变，只改版本守卫与
写入字段；仍只 UPDATE locationName，不动其他数据。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## 全局收尾（两 task 都合并后）

- [ ] **跑全量测试：** `flutter test` → 全绿。
- [ ] **全量静态分析：** `flutter analyze` → `No issues found!`。
- [ ] **手动验证（dev 构建）：** `./scripts/run_dev.sh`，陌生地点录音 → 详情页 chip 显示精简地标名（非完整省市地址）；旧日记在首启后被重新解析变短。

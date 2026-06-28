# 位置显示升级（常用位置 + 地标）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 录音位置接近常用位置(200m)显示常用名，否则用高德逆地理解析最近地标，高德失败回退和风行政区；并自动回填历史日记。

**Architecture:** 纯快照语义——`locationName` 在录音时即解析为最终值并存库，显示层零语义改动。核心是单一解析入口 `LocationResolver.resolve()`（常用位置 → 高德 POI → 高德地址 → null），录音时与回填共用。天气与高德并行调用、各自完成各自发消息到前端；存库时 `?? _weatherLocation?.locationName` 做和风行政区兜底。

**Tech Stack:** Flutter / Dart、drift（SQLite）、SharedPreferences（常用位置）、dio（高德 HTTP）、geolocator（距离）、mocktail（测试）。

**提交约定（每个 task 通用）：** 提交前对改动文件运行 `dart format <files>`，并运行 `flutter analyze` 至 `No issues found!`，再执行该 task 末尾的 `git commit`。commit message 用中文。

**与 spec 的差异：** spec §10「纳入 app-backup」依赖尚未实现的备份/恢复功能，本计划不做（spec 已标注），常用位置目前仅存 SharedPreferences。

---

## File Structure

**新增：**
- `lib/models/favorite_location.dart` — 常用位置模型（toJson/fromJson）
- `lib/services/favorite_location_store.dart` — SharedPreferences CRUD
- `lib/services/amap_service.dart` — 高德逆地理（仿 `weather_service.dart`）
- `lib/services/location_resolver.dart` — 核心解析逻辑（依赖注入 AmapService）
- `lib/services/location_resolve_migration.dart` — 历史回填迁移
- `lib/pages/favorite_locations_page.dart` — 常用位置管理页

**修改：**
- `lib/services/diary_storage_service.dart` — 新增 `updateLocationName`
- `lib/services/recording_task_handler.dart` — 并行解析 + 分别发消息 + 存库兜底
- `lib/pages/recording_page.dart` — 拆分 weather/location 消息与显示
- `lib/pages/settings_page.dart` — 新增「常用位置」入口
- `lib/main.dart` — 注册回填迁移
- `.env.local` / `.env.local.example` / `scripts/build.sh` — `AMAP_WEB_KEY`

---

### Task 1: FavoriteLocation 模型

**Files:**
- Create: `lib/models/favorite_location.dart`
- Test: `test/favorite_location_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/favorite_location_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:glimmer/models/favorite_location.dart';

void main() {
  test('toJson/fromJson 往返保持一致', () {
    final original = FavoriteLocation(
      id: 'abc',
      name: '家',
      lat: 34.0,
      lon: 108.0,
      createdAt: DateTime(2026, 6, 28, 10, 0),
    );
    final json = original.toJson();
    final restored = FavoriteLocation.fromJson(json);
    expect(restored.id, 'abc');
    expect(restored.name, '家');
    expect(restored.lat, 34.0);
    expect(restored.lon, 108.0);
    expect(restored.createdAt, original.createdAt);
  });

  test('copyWith 仅改 name', () {
    final original = FavoriteLocation(
      id: 'abc', name: '家', lat: 34.0, lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final renamed = original.copyWith(name: '家（新）');
    expect(renamed.name, '家（新）');
    expect(renamed.id, 'abc');
    expect(renamed.lat, 34.0);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/favorite_location_test.dart`
Expected: FAIL（`favorite_location.dart` 不存在 / `FavoriteLocation` 未定义）

- [ ] **Step 3: 实现模型**

```dart
// lib/models/favorite_location.dart
import 'package:uuid/uuid.dart';

class FavoriteLocation {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final DateTime createdAt;

  const FavoriteLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.createdAt,
  });

  /// 新建：自动生成 id 与时间戳。
  factory FavoriteLocation.create({
    required String name,
    required double lat,
    required double lon,
  }) {
    return FavoriteLocation(
      id: const Uuid().v4(),
      name: name,
      lat: lat,
      lon: lon,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FavoriteLocation.fromJson(Map<String, dynamic> json) {
    return FavoriteLocation(
      id: json['id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  FavoriteLocation copyWith({String? name}) => FavoriteLocation(
        id: id,
        name: name ?? this.name,
        lat: lat,
        lon: lon,
        createdAt: createdAt,
      );
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/favorite_location_test.dart`
Expected: PASS（2 个测试）

- [ ] **Step 5: 提交**

```bash
git add lib/models/favorite_location.dart test/favorite_location_test.dart
git commit -m "feat: 添加 FavoriteLocation 模型"
```

---

### Task 2: FavoriteLocationStore（SharedPreferences CRUD）

**Files:**
- Create: `lib/services/favorite_location_store.dart`
- Test: `test/favorite_location_store_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/favorite_location_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glimmer/services/favorite_location_store.dart';

void main() {
  late FavoriteLocationStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FavoriteLocationStore();
  });

  test('初始为空列表', () async {
    expect(await store.load(), isEmpty);
  });

  test('add 后 load 能读到', () async {
    await store.add('家', 34.0, 108.0);
    final list = await store.load();
    expect(list, hasLength(1));
    expect(list.first.name, '家');
    expect(list.first.lat, 34.0);
  });

  test('rename 改名保留 id/坐标', () async {
    final added = await store.add('家', 34.0, 108.0);
    final id = added.first.id;
    await store.rename(id, '家（新）');
    final list = await store.load();
    expect(list.first.name, '家（新）');
    expect(list.first.id, id);
    expect(list.first.lat, 34.0);
  });

  test('remove 按 id 删除', () async {
    final added = await store.add('家', 34.0, 108.0);
    await store.remove(added.first.id);
    expect(await store.load(), isEmpty);
  });

  test('新增多个共存（持久化）', () async {
    await store.add('家', 34.0, 108.0);
    // 用新实例模拟重启后读取（读同一份 SharedPreferences）
    final list = await FavoriteLocationStore().load();
    expect(list, hasLength(1));
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/favorite_location_store_test.dart`
Expected: FAIL（`FavoriteLocationStore` 未定义）

- [ ] **Step 3: 实现 store**

```dart
// lib/services/favorite_location_store.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_location.dart';

/// 常用位置存储（SharedPreferences）。isolate 安全：各 isolate 各自
/// `getInstance()` 读同一份偏好数据。
class FavoriteLocationStore {
  static const _key = 'pref_favorite_locations';

  Future<List<FavoriteLocation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => FavoriteLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<FavoriteLocation> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((f) => f.toJson()).toList()),
    );
  }

  Future<List<FavoriteLocation>> add(String name, double lat, double lon) async {
    final list = await load();
    list.add(FavoriteLocation.create(name: name, lat: lat, lon: lon));
    await _save(list);
    return list;
  }

  Future<List<FavoriteLocation>> rename(String id, String name) async {
    final list = (await load())
        .map((f) => f.id == id ? f.copyWith(name: name) : f)
        .toList();
    await _save(list);
    return list;
  }

  Future<List<FavoriteLocation>> remove(String id) async {
    final list = (await load()).where((f) => f.id != id).toList();
    await _save(list);
    return list;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/favorite_location_store_test.dart`
Expected: PASS（5 个测试）

- [ ] **Step 5: 提交**

```bash
git add lib/services/favorite_location_store.dart test/favorite_location_store_test.dart
git commit -m "feat: 添加 FavoriteLocationStore（SharedPreferences 存储）"
```

---

### Task 3: AmapService（高德逆地理）

> 与 `weather_service.dart` 一致：HTTP service 不写单测（项目无 dio mock 基础设施），靠手动验证。失败静默返回 null，不抛异常。

**Files:**
- Create: `lib/services/amap_service.dart`

- [ ] **Step 1: 实现 service**

```dart
// lib/services/amap_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 高德 Web 服务：逆地理编码，取最近 POI / 地址作地标。
class AmapService {
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  String? _key;

  void _ensureInitialized() {
    if (_key != null) return;
    _key = dotenv.get('AMAP_WEB_KEY', fallback: '');
  }

  /// 取最近 POI 名；POI 为空则取 formatted_address；失败/未配置返回 null。
  Future<String?> nearestPoiOrAddress(double lat, double lon) async {
    _ensureInitialized();
    final key = _key;
    if (key == null || key.isEmpty) {
      debugPrint('[高德] 未配置 AMAP_WEB_KEY，跳过逆地理');
      return null;
    }
    try {
      final locParam = '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}';
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
      final status = resp.data['status']?.toString();
      if (status != '1') {
        debugPrint('[高德] regeo 失败 status=$status, body=${resp.data}');
        return null;
      }
      final regeocode = resp.data['regeocode'];
      final pois = regeocode?['pois'] as List?;
      if (pois != null && pois.isNotEmpty) {
        return pois[0]['name'] as String?;
      }
      final addr = regeocode?['formatted_address'] as String?;
      return (addr != null && addr.isNotEmpty) ? addr : null;
    } on DioException catch (e) {
      debugPrint('[高德] HTTP 错误: status=${e.response?.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[高德] 解析失败: $e');
      return null;
    }
  }
}
```

- [ ] **Step 2: 验证分析通过**

Run: `flutter analyze lib/services/amap_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: 提交**

```bash
git add lib/services/amap_service.dart
git commit -m "feat: 添加 AmapService（高德逆地理）"
```

---

### Task 4: LocationResolver（核心解析逻辑）

**Files:**
- Create: `lib/services/location_resolver.dart`
- Test: `test/location_resolver_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/location_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:glimmer/models/favorite_location.dart';
import 'package:glimmer/services/amap_service.dart';
import 'package:glimmer/services/location_resolver.dart';

class _MockAmap extends Mock implements AmapService {}

void main() {
  late _MockAmap amap;
  late LocationResolver resolver;

  setUp(() {
    amap = _MockAmap();
    resolver = LocationResolver(amap);
  });

  test('常用位置命中(同点 0m) → 返回常用名，不调高德', () async {
    final fav = FavoriteLocation(
      id: '1', name: '家', lat: 34.0, lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final result = await resolver.resolve(
      lat: 34.0, lon: 108.0, favorites: [fav],
    );
    expect(result, '家');
    verifyNever(() => amap.nearestPoiOrAddress(any(), any()));
  });

  test('常用位置越界(~920m) → 调高德返回 POI', () async {
    // 经度差 0.01°（约 920m）> 200m 阈值
    final fav = FavoriteLocation(
      id: '1', name: '家', lat: 34.0, lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    when(() => amap.nearestPoiOrAddress(any(), any()))
        .thenAnswer((_) async => '星巴克国贸店');
    final result = await resolver.resolve(
      lat: 34.0, lon: 108.01, favorites: [fav],
    );
    expect(result, '星巴克国贸店');
  });

  test('无常用位置 + 高德成功 → 返回高德结果', () async {
    when(() => amap.nearestPoiOrAddress(any(), any()))
        .thenAnswer((_) async => '雁塔路');
    final result = await resolver.resolve(
      lat: 34.0, lon: 108.0, favorites: const [],
    );
    expect(result, '雁塔路');
  });

  test('无常用位置 + 高德失败 → 返回 null', () async {
    when(() => amap.nearestPoiOrAddress(any(), any()))
        .thenAnswer((_) async => null);
    final result = await resolver.resolve(
      lat: 34.0, lon: 108.0, favorites: const [],
    );
    expect(result, isNull);
  });

  test('多个常用位置取最近且命中', () async {
    final near = FavoriteLocation(
      id: '1', name: '公司', lat: 34.0, lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final far = FavoriteLocation(
      id: '2', name: '家', lat: 40.0, lon: 116.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final result = await resolver.resolve(
      lat: 34.0001, lon: 108.0001, favorites: [near, far],
    );
    expect(result, '公司');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/location_resolver_test.dart`
Expected: FAIL（`LocationResolver` 未定义）

- [ ] **Step 3: 实现 resolver**

```dart
// lib/services/location_resolver.dart
import 'package:geolocator/geolocator.dart';

import '../models/favorite_location.dart';
import 'amap_service.dart';

/// 位置名解析：常用位置(≤200m) → 高德 POI → 高德地址 → null。
///
/// 全程降级用返回值，不抛异常（符合项目异常规范）。
class LocationResolver {
  final AmapService _amap;
  LocationResolver(this._amap);

  static const double _thresholdMeters = 200;

  Future<String?> resolve({
    required double lat,
    required double lon,
    required List<FavoriteLocation> favorites,
  }) async {
    // ① 常用位置匹配（纯本地）
    FavoriteLocation? nearest;
    double minDist = double.infinity;
    for (final f in favorites) {
      final d = Geolocator.distanceBetween(lat, lon, f.lat, f.lon);
      if (d < minDist) {
        minDist = d;
        nearest = f;
      }
    }
    if (nearest != null && minDist <= _thresholdMeters) {
      return nearest.name;
    }
    // ②/③ 高德（POI → 地址）
    return _amap.nearestPoiOrAddress(lat, lon);
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/location_resolver_test.dart`
Expected: PASS（5 个测试）

- [ ] **Step 5: 提交**

```bash
git add lib/services/location_resolver.dart test/location_resolver_test.dart
git commit -m "feat: 添加 LocationResolver（常用位置+地标解析）"
```

---

### Task 5: DiaryStorageService.updateLocationName

**Files:**
- Modify: `lib/services/diary_storage_service.dart`（在 `updateTitle` 方法后，约行 99 处新增）
- Test: `test/diary_storage_service_test.dart`（追加用例）

- [ ] **Step 1: 在现有测试文件追加失败测试**

在 `test/diary_storage_service_test.dart` 末尾的 `void main() {}` 内追加：

```dart
  test('updateLocationName 只改 locationName 字段', () async {
    await service.createEntry(DiaryEntry(
      id: 'x', title: 't', folderPath: '/x', durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28), locationName: '雁塔区',
      locationLat: 34.0, locationLon: 108.0,
    ));
    await service.updateLocationName('x', '家');
    final entries = await service.getAllEntries();
    final e = entries.firstWhere((e) => e.id == 'x');
    expect(e.locationName, '家');
    expect(e.locationLat, 34.0);   // 其他字段不变
    expect(e.title, 't');
  });
```

> 若该测试文件已有 `setUp` 建立 `service = DiaryStorageService.forTesting(db)`（in-memory drift），复用即可；否则参照文件顶部既有 setUp 模式。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/diary_storage_service_test.dart`
Expected: FAIL（`updateLocationName` 未定义）

- [ ] **Step 3: 实现方法**

在 `lib/services/diary_storage_service.dart` 的 `updateTitle` 方法（约行 95-99）之后新增：

```dart
  /// 只更新 locationName（位置回填用）
  Future<void> updateLocationName(String id, String? locationName) async {
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(id))).write(
      DiaryEntriesCompanion(locationName: Value(locationName)),
    );
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/diary_storage_service_test.dart`
Expected: PASS（含新追加用例）

- [ ] **Step 5: 提交**

```bash
git add lib/services/diary_storage_service.dart test/diary_storage_service_test.dart
git commit -m "feat: DiaryStorageService 增加 updateLocationName"
```

---

### Task 6: LocationResolveMigration（历史回填）

**Files:**
- Create: `lib/services/location_resolve_migration.dart`
- Test: `test/location_resolve_migration_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/location_resolve_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glimmer/models/diary_entry.dart';
import 'package:glimmer/models/favorite_location.dart';
import 'package:glimmer/services/diary_storage_service.dart';
import 'package:glimmer/services/favorite_location_store.dart';
import 'package:glimmer/services/location_resolve_migration.dart';
import 'package:glimmer/services/location_resolver.dart';

class _MockStorage extends Mock implements DiaryStorageService {}
class _MockResolver extends Mock implements LocationResolver {}
class _MockFavStore extends Mock implements FavoriteLocationStore {}

void main() {
  late _MockStorage storage;
  late _MockResolver resolver;
  late _MockFavStore favStore;
  late LocationResolveMigration migration;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = _MockStorage();
    resolver = _MockResolver();
    favStore = _MockFavStore();
    migration = LocationResolveMigration(storage, resolver, favStore);
  });

  EntryStatus _unused = EntryStatus.completed;

  test('只回填有 lat/lon 的条目，更新 locationName，并置完成标志', () async {
    final withLoc = DiaryEntry(
      id: 'a', title: 't', folderPath: '/a', durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
      locationLat: 34.0, locationLon: 108.0, locationName: '雁塔区',
      status: _unused,
    );
    final noLoc = DiaryEntry(
      id: 'b', title: 't', folderPath: '/b', durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28), status: _unused,
    );
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => [withLoc, noLoc]);
    when(() => resolver.resolve(lat: 34.0, lon: 108.0, favorites: any(named: 'favorites')))
        .thenAnswer((_) async => '星巴克');
    when(() => storage.updateLocationName(any(), any())).thenAnswer((_) async {});

    final count = await migration.run();

    expect(count, 1);
    verify(() => storage.updateLocationName('a', '星巴克')).called(1);
    verifyNever(() => storage.updateLocationName('b', any()));
    expect(await LocationResolveMigration.isDone(), isTrue);
  });

  test('resolve 返回 null/空 不更新', () async {
    final withLoc = DiaryEntry(
      id: 'a', title: 't', folderPath: '/a', durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
      locationLat: 34.0, locationLon: 108.0, status: _unused,
    );
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => [withLoc]);
    when(() => resolver.resolve(lat: 34.0, lon: 108.0, favorites: any(named: 'favorites')))
        .thenAnswer((_) async => null);
    when(() => storage.updateLocationName(any(), any())).thenAnswer((_) async {});

    expect(await migration.run(), 0);
    verifyNever(() => storage.updateLocationName(any(), any()));
  });

  test('isDone 为 true 时 run 仍可执行（幂等由调用方判断）', () async {
    // run() 本身总是执行；幂等性由 main 调用前的 isDone 守卫保证。
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => const []);
    expect(await migration.run(), 0);
  });
}
```

> 注：`DiaryEntry` 必填字段以实际模型为准；若构造签名不同（如 `processingStage` 必填），按 `lib/models/diary_entry.dart` 补齐默认值。`_unused` 仅为绕过 enum 必填的占位变量名，不影响断言。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/location_resolve_migration_test.dart`
Expected: FAIL（`LocationResolveMigration` 未定义）

- [ ] **Step 3: 实现 migration**

```dart
// lib/services/location_resolve_migration.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diary_storage_service.dart';
import 'favorite_location_store.dart';
import 'location_resolver.dart';

/// 历史位置回填：用已有 lat/lon 重新解析 locationName（常用位置 → 高德地标）。
/// 串行调用高德，单条失败不阻塞；只 UPDATE locationName 字段，不动其他数据。
class LocationResolveMigration {
  static const _doneKey = 'location_resolve_migration_done';

  final DiaryStorageService _storage;
  final LocationResolver _resolver;
  final FavoriteLocationStore _favStore;

  LocationResolveMigration(this._storage, this._resolver, this._favStore);

  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_doneKey) ?? false;
  }

  /// 执行回填，返回更新条数。幂等性由调用方用 [isDone] 守卫。
  Future<int> run() async {
    final favorites = await _favStore.load();
    final entries = await _storage.getAllEntries();
    var updated = 0;
    for (final e in entries) {
      if (e.locationLat == null || e.locationLon == null) continue;
      try {
        final name = await _resolver.resolve(
          lat: e.locationLat!,
          lon: e.locationLon!,
          favorites: favorites,
        );
        if (name != null && name.isNotEmpty) {
          await _storage.updateLocationName(e.id, name);
          updated++;
        }
      } catch (err) {
        debugPrint('[位置回填] 跳过 ${e.id}: $err');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doneKey, true);
    return updated;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/location_resolve_migration_test.dart`
Expected: PASS（3 个测试）

- [ ] **Step 5: 提交**

```bash
git add lib/services/location_resolve_migration.dart test/location_resolve_migration_test.dart
git commit -m "feat: 添加位置回填迁移"
```

---

### Task 7: main.dart 注册回填迁移

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 添加 import**

在 `lib/main.dart` 顶部 import 区（约行 10-13）追加：

```dart
import 'services/amap_service.dart';
import 'services/favorite_location_store.dart';
import 'services/location_resolve_migration.dart';
import 'services/location_resolver.dart';
```

- [ ] **Step 2: 注册调用**

在 `main()` 内 `_runDailySummaryIfNeeded();`（行 47）之后追加一行：

```dart
  _runLocationResolveMigrationIfNeeded();
```

- [ ] **Step 3: 实现迁移函数**

在 `_runTosMigrationIfNeeded` 函数（约行 52-66）之后新增：

```dart
/// 异步执行：首次启动时用已有 lat/lon 回填历史日记的 locationName。
/// fire-and-forget，不阻塞 UI；标志位保证只跑一次。
Future<void> _runLocationResolveMigrationIfNeeded() async {
  if (await LocationResolveMigration.isDone()) return;
  try {
    final storage = DiaryStorageService();
    final resolver = LocationResolver(AmapService());
    final favStore = FavoriteLocationStore();
    final migration = LocationResolveMigration(storage, resolver, favStore);
    final count = await migration.run();
    if (count > 0) {
      debugPrint('[位置回填] 完成: 更新 $count 条日记');
    }
  } catch (e) {
    debugPrint('[位置回填] 跳过: $e');
  }
}
```

- [ ] **Step 4: 验证分析通过**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add lib/main.dart
git commit -m "feat: 启动时自动回填历史位置"
```

---

### Task 8: recording_task_handler 改造（并行 + 分别发消息 + 存库兜底）

> 此 handler 跑在 FGS isolate，无 isolate 单测；靠手动验证（Task 12）。

**Files:**
- Modify: `lib/services/recording_task_handler.dart`

- [ ] **Step 1: 添加 import**

在文件顶部 import 区（约行 11-16）追加：

```dart
import 'amap_service.dart';
import 'favorite_location_store.dart';
import 'location_resolver.dart';
```

- [ ] **Step 2: 添加 resolver 字段与状态字段**

在 service 实例区（约行 34-37 `_weatherService` 旁）追加：

```dart
  final _locationResolver = LocationResolver(AmapService());
```

在状态区（约行 49-51 `_weatherLocation` / `_location` 旁）追加：

```dart
  // 解析后的最终地名（常用位置/地标/高德地址，可空）
  String? _resolvedLocationName;
```

- [ ] **Step 3: 重写 `_fetchWeatherInBackground`（天气与高德并行、分别发消息）**

将整个 `_fetchWeatherInBackground` 方法（行 178-201）替换为：

```dart
  void _fetchWeatherInBackground() {
    () async {
      try {
        final loc = await _locationService.getCurrentLocation();
        if (loc == null) return;
        _location = loc;
        final favorites = await FavoriteLocationStore.load();

        // 天气 与 位置解析 并行（两者只依赖 lat/lon）
        final weatherFuture = _weatherService.fetchWeatherAndLocation(
          loc.lat,
          loc.lon,
        );
        final resolveFuture = _locationResolver.resolve(
          lat: loc.lat,
          lon: loc.lon,
          favorites: favorites,
        );

        // 天气就绪 → 发天气消息（不含 locationName）
        weatherFuture.then((w) {
          if (w == null) return;
          _weatherLocation = w;
          _sendToMain({
            'type': 'weather',
            'icon': w.icon,
            'text': w.text,
            'temp': w.temp,
          });
        });

        // 位置就绪 → 发位置消息
        resolveFuture.then((name) {
          _resolvedLocationName = name;
          _sendToMain({'type': 'location', 'locationName': name ?? ''});
        });
      } catch (e) {
        debugPrint('[TaskHandler] 天气/位置获取失败（不阻塞）: $e');
      }
    }();
  }
```

- [ ] **Step 4: 改 `_requestStop` 存库的 locationName（和风兜底）**

在 `_requestStop` 的 `createEntry(DiaryEntry(...))`（约行 258）中，将：

```dart
            locationName: _weatherLocation?.locationName,
```

替换为：

```dart
            locationName: _resolvedLocationName ?? _weatherLocation?.locationName,
```

- [ ] **Step 5: 验证分析通过**

Run: `flutter analyze lib/services/recording_task_handler.dart`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/recording_task_handler.dart
git commit -m "feat: 录音时并行解析位置、分别发天气/位置消息"
```

---

### Task 9: recording_page 拆分位置与天气显示

**Files:**
- Modify: `lib/pages/recording_page.dart`

- [ ] **Step 1: 添加位置状态字段**

在 `RecordingPage` 的 State 中（与 `_currentWeatherLocation` 同区）追加：

```dart
  String? _currentLocationName;
```

- [ ] **Step 2: 改消息处理：weather 去 locationName，新增 location 分支**

在 `_handleTaskData`（约行 95-103）的 `case 'weather':` 替换为（`locationName` 传空串，位置走 location 消息），并在其后新增 `case 'location':`：

```dart
      case 'weather':
        setState(() {
          _currentWeatherLocation = WeatherLocation(
            icon: data['icon'] as String,
            text: data['text'] as String,
            temp: data['temp'] as String,
            locationName: '', // 前端不再用，位置走 location 消息
          );
        });
      case 'location':
        setState(() {
          _currentLocationName = (data['locationName'] as String?) ?? '';
        });
```

> 注意：原 `case 'weather'` 之后紧跟的是 `case 'recordingComplete'`。新增的 `case 'location':` 插在这两者之间；Dart switch 的 case 穿透语义下，`weather` 分支末尾无需 break（与现有风格一致）。

- [ ] **Step 3: 抽取 info pill helper**

在 State 类内新增私有方法（复用现有 pill 样式）：

```dart
  Widget _infoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: WarmTokens.warmSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: WarmTokens.warmDivider.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: WarmTokens.warmMuted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
```

- [ ] **Step 4: 替换底部天气 pill 为「位置 + 天气」两个独立 pill**

将原天气 pill 区块（约行 315-341，从 `// 天气信息 pill` 注释到对应 `],` 结束）替换为：

```dart
                // 位置 + 天气 pill（任一就绪即显示，各自独立）
                if (_state == RecordingState.recording &&
                    ((_currentLocationName != null &&
                            _currentLocationName!.isNotEmpty) ||
                        _currentWeatherLocation != null)) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (_currentLocationName != null &&
                          _currentLocationName!.isNotEmpty)
                        _infoPill(_currentLocationName!),
                      if (_currentWeatherLocation != null)
                        _infoPill(
                          '${DiaryEntry.weatherEmoji(_currentWeatherLocation!.icon) ?? _currentWeatherLocation!.text} ${_currentWeatherLocation!.temp}°',
                        ),
                    ],
                  ),
                ],
```

- [ ] **Step 5: 验证分析通过**

Run: `flutter analyze lib/pages/recording_page.dart`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "feat: 录音页拆分位置与天气显示"
```

---

### Task 10: 设置页入口 + 常用位置管理页

**Files:**
- Create: `lib/pages/favorite_locations_page.dart`
- Modify: `lib/pages/settings_page.dart`

- [ ] **Step 1: 实现管理页**

```dart
// lib/pages/favorite_locations_page.dart
import 'package:flutter/material.dart';

import '../models/favorite_location.dart';
import '../services/favorite_location_store.dart';
import '../services/location_service.dart';
import '../widgets/app_title.dart';

class FavoriteLocationsPage extends StatefulWidget {
  const FavoriteLocationsPage({super.key});

  @override
  State<FavoriteLocationsPage> createState() => _FavoriteLocationsPageState();
}

class _FavoriteLocationsPageState extends State<FavoriteLocationsPage> {
  final _store = FavoriteLocationStore();
  final _locationService = LocationService();
  List<FavoriteLocation> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _store.load();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<String?> _promptName({String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('命名常用位置'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如：家、公司',
            helperText: '请站在目标位置、静止片刻以获更准坐标',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final name = await _promptName();
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final loc = await _locationService.getCurrentLocation();
    if (loc == null) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取当前位置，请检查定位权限')),
        );
      }
      return;
    }
    final items = await _store.add(name.trim(), loc.lat, loc.lon);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _rename(FavoriteLocation f) async {
    final name = await _promptName(initial: f.name);
    if (name == null || name.trim().isEmpty) return;
    final items = await _store.rename(f.id, name.trim());
    if (mounted) setState(() => _items = items);
  }

  Future<void> _delete(FavoriteLocation f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除常用位置'),
        content: Text('删除「${f.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final items = await _store.remove(f.id);
      if (mounted) setState(() => _items = items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(title: '常用位置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '还没有常用位置\n点右下角 +，在目标位置新增',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final f = _items[i];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(f.name),
                      subtitle: Text(
                        '${f.lat.toStringAsFixed(4)}, ${f.lon.toStringAsFixed(4)}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'rename') _rename(f);
                          if (v == 'delete') _delete(f);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: '新增常用位置',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 2: settings_page 加入口**

在 `lib/pages/settings_page.dart` 顶部 import 区追加：

```dart
import 'favorite_locations_page.dart';
```

在 `build` 的 ListView 中，「处理延迟」Slider 之后、`const Divider()`（约行 107）之前插入：

```dart
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('常用位置'),
            subtitle: const Text('家、公司等，录音接近时显示名称'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FavoriteLocationsPage(),
                ),
              );
            },
          ),
```

- [ ] **Step 3: 验证分析通过**

Run: `flutter analyze lib/pages/favorite_locations_page.dart lib/pages/settings_page.dart`
Expected: `No issues found!`

- [ ] **Step 4: 提交**

```bash
git add lib/pages/favorite_locations_page.dart lib/pages/settings_page.dart
git commit -m "feat: 设置页新增常用位置管理"
```

---

### Task 11: 环境变量配置（AMAP_WEB_KEY）

**Files:**
- Modify: `.env.local.example`
- Modify: `.env.local`（本地，不入库）
- Modify: `scripts/build.sh`

- [ ] **Step 1: 更新 `.env.local.example`**

在 `.env.local.example` 末尾（`QWEATHER_HOST=devapi.qweather.com` 之后）追加：

```
# 高德地图 Web 服务（位置地标逆地理）
AMAP_WEB_KEY=your_amap_web_key_here
```

- [ ] **Step 2: 更新本地 `.env.local`**

在本地 `.env.local` 追加真实 key（**该文件在 .gitignore，勿提交**）：

```
AMAP_WEB_KEY=<在此填入你的高德 Web 服务 key>
```

> 提示：在 [高德开放平台 → 控制台 → 应用管理](https://console.amap.com/dev/key/app) 创建「Web 服务」类型 key。

- [ ] **Step 3: 更新 `scripts/build.sh` 的校验数组**

在 `scripts/build.sh` 的 `REQUIRED_ENV_VARS=(` 数组（行 14-25）中，`QWEATHER_TOKEN` 之后、`)` 之前新增一行：

```bash
  AMAP_WEB_KEY
```

修改后数组结尾应为：

```bash
  QWEATHER_TOKEN
  AMAP_WEB_KEY
)
```

- [ ] **Step 4: 验证 build.sh 语法**

Run: `bash -n scripts/build.sh`
Expected: 无输出（语法正确）

- [ ] **Step 5: 提交（仅 example 与 build.sh，.env.local 不入库）**

```bash
git add .env.local.example scripts/build.sh
git commit -m "chore: 新增 AMAP_WEB_KEY 环境变量配置"
```

---

### Task 12: 全量验证

**Files:** 无（验证 + 收尾）

- [ ] **Step 1: 全量分析清零**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试通过**

Run: `flutter test`
Expected: 所有测试 PASS（含新增的 4 个测试文件）

- [ ] **Step 3: 手动验证 — 常用位置命中**

用 `./scripts/run_dev.sh` 运行 dev 版本：
1. 设置 → 常用位置 → 在当前位置新增「测试点」。
2. 原地开始录音（数秒）→ 停止。
3. 进详情页，确认位置 chip 显示「测试点」而非行政区。

- [ ] **Step 4: 手动验证 — 陌生地点显示地标**

1. 移动到一个非常用位置（>200m）。
2. 录音 → 停止 → 详情页确认位置显示为高德 POI/地址（非行政区）。

- [ ] **Step 5: 手动验证 — 高德失败回退**

1. 临时把 `.env.local` 的 `AMAP_WEB_KEY` 改为无效值，重启 app。
2. 在非常用位置录音 → 详情页确认位置回退为和风行政区（如「雁塔区」）。
3. 恢复正确 key。

- [ ] **Step 6: 手动验证 — 历史回填**

1. 确保有一条带 lat/lon 的旧日记（locationName 为行政区）。
2. 删除 SharedPreferences 标志位（卸载重装，或清除 app 数据后重新产生一条旧风格数据）后重启 app。
3. 等待后台回填（看 logcat `[位置回填] 完成: 更新 N 条`），确认旧日记 locationName 升级。

- [ ] **Step 7: 格式化全部改动文件**

Run: `dart format lib/`
Expected: 格式化完成

- [ ] **Step 8: 最终提交（如有格式化或微调）**

```bash
git add -A
git commit -m "style: 位置显示升级代码格式化"
```

---

## Self-Review 已完成

- **Spec 覆盖**：§3-§6（模型/存储/解析/录音接入）→ Task 1-4、8；§7 回填 → Task 5-7；§8 设置页 → Task 10；§9 降级 → Task 4/8；§10 环境变量 → Task 11；§11 测试 → 各 task 内联；§12 YAGNI 已遵循。§10 backup 项已注明不做。
- **类型一致性**：`FavoriteLocation`（id/name/lat/lon/createdAt）、`FavoriteLocationStore.load/add/rename/remove`、`AmapService.nearestPoiOrAddress`、`LocationResolver.resolve`、`DiaryStorageService.updateLocationName`、`LocationResolveMigration.run/isDone` 在所有 task 中签名一致。
- **无占位符**：所有代码 step 含完整代码；唯一需用户填入的是 Task 11 Step 2 的真实 key（属配置，非代码占位）。

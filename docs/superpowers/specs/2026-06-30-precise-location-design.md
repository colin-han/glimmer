# 精确定位（实时精确 → 超时降级模糊）— 设计

> 日期：2026-06-30
> 状态：设计中
> 承接：`2026-06-28-location-display-design.md`（引入定位链路）

## 1. 背景

录音定位当前用低精度（仅 coarse 权限 + `LocationAccuracy.low`），且 `getCurrentLocation` 优先用 `getLastKnownPosition`（Android 系统级位置缓存）。三个"不靠谱"根源：

1. **权限**：`AndroidManifest` 仅 `ACCESS_COARSE_LOCATION`（模糊），缺 `ACCESS_FINE_LOCATION`（精确）。
2. **精度**：`getCurrentPosition(accuracy: LocationAccuracy.low)` → 数百米误差。
3. **缓存优先**：`getLastKnownPosition` 可能是其他 app 几小时前留下的陈旧位置，用户移动后严重失准。

## 2. 目标

1. 加 `ACCESS_FINE_LOCATION` 权限 + `LocationAccuracy.high` 实时 GPS。
2. **放弃 lastKnown 缓存优先**；实时精确优先，超时降级到实时模糊（coarse，当下获取，非陈旧缓存）。
3. 不阻塞录音、失败不影响录音（延续 best-effort）。
4. 向后兼容：不改 schema、不改数据格式、不丢数据。

## 3. 现状（定位链路）

```
RecordingTaskHandler（录音 FGS isolate）
  → LocationService.ensurePermission()      ← UI 触发，请求权限（主 isolate）
  → LocationService.getCurrentLocation()    ← 后台 isolate，只读取已授权限
       ① getLastKnownPosition()             ← 优先（瞬间，但可能陈旧）
       ② getCurrentPosition(low, timeLimit 10s)  ← 缓存未命中才调
  → lat/lon 存 SQLite（locationLat / locationLon）
  → LocationResolver.resolve() 用坐标算常用位置匹配 / 调高德
```

`AndroidManifest` 仅 `ACCESS_COARSE_LOCATION`。

## 4. 核心设计

### 4.1 权限（AndroidManifest）

新增 `ACCESS_FINE_LOCATION`，**保留** `ACCESS_COARSE_LOCATION`（模糊兜底依赖它）：

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

- `geolocator.requestPermission()` 自动同时请求两者。
- **Android 12+ (API 31+)**：用户可只授 coarse（拒绝 fine）。此时 high 精度请求由系统降级返回 coarse 级别位置（不报错）——预期行为，用户不给 fine 就只能模糊。
- 权限变更需重新安装 APK 生效（非环境变量，不改 `build.sh`）。

### 4.2 `getCurrentLocation` 两级降级

放弃 lastKnown，改为实时两级定位。把现有方法开头的「service enabled + permission granted」检查提取为私有 `_hasLocationAccess()`（逻辑不变），定位部分改为两级降级：

```dart
Future<({double lat, double lon})?> getCurrentLocation() async {
  // 权限/服务检查（原有逻辑，提取为私有方法）
  if (!await _hasLocationAccess()) return null;

  // ① 实时精确
  try {
    final p = await _getPosition(
      accuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 8),
    );
    return (lat: p.latitude, lon: p.longitude);
  } catch (e) {
    debugPrint('[定位] 高精度失败，降级模糊: $e');
  }
  // ② 超时/失败 → 实时模糊兜底（当下获取，优于陈旧缓存）
  try {
    final p = await _getPosition(
      accuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 5),
    );
    return (lat: p.latitude, lon: p.longitude);
  } catch (e) {
    debugPrint('[定位] 模糊定位也失败: $e');
    return null;
  }
}
```

- `timeLimit` 超时 → geolocator 抛 `TimeoutException` → catch 降级。
- 全程降级返回值，**不抛异常**（符合异常规范）。
- **移除 `getLastKnownPosition` 调用**。
- `_hasLocationAccess()` 封装现有 `isLocationServiceEnabled()` + `checkPermission()`（denied / deniedForever → 返回 false 并 debugPrint），逻辑零改动。

### 4.3 可测性（注入定位获取器）

`Geolocator.getCurrentPosition` 是静态方法，mocktail 无法直接 mock。为可测降级顺序，注入获取器：

```dart
typedef PositionGetter = Future<Position> Function({
  required LocationAccuracy accuracy,
  required Duration timeLimit,
});

class LocationService {
  final PositionGetter _getPosition;
  LocationService({PositionGetter? getPosition})
      : _getPosition = getPosition ?? _defaultGetPosition;

  static Future<Position> _defaultGetPosition({
    required LocationAccuracy accuracy,
    required Duration timeLimit,
  }) =>
      Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeLimit,
        ),
      );
  // ...
}
```

- 生产用默认（调 Geolocator）；测试注入 mock 获取器。
- 现有调用点 `LocationService()` 不变（参数可选）。

### 4.4 `ensurePermission` 不变

仍请求权限；后台 isolate 不请求（无 Activity），只读取已授。

## 5. 数据兼容性

- 不改 SQLite schema、不改数据格式，只改定位获取行为。
- `lat/lon` 仍存 `locationLat`/`locationLon`；无数据丢失。
- 不删/不改用户数据文件。

## 6. 涉及文件清单

修改：
- `android/app/src/main/AndroidManifest.xml`（+`ACCESS_FINE_LOCATION`）
- `lib/services/location_service.dart`（两级降级 + 移除 lastKnown + 注入获取器 + 提取 `_hasLocationAccess`）

新增：
- `test/location_service_test.dart`（降级顺序单测）

不改：`LocationResolver`、`recording_task_handler.dart`、`main.dart`、UI、schema、`build.sh`。

## 7. 测试策略

注入 `PositionGetter` mock 验证降级顺序（无网络/平台依赖）：

1. **high 成功** → 返回 high 位置，**不调 low**。
2. **high 抛异常（超时）** → 降级调 low；low 成功 → 返回 low 位置。
3. **high + low 都抛** → 返回 null。
4. 验证调用顺序：low 仅在 high 失败后才调用。
5. 手动验证（dev 真机）：室外录音定位精确；室内/遮挡超时降级模糊；权限弹窗请求 fine+coarse；用户只授 coarse 时仍能模糊定位。

> 权限检查（`_hasLocationAccess`）依赖 Geolocator 静态方法，单测不覆盖，依赖手动验证（属已有逻辑，本次仅提取未改语义）。

## 8. 验收标准

- `flutter analyze` 无 issue；改动文件 `dart format` 通过。
- 新录音定位为实时精确（high），室内/遮挡超时降级实时模糊（low），不再使用 lastKnown。
- `AndroidManifest` 含 `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`。
- `LocationService()` 调用点无需改动（获取器参数可选）。
- 单测覆盖降级顺序三类；不丢数据。

## 9. 不做（YAGNI）

- 不做位置精度展示/标注（位置名不区分「精确/模糊」标记）。
- 不做定位重试/轮询（两级降级足够）。
- 不做 lastKnown 新鲜度判断（直接放弃 lastKnown）。
- 不改 `LocationResolver` 匹配逻辑、不改 schema、不改 `build.sh`。
- 不为定位新增异常派生类（全程降级返回值）。

# 精确定位（实时精确 → 超时降级模糊）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 录音定位改精确——加 fine 权限 + high 精度实时 GPS，超时降级实时模糊，放弃 lastKnown 缓存。

**Architecture:** 把「两级降级」抽成顶层纯函数 `resolvePositionWithFallback(getter)`（high→low→null），`getCurrentLocation` 只做权限检查 + 调纯函数。降级逻辑与权限检查解耦，纯函数可独立单测（注入获取器，绕过 Geolocator 静态方法）。`AndroidManifest` 补 `ACCESS_FINE_LOCATION`。

**Tech Stack:** Flutter / Dart、geolocator（定位）、mocktail（测试 Position/getter）。

**提交约定（每个 task 通用）：** 提交前对改动文件运行 `dart format <files>`，运行 `flutter analyze` 至 `No issues found!`，再执行 task 末尾的 `git commit`。commit message 用中文。**仅本地 commit，不 push。**

**并行执行：** Task 1（`lib/services/location_service.dart` + `test/location_service_test.dart`）与 Task 2（`android/app/src/main/AndroidManifest.xml`）改动文件完全不重叠，可派两个 subagent **并行执行**。

**与 spec 的差异（可测性优化）：** spec §4.3 用构造函数注入 getter 到 `LocationService`，但 `getCurrentLocation` 开头的权限检查（`Geolocator` 静态方法）mocktail 无法 mock，会阻碍对降级顺序的单测。本计划改为把降级逻辑抽成**顶层纯函数** `resolvePositionWithFallback(PositionGetter)`，`getCurrentLocation` 在权限通过后调它；测试直接调纯函数，完全绕过权限检查。目标行为与 spec 完全一致，仅可测性更优。

---

## File Structure

**修改：**
- `android/app/src/main/AndroidManifest.xml` — 新增 `ACCESS_FINE_LOCATION`
- `lib/services/location_service.dart` — 新增 `PositionGetter` typedef + 顶层纯函数 `resolvePositionWithFallback`；`getCurrentLocation` 改为「权限检查 + 调纯函数」；提取 `_hasLocationAccess()`；新增 `_defaultGetPosition`；**移除 `getLastKnownPosition`**

**新增：**
- `test/location_service_test.dart` — `resolvePositionWithFallback` 降级顺序单测

**不改：** `LocationResolver`、`recording_task_handler.dart`、`main.dart`、UI、schema、`build.sh`、`ensurePermission`（原样保留）。

---

### Task 1: LocationService 两级降级

**Files:**
- Modify: `lib/services/location_service.dart`
- Create: `test/location_service_test.dart`

- [ ] **Step 1: 写失败测试（resolvePositionWithFallback 降级顺序）**

创建 `test/location_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/services/location_service.dart';

class _MockPosition extends Mock implements Position {}

/// 构造一个 stub 了 latitude/longitude 的 mock Position。
Position _pos(double lat, double lon) {
  final p = _MockPosition();
  when(() => p.latitude).thenReturn(lat);
  when(() => p.longitude).thenReturn(lon);
  return p;
}

void main() {
  group('resolvePositionWithFallback', () {
    test('high 成功 → 返回 high 位置，不调 low', () async {
      var lowCalled = false;
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) return _pos(34.0, 108.0);
        lowCalled = true;
        return _pos(0, 0);
      }

      final result = await resolvePositionWithFallback(getter);

      expect(result, (lat: 34.0, lon: 108.0));
      expect(lowCalled, isFalse);
    });

    test('high 超时/失败 → 降级 low 成功', () async {
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) {
          throw Exception('超时');
        }
        return _pos(34.1, 108.1);
      }

      final result = await resolvePositionWithFallback(getter);

      expect(result, (lat: 34.1, lon: 108.1));
    });

    test('high + low 都失败 → null', () async {
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        throw Exception('失败');
      }

      final result = await resolvePositionWithFallback(getter);

      expect(result, isNull);
    });

    test('high 用 8s timeLimit', () async {
      Duration? highLimit;
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) {
          highLimit = timeLimit;
          return _pos(1, 1);
        }
        return _pos(2, 2);
      }

      await resolvePositionWithFallback(getter);

      expect(highLimit, const Duration(seconds: 8));
    });

    test('high 失败时 low 用 5s timeLimit', () async {
      Duration? lowLimit;
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) {
          throw Exception('超时');
        }
        lowLimit = timeLimit;
        return _pos(2, 2);
      }

      await resolvePositionWithFallback(getter);

      expect(lowLimit, const Duration(seconds: 5));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/location_service_test.dart`
Expected: FAIL — `resolvePositionWithFallback` 未定义（`Error: Method not found` / `Undefined name`）。

- [ ] **Step 3: 实现 typedef + 顶层纯函数 resolvePositionWithFallback**

在 `lib/services/location_service.dart` 文件顶部、`class LocationService` 声明**之前**，新增：

```dart
/// 定位获取器：按精度与超时获取当前位置（生产调 Geolocator，测试可注入 mock）。
typedef PositionGetter = Future<Position> Function({
  required LocationAccuracy accuracy,
  required Duration timeLimit,
});

/// 两级降级定位：
/// ① high 精确实时；② 超时/失败降级 low 模糊实时；③ 都失败返回 null。
/// 纯逻辑（接收获取器），不依赖 Geolocator 静态方法，便于单测。
Future<({double lat, double lon})?> resolvePositionWithFallback(
  PositionGetter getPosition,
) async {
  try {
    final p = await getPosition(
      accuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 8),
    );
    return (lat: p.latitude, lon: p.longitude);
  } catch (e) {
    debugPrint('[定位] 高精度失败，降级模糊: $e');
  }
  try {
    final p = await getPosition(
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

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/location_service_test.dart`
Expected: PASS（5 个用例）。

- [ ] **Step 5: 改造 getCurrentLocation + 提取 _hasLocationAccess + _defaultGetPosition + 移除 lastKnown**

把 `lib/services/location_service.dart` 中 `getCurrentLocation` 方法整体替换为下面两个成员，并在 class 内新增 `_defaultGetPosition`（`ensurePermission` **原样保留，不动**）：

```dart
  /// 获取当前位置（不请求权限，isolate 安全）。
  ///
  /// 实时精确优先，超时降级实时模糊；都失败返回 null。调用方需先 [ensurePermission]。
  Future<({double lat, double lon})?> getCurrentLocation() async {
    if (!await _hasLocationAccess()) return null;
    return resolvePositionWithFallback(_defaultGetPosition);
  }

  /// 服务开启 + 权限已授（不请求，isolate 安全）。未满足返回 false 并记日志。
  Future<bool> _hasLocationAccess() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[定位] 位置服务未开启');
        return false;
      }
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('[定位] 权限未授，跳过获取位置');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[定位] 权限检查异常: $e');
      return false;
    }
  }

  /// 默认获取器：调 Geolocator 实时定位。
  static Future<Position> _defaultGetPosition({
    required LocationAccuracy accuracy,
    required Duration timeLimit,
  }) {
    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );
  }
```

> 改造后**删除**原 `getCurrentLocation` 内对 `Geolocator.getLastKnownPosition()` 的调用与相关分支（lastKnown 缓存是「不靠谱」根源之一，彻底移除）。

- [ ] **Step 6: 跑测试 + 分析确认无回归**

Run: `flutter test test/location_service_test.dart`
Expected: PASS（5 用例）。

Run: `flutter analyze`
Expected: `No issues found!`（确认移除 lastKnown 后无未使用 import / 死代码；`geolocator` import 仍被 `_defaultGetPosition` / `ensurePermission` 使用，保留）。

- [ ] **Step 7: 格式化**

Run: `dart format lib/services/location_service.dart test/location_service_test.dart`

- [ ] **Step 8: 提交**

```bash
git add lib/services/location_service.dart test/location_service_test.dart
git commit -m "$(cat <<'EOF'
feat: 录音定位改精确（实时精确→超时降级模糊）

加 high 精度实时 GPS，超时降级实时模糊（low），都失败返回 null；
移除 lastKnown 缓存优先（陈旧根源）。降级逻辑抽成顶层纯函数
resolvePositionWithFallback 注入获取器，便于单测降级顺序。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: AndroidManifest 补精确权限

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: 新增 ACCESS_FINE_LOCATION**

在 `android/app/src/main/AndroidManifest.xml` 中，已有的 coarse 权限行：

```xml
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

上方（或紧邻）新增 fine 权限，最终两行共存：

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

> 保留 coarse（模糊兜底依赖它）。`geolocator.requestPermission()` 会自动同时请求两者。

- [ ] **Step 2: 静态分析（确认 manifest 无语法问题）**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 提交**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "$(cat <<'EOF'
chore: 新增 ACCESS_FINE_LOCATION 精确定位权限

配合 LocationService high 精度定位；保留 COARSE 作为模糊兜底。
Android 12+ 用户可只授 coarse，届时 high 自动降级模糊（系统行为）。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## 全局收尾（两 task 都合并后）

- [ ] **跑全量测试：** `flutter test` → 全绿。
- [ ] **全量静态分析：** `flutter analyze` → `No issues found!`。
- [ ] **手动验证（dev 构建，需重新安装 APK 使权限生效）：** `./scripts/run_dev.sh`，室外录音 → 定位精确；室内/遮挡 → 超时降级模糊（仍有当下位置）；权限弹窗请求「精确+大致」位置。

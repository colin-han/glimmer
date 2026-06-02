# 天气与位置记录 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建日记时自动获取天气和位置信息，存入数据库，在日记卡片和详情页显示。

**Architecture:** 新增 `LocationService`（geolocator 粗略定位）和 `WeatherService`（和风天气 GeoAPI + 天气实况），录音开始时异步获取，不阻塞录音流程。drift schema 升级新增 6 个可空字段。UI 层在副标题行追加天气 emoji + 温度 + 位置名。

**Tech Stack:** geolocator（定位）、和风天气 Web API via dio（天气+逆地理编码）、drift（SQLite schema v4）

---

## File Structure

| 操作 | 文件 | 职责 |
|------|------|------|
| Create | `lib/services/location_service.dart` | GPS 粗略定位 |
| Create | `lib/services/weather_service.dart` | 和风天气 API + WeatherLocation 模型 |
| Modify | `lib/services/database/tables.dart` | 新增 6 列 |
| Modify | `lib/services/database/app_database.dart` | schemaVersion 3→4 + migration |
| Regenerate | `lib/services/database/app_database.g.dart` | build_runner 重新生成 |
| Modify | `lib/models/diary_entry.dart` | 新增 6 个字段 |
| Modify | `lib/services/diary_storage_service.dart` | createEntry / getAllEntries / getEntryById 映射新字段 |
| Modify | `lib/pages/recording_page.dart` | 录音开始时异步获取天气+位置，保存时注入 |
| Modify | `lib/pages/diary_list_page.dart` | 副标题行显示天气+位置 |
| Modify | `lib/pages/diary_detail_page.dart` | 详情页元数据区显示天气+位置 |
| Modify | `android/app/src/main/AndroidManifest.xml` | 新增 ACCESS_COARSE_LOCATION |
| Modify | `pubspec.yaml` | 新增 geolocator 依赖 |
| Modify | `.env.local.example` | 新增 QWEATHER_TOKEN / QWEATHER_HOST |

---

### Task 1: 添加依赖 + Android 权限

**Files:**
- Modify: `pubspec.yaml:50` (dependencies 块末尾)
- Modify: `android/app/src/main/AndroidManifest.xml:4`
- Modify: `.env.local.example`

- [ ] **Step 1: 添加 geolocator 依赖**

在 `pubspec.yaml` 的 dependencies 末尾 `archive: ^4.0.7` 后添加：

```yaml
  geolocator: ^13.0.0
```

- [ ] **Step 2: 运行 flutter pub get**

Run: `flutter pub get`
Expected: 成功安装 geolocator 及其依赖

- [ ] **Step 3: 添加 Android 粗略定位权限**

在 `android/app/src/main/AndroidManifest.xml` 的 `<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />` 后添加：

```xml
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

- [ ] **Step 4: 更新 .env.local.example**

在文件末尾添加：

```env
# 和风天气（天气 + 逆地理编码）
QWEATHER_TOKEN=your_qweather_token_here
QWEATHER_HOST=devapi.qweather.com
```

- [ ] **Step 5: 提交**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml .env.local.example
git commit -m "feat: 添加 geolocator 依赖和粗略定位权限"
```

---

### Task 2: 数据库 schema 升级（drift）

**Files:**
- Modify: `lib/services/database/tables.dart`
- Modify: `lib/services/database/app_database.dart`
- Regenerate: `lib/services/database/app_database.g.dart`

- [ ] **Step 1: 在 tables.dart 新增 6 列**

在 `lib/services/database/tables.dart` 的 `DiaryEntries` 表中，`uploadedAt` 后添加：

```dart
  TextColumn get weatherIcon => text().nullable()();
  TextColumn get weatherText => text().nullable()();
  TextColumn get temperature => text().nullable()();
  TextColumn get locationName => text().nullable()();
  RealColumn get locationLat => real().nullable()();
  RealColumn get locationLon => real().nullable()();
```

- [ ] **Step 2: 升级 schemaVersion 并添加 migration**

在 `lib/services/database/app_database.dart` 中：

将 `schemaVersion` 从 3 改为 4：

```dart
  @override
  int get schemaVersion => 4;
```

在 `onUpgrade` 方法的末尾（`if (from < 3)` 块之后）添加：

```dart
          if (from < 4) {
            await m.addColumn(diaryEntries, diaryEntries.weatherIcon);
            await m.addColumn(diaryEntries, diaryEntries.weatherText);
            await m.addColumn(diaryEntries, diaryEntries.temperature);
            await m.addColumn(diaryEntries, diaryEntries.locationName);
            await m.addColumn(diaryEntries, diaryEntries.locationLat);
            await m.addColumn(diaryEntries, diaryEntries.locationLon);
          }
```

- [ ] **Step 3: 运行 build_runner 重新生成代码**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 成功生成 `app_database.g.dart`

- [ ] **Step 4: 提交**

```bash
git add lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/database/app_database.g.dart
git commit -m "feat: 数据库 schema v4，新增天气和位置字段"
```

---

### Task 3: DiaryEntry 模型 + DiaryStorageService 映射

**Files:**
- Modify: `lib/models/diary_entry.dart`
- Modify: `lib/services/diary_storage_service.dart`

- [ ] **Step 1: 在 DiaryEntry 模型新增 6 个字段**

在 `lib/models/diary_entry.dart` 中，在 `uploadedAt` 字段后添加：

```dart
  final String? weatherIcon;
  final String? weatherText;
  final String? temperature;
  final String? locationName;
  final double? locationLat;
  final double? locationLon;
```

在构造函数中，`this.uploadedAt,` 后添加：

```dart
    this.weatherIcon,
    this.weatherText,
    this.temperature,
    this.locationName,
    this.locationLat,
    this.locationLon,
```

添加一个辅助方法，用于副标题显示天气摘要：

```dart
  /// 天气摘要文本，如 "海淀区  ☁️ 24°"，无天气时返回空字符串
  String get weatherDisplay {
    final parts = <String>[];
    if (locationName != null) parts.add(locationName!);
    if (weatherIcon != null) {
      final emoji = _weatherEmoji[weatherIcon!] ?? weatherText ?? '';
      if (emoji.isNotEmpty) parts.add(emoji);
    }
    if (temperature != null) parts.add('$temperature°');
    return parts.join('  ');
  }

  static const _weatherEmoji = {
    '100': '☀️',
    '101': '🌤️',
    '102': '⛅',
    '103': '⛅',
    '104': '☁️',
    '150': '☀️',
    '151': '🌤️',
    '300': '🌧️',
    '301': '⛈️',
    '302': '⛈️',
    '303': '⛈️',
    '304': '⛈️',
    '305': '🌧️',
    '306': '🌧️',
    '307': '🌧️',
    '308': '🌧️',
    '309': '🌧️',
    '310': '🌧️',
    '311': '🌧️',
    '312': '🌧️',
    '313': '🌧️',
    '314': '🌧️',
    '315': '🌧️',
    '399': '🌧️',
    '400': '🌨️',
    '401': '🌨️',
    '402': '🌨️',
    '403': '🌨️',
    '404': '🌨️',
    '405': '🌨️',
    '406': '🌨️',
    '407': '🌨️',
    '408': '🌨️',
    '409': '🌨️',
    '499': '🌨️',
    '500': '🌫️',
    '501': '🌫️',
    '502': '🌫️',
    '503': '🌫️',
    '504': '🌫️',
    '507': '🌫️',
    '508': '🌫️',
    '509': '🌫️',
    '510': '🌫️',
    '511': '🌫️',
    '512': '🌫️',
    '513': '🌫️',
    '514': '🌫️',
    '515': '🌫️',
    '900': '🌡️',
    '901': '🌡️',
    '999': '🌡️',
  };
```

- [ ] **Step 2: 更新 DiaryStorageService 中的映射**

在 `lib/services/diary_storage_service.dart` 的 `createEntry` 方法中，`uploadedAt:` 行后添加：

```dart
      weatherIcon: Value(entry.weatherIcon),
      weatherText: Value(entry.weatherText),
      temperature: Value(entry.temperature),
      locationName: Value(entry.locationName),
      locationLat: Value(entry.locationLat),
      locationLon: Value(entry.locationLon),
```

在 `getAllEntries` 方法的 `DiaryEntry(...)` 构造中，`uploadedAt:` 行后添加：

```dart
              weatherIcon: r.weatherIcon,
              weatherText: r.weatherText,
              temperature: r.temperature,
              locationName: r.locationName,
              locationLat: r.locationLat,
              locationLon: r.locationLon,
```

同样更新 `getEntryById` 方法的 `DiaryEntry(...)` 构造，`uploadedAt:` 行后添加相同的 6 行。

- [ ] **Step 3: 运行 flutter analyze 确认无错误**

Run: `flutter analyze`
Expected: 无 error（可能有 info 级别的 lint）

- [ ] **Step 4: 提交**

```bash
git add lib/models/diary_entry.dart lib/services/diary_storage_service.dart
git commit -m "feat: DiaryEntry 模型新增天气和位置字段"
```

---

### Task 4: LocationService

**Files:**
- Create: `lib/services/location_service.dart`

- [ ] **Step 1: 创建 LocationService**

```dart
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// 获取当前位置（粗略定位），失败返回 null
  Future<({double lat, double lon})?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) return null;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return (lat: position.latitude, lon: position.longitude);
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/location_service.dart
git commit -m "feat: 添加 LocationService（粗略定位）"
```

---

### Task 5: WeatherService

**Files:**
- Create: `lib/services/weather_service.dart`

- [ ] **Step 1: 创建 WeatherService**

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WeatherLocation {
  final String icon;
  final String text;
  final String temp;
  final String locationName;

  const WeatherLocation({
    required this.icon,
    required this.text,
    required this.temp,
    required this.locationName,
  });
}

class WeatherService {
  final _dio = Dio();
  String? _token;
  String? _host;

  void _ensureInitialized() {
    if (_token != null) return;
    _token = dotenv.get('QWEATHER_TOKEN');
    _host = dotenv.get('QWEATHER_HOST', fallback: 'devapi.qweather.com');
  }

  /// 根据经纬度获取天气和城市信息，失败返回 null
  Future<WeatherLocation?> fetchWeatherAndLocation(
      double lat, double lon) async {
    _ensureInitialized();
    final token = _token!;
    final host = _host!;

    try {
      // 1. 逆地理编码获取城市名
      final geoResponse = await _dio.get(
        'https://$host/geo/v2/city/lookup',
        queryParameters: {
          'location': '${lon.toStringAsFixed(2)},${lat.toStringAsFixed(2)}',
          'number': 1,
          'lang': 'zh',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final geoCode = geoResponse.data['code']?.toString();
      if (geoCode != '200') return null;

      final locations = geoResponse.data['location'] as List;
      if (locations.isEmpty) return null;

      final locationName = locations[0]['name'] as String;

      // 2. 获取天气实况
      final weatherResponse = await _dio.get(
        'https://$host/v7/weather/now',
        queryParameters: {
          'location': '${lon.toStringAsFixed(2)},${lat.toStringAsFixed(2)}',
          'lang': 'zh',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final weatherCode = weatherResponse.data['code']?.toString();
      if (weatherCode != '200') return null;

      final now = weatherResponse.data['now'];
      return WeatherLocation(
        icon: now['icon'] as String,
        text: now['text'] as String,
        temp: now['temp'] as String,
        locationName: locationName,
      );
    } catch (e) {
      debugPrint('[天气] 获取失败: $e');
      return null;
    }
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/services/weather_service.dart
git commit -m "feat: 添加 WeatherService（和风天气 API）"
```

---

### Task 6: 录音流程集成

**Files:**
- Modify: `lib/pages/recording_page.dart`

- [ ] **Step 1: 添加 import 和服务实例**

在 `recording_page.dart` 文件顶部的 import 区添加：

```dart
import '../services/location_service.dart';
import '../services/weather_service.dart';
```

在 `_RecordingPageState` 类中，`final _uuid = const Uuid();` 后添加：

```dart
  final _locationService = LocationService();
  final _weatherService = WeatherService();

  /// 录音期间异步获取的天气+位置信息，保存时注入 DiaryEntry
  WeatherLocation? _currentWeatherLocation;
  ({double lat, double lon})? _currentLocation;
```

- [ ] **Step 2: 在 _startRecording 中异步获取天气**

在 `_startRecording` 方法中，`setState(() => _state = RecordingState.recording);` 之前添加：

```dart
      // 异步获取位置和天气（不阻塞录音）
      _fetchWeatherInBackground();
```

在 `_RecordingPageState` 类中添加新方法（放在 `_connectRealtimeAsr` 之后）：

```dart
  void _fetchWeatherInBackground() {
    () async {
      try {
        final loc = await _locationService.getCurrentLocation();
        if (loc == null) return;
        _currentLocation = loc;
        _currentWeatherLocation =
            await _weatherService.fetchWeatherAndLocation(loc.lat, loc.lon);
      } catch (e) {
        debugPrint('[天气] 获取失败（不阻塞）: $e');
      }
    }();
  }
```

- [ ] **Step 3: 在 _stopAndProcess 中注入天气数据**

在 `_stopAndProcess` 方法的步骤 3 中，`DiaryEntry(...)` 构造中 `uploadedAt: DateTime.now(),` 后添加：

```dart
        weatherIcon: _currentWeatherLocation?.icon,
        weatherText: _currentWeatherLocation?.text,
        temperature: _currentWeatherLocation?.temp,
        locationName: _currentWeatherLocation?.locationName,
        locationLat: _currentLocation?.lat,
        locationLon: _currentLocation?.lon,
```

- [ ] **Step 4: 在 _saveEntryAndNavigate 中也注入天气数据**

在 `_saveEntryAndNavigate` 方法的 `DiaryEntry(...)` 构造中，`audioFormat: audioFormat,` 后添加：

```dart
      weatherIcon: _currentWeatherLocation?.icon,
      weatherText: _currentWeatherLocation?.text,
      temperature: _currentWeatherLocation?.temp,
      locationName: _currentWeatherLocation?.locationName,
      locationLat: _currentLocation?.lat,
      locationLon: _currentLocation?.lon,
```

同时在 `_stopAndProcess` 方法的最后（`setState(() => _state = RecordingState.idle...)` 块内）重置天气数据：

在 `_realtimeText = '';` 后添加：

```dart
            _currentWeatherLocation = null;
            _currentLocation = null;
```

- [ ] **Step 5: 提交**

```bash
git add lib/pages/recording_page.dart
git commit -m "feat: 录音时异步获取天气和位置，保存时注入日记条目"
```

---

### Task 7: 日记卡片 UI 显示天气

**Files:**
- Modify: `lib/pages/diary_list_page.dart`

- [ ] **Step 1: 更新副标题行**

在 `diary_list_page.dart` 的 `_buildEntryCard` 方法中，替换 subtitle 的 Text 内容。

将：

```dart
        child: Text(
            '${entry.formattedDate}  ${entry.durationDisplay}'),
```

替换为：

```dart
        child: Text(
            '${entry.formattedDate}  ${entry.durationDisplay}${entry.weatherDisplay.isNotEmpty ? '  ${entry.weatherDisplay}' : ''}'),
```

- [ ] **Step 2: 提交**

```bash
git add lib/pages/diary_list_page.dart
git commit -m "feat: 日记卡片副标题显示天气和位置"
```

---

### Task 8: 日记详情页显示天气

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: 更新元数据行**

在 `diary_detail_page.dart` 的 `build` 方法中，找到元数据 Text：

```dart
                      Text(
                        '${widget.entry.formattedDate}  ${widget.entry.durationDisplay}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
```

替换为：

```dart
                      Text(
                        '${widget.entry.formattedDate}  ${widget.entry.durationDisplay}${widget.entry.weatherDisplay.isNotEmpty ? '  ${widget.entry.weatherDisplay}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
```

- [ ] **Step 2: 提交**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "feat: 日记详情页显示天气和位置信息"
```

---

### Task 9: 端到端测试

**Files:** 无新增

- [ ] **Step 1: 在 .env.local 中配置和风天气 Token**

确保 `.env.local` 中有：

```env
QWEATHER_TOKEN=你的实际token
QWEATHER_HOST=devapi.qweather.com
```

- [ ] **Step 2: 在设备上运行 dev 版本**

Run: `./run_dev.sh`
Expected: 应用正常启动，无编译错误

- [ ] **Step 3: 测试录音流程**

1. 点击录音按钮开始录音
2. 说几句话后停止
3. 等待处理完成
4. 检查日志中是否有 `[天气]` 相关输出
5. 跳转到详情页后，检查元数据区是否显示天气信息（如 "海淀  ☁️ 24°"）

- [ ] **Step 4: 测试日记卡片**

返回日记列表，检查新日记卡片的副标题是否显示天气信息。

- [ ] **Step 5: 测试旧日记兼容性**

检查旧日记（无天气数据）的卡片和详情页是否正常显示，不显示天气部分。

- [ ] **Step 6: 更新版本号并提交**

确认一切正常后更新版本号：

在 `pubspec.yaml` 中将 `version: 1.1.1+5` 改为 `version: 1.2.0+6`

```bash
git add pubspec.yaml
git commit -m "chore: v1.2.0"
```

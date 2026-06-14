# 天气与位置记录 设计文档

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建日记时自动获取当前位置的天气信息和地理位置，记录在日记条目中，并在日记卡片上显示。

**Architecture:** 使用 geolocator 获取粗略定位（经纬度），然后调用和风天气 GeoAPI 反查城市信息（获取区级行政区名），再调用和风天气实况 API 获取当前天气。天气和位置数据存入 SQLite 新增字段。天气图标使用和风天气 icon 代码映射到 Unicode emoji。

**Tech Stack:** geolocator（定位）、和风天气 Web API（GeoAPI + 天气实况）、drift（SQLite schema 升级）

---

## 数据模型

### DiaryEntry 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `weatherIcon` | `text().nullable()()` | null | 和风天气图标代码（如 "101"） |
| `weatherText` | `text().nullable()()` | null | 天气描述（如 "多云"） |
| `temperature` | `text().nullable()()` | null | 温度字符串（如 "24"） |
| `locationName` | `text().nullable()()` | null | 区级行政区名（如 "海淀区"） |
| `locationLat` | `real().nullable()()` | null | 纬度 |
| `locationLon` | `real().nullable()()` | null | 经度 |

drift schemaVersion 从 3 升至 4，`onUpgrade` 中 `from < 4` 时 `addColumn` 这 6 个字段。

### DiaryEntry Dart 模型

```dart
class DiaryEntry {
  // ... 现有字段 ...
  final String? weatherIcon;
  final String? weatherText;
  final String? temperature;
  final String? locationName;
  final double? locationLat;
  final double? locationLon;
}
```

---

## 服务层

### LocationService

职责：获取当前设备位置（粗略定位）。

```dart
class LocationService {
  /// 获取当前位置（粗略定位），返回 (纬度, 经度) 或 null
  Future<({double lat, double lon})?> getCurrentLocation();
}
```

- 使用 `geolocator` 包的 `getLastKnownPosition` 或 `getCurrentPosition`，请求 `LocationPermission.whenInUse`
- 仅请求 `ACCESS_COARSE_LOCATION`（Android 不弹窗确认，用户无感知）
- 定位失败返回 null，不阻塞日记创建

### WeatherService

职责：根据经纬度获取天气信息和城市名。

```dart
class WeatherService {
  /// 获取天气和位置信息
  /// 返回 WeatherLocation 或 null（失败时）
  Future<WeatherLocation?> fetchWeatherAndLocation(double lat, double lon);
}

class WeatherLocation {
  final String icon;       // 和风天气图标代码
  final String text;       // 天气描述
  final String temp;       // 温度
  final String locationName; // 区级行政区名
}
```

内部流程：
1. 调用 GeoAPI `/geo/v2/city/lookup?location={lon},{lat}&number=1` 获取城市信息，取 `name`（区/县级名称，如"海淀"）作为 `locationName`
2. 调用天气实况 `/v7/weather/now?location={lon},{lat}` 获取 `now.icon`、`now.text`、`now.temp`
3. 任意一步失败返回 null

**API 认证：** 和风天气使用 JWT Bearer Token，key 存放在 `.env.local` 的 `QWEATHER_TOKEN` 中。

**API Host：** 免费版使用 `devapi.qweather.com`，付费版使用 `api.qweather.com`。通过 `.env.local` 的 `QWEATHER_HOST` 配置（默认 `devapi.qweather.com`）。

### 环境变量新增

```env
# 和风天气
QWEATHER_TOKEN=your_token_here
QWEATHER_HOST=devapi.qweather.com
```

---

## 录音流程集成

在 `RecordingPage` 的保存流程中，录音开始时异步获取位置和天气，不阻塞录音。

```
录音开始
  └→ 异步: LocationService.getCurrentLocation()
       └→ 成功: WeatherService.fetchWeatherAndLocation(lat, lon)
            └→ 存入 _currentWeatherLocation
       └→ 失败: _currentWeatherLocation = null（静默降级）

录音停止 → ASR → LLM → 保存
  └→ DiaryEntry(..., weatherIcon, weatherText, temperature, locationName, locationLat, locationLon)
```

天气/位置获取失败不影响日记创建，所有字段为 null 即可。

---

## UI 显示

### 日记卡片（diary_list_page.dart）

副标题行格式变更：

```
旧: 2026-06-02 14:30  ·  05:23
新: 2026-06-02 14:30  ·  05:23  ·  海淀区  ☁️ 24°
```

天气图标使用和风天气 icon 代码映射到 emoji（内置 Map，不依赖外部资源）：

```dart
static const _weatherIconMap = {
  '100': '☀️',  // 晴
  '101': '🌤️', // 多云
  '102': '⛅',  // 少云
  '103': '☁️',  // 晴间多云
  '104': '☁️',  // 阴
  '300': '阵雨', '301': '⛈️', // ...
};
```

位置名或天气任一为 null 则不显示对应部分，保持向后兼容。

### 日记详情页（diary_detail_page.dart）

在详情页顶部元数据区域追加天气和位置信息，格式同卡片。

---

## Android 权限

`android/app/src/main/AndroidManifest.xml` 新增：

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

不需要 `ACCESS_FINE_LOCATION`。Android 12+ 粗略定位不需要用户弹窗确认。

---

## 错误处理

- **定位失败**（无 GPS、无网络、权限拒绝）：静默降级，日记条目天气/位置字段全部为 null
- **天气 API 失败**（网络错误、API 配额用尽）：同上，静默降级
- **历史数据**：旧日记无天气/位置字段，卡片不显示，无迁移需求

---

## 依赖新增

```yaml
dependencies:
  geolocator: ^13.0.0   # 定位服务
```

和风天气 API 通过已有的 `dio` HTTP 客户端调用，不需要额外 SDK。

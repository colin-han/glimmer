# 位置显示升级（常用位置 + 地标）— 设计

> 日期：2026-06-28
> 状态：设计中

## 1. 背景与目标

当前日记的位置来自和风天气 `city/lookup` 逆地理，返回的是**城市/区县级**行政区名（如「雁塔区」），粒度太粗、千篇一律。

**目标**：让位置显示更有意义——

1. 用户可设置**常用位置**（家、公司等，带名称 + 坐标）。
2. 录音位置在某个常用位置 **200m 内** → 显示常用位置名（「家」「公司」）。
3. 否则用**高德逆地理**解析最近地标（POI，如「星巴克国贸店」）。
4. 高德失败 → 回退到和风行政区（现有行为），不更差。

## 2. 现状（位置是怎么来的）

| 环节 | 现状 |
|---|---|
| 取经纬度 | 录音时后台 isolate 用 `Geolocator` 低精度定位，**已存 `locationLat` / `locationLon`** |
| 取地名 | 和风 `/geo/v2/city/lookup` → 城市/区县级名（行政区）|
| 存储 | `locationName` + `lat` + `lon` 三字段进 SQLite（`diary_entries`）|
| 显示 | 详情页 `DetailInfoBar` 的 chip；录音实时页底部天气条；日报统计最常出现地名 |

执行点：`RecordingTaskHandler._fetchWeatherInBackground()`（FGS isolate 内，fire-and-forget）。先 `getCurrentLocation()` 拿 lat/lon 存字段 `_location`，再 `fetchWeatherAndLocation()` 拿行政区 + 天气存 `_weatherLocation`。`_requestStop()` 把 `_weatherLocation?.locationName`、`_location?.lat/lon` 存库。

**关键事实**：lat/lon 的获取与天气获取是**先后两步、彼此独立**——`_location = loc`（行 183）在天气调用（行 184）之前。存库时 `locationLat/Lon` 只读 `_location`、不读天气字段。因此**天气失败不影响 lat/lon 入库**；lat/lon 只在「定位本身失败」或「短录音竞态（定位未返回就 stop）」时缺失。

## 3. 技术约束与关键决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| 地标数据源 | **高德 Web 服务** `/v3/geocode/regeo` | 国内 POI 最全；一次返回 POI + 地址兜底 |
| 常用位置录入 | **仅当前位置** | 复用现有 `LocationService`，最简；YAGNI 地址搜索/地图选点 |
| 历史回填 | **自动回填全部旧日记** | 用户选择；用已有 lat/lon 重新解析 |
| 匹配阈值 | **固定 200m** | 兼顾低精度定位（low accuracy + 缓存位置）误差 |
| 解析时机 | **录音 isolate 内、天气之后** | `locationName` 在存库前即最终值（纯快照语义）|
| 短录音竞态 | **不修** | 维持现状 best-effort；用户接受 |
| 天气 / 高德 | **并行调用** | 两者都只依赖 lat/lon，无依赖关系 |
| 前端消息 | **天气、位置分别发** | 谁先到谁先显示 |

**跨 isolate 数据**：`RecordingTaskHandler` 跑在 FGS isolate。常用位置通过 `SharedPreferences.getInstance()` 在 isolate 内直读（与 `onStart` 手动 `dotenv.load` 同理，偏好数据平台共享）。

## 4. 整体方案

纯快照语义：`locationName` 在录音时即解析为最终值并存库，显示层零语义改动（只是内容更精确）。核心是单一解析入口 `LocationResolver.resolve()`，录音时与回填共用。

```
resolve(lat, lon, favorites):            ← 唯一解析入口，返回 String?（nullable）
  ① 常用位置列表最近者 ≤ 200m   → "家"
  ② 高德 regeo pois[0].name     → "星巴克国贸店"
  ③ 高德 regeo formatted_address → "雁塔区xx路"（高德自带地址兜底）
  ④ 都没有                      → null
```

> 注：`resolve` **不依赖和风行政区**（并行时拿不到）。和风行政区降级为「存库时的最后兜底」——见 §6。

## 5. 数据结构

### `lib/models/favorite_location.dart`

```dart
class FavoriteLocation {
  final String id;          // uuid
  final String name;        // "家" / "公司" / 自定义
  final double lat;
  final double lon;
  final DateTime createdAt;

  // toJson / fromJson（SharedPreferences 序列化）
}
```

### `lib/services/favorite_location_store.dart`

- 存储：SharedPreferences 键 `pref_favorite_locations`，值为 JSON 数组。
- 理由：数量少（家、公司、几个常去地）、纯配置、避免 drift migration。
- 接口：`Future<List<FavoriteLocation>> load()` / `add(name, lat, lon)` / `rename(id, name)` / `remove(id)`。
- **isolate 安全**：`load()` 内部 `SharedPreferences.getInstance()`，主 isolate 与 FGS isolate 各自独立实例、读同一份数据。

## 6. 录音流程接入（`recording_task_handler.dart`）

### `_fetchWeatherInBackground` 改造

`getCurrentLocation()` 仍是先决条件（串行在最前）；拿到 lat/lon 后，**天气与高德并行**，各自完成、各自发消息：

```dart
final loc = await _locationService.getCurrentLocation();   // 先决
if (loc == null) return;
_location = loc;
final favorites = await FavoriteLocationStore.load();

// 并行：天气 与 位置解析（含高德）
final weatherFuture = _weatherService.fetchWeatherAndLocation(loc.lat, loc.lon);
final resolveFuture = _locationResolver.resolve(
  lat: loc.lat, lon: loc.lon, favorites: favorites,
);

weatherFuture.then((w) {                                   // 天气就绪 → 发天气消息
  if (w == null) return;
  _weatherLocation = w;
  _sendToMain({'type': 'weather', 'icon': w.icon, 'text': w.text, 'temp': w.temp});
});

resolveFuture.then((name) {                                // 位置就绪 → 发位置消息
  _resolvedLocationName = name;                            // String?
  _sendToMain({'type': 'location', 'locationName': name ?? ''});
});
```

新增 handler 字段：`String? _resolvedLocationName`、`LocationResolver _locationResolver`、`AmapService _amapService`。

### `_requestStop` 存库改动

```dart
locationName: _resolvedLocationName ?? _weatherLocation?.locationName,
locationLat:  _location?.lat,
locationLon:  _location?.lon,
```

`resolve` 成功（家/地标/高德地址）→ 用它；为 null（高德失败）→ 退回和风行政区；都无 → null。

### 新增 `lib/services/amap_service.dart`

仿 `WeatherService`：dio + `AMAP_WEB_KEY`（`dotenv.get`）。`Future<String?> nearestPoiOrAddress(lat, lon)` 调 `/v3/geocode/regeo`（`radius=1000, extensions=base, output=json`），返回 `pois[0].name` 或 `formatted_address` 或 null。失败返回 null，不抛。

### 新增 `lib/services/location_resolver.dart`

`Future<String?> resolve({lat, lon, favorites})`：按 §4 顺序，距离用 `Geolocator.distanceBetween`（复用现有依赖）。全程降级用返回值，不抛异常。

### 前端 `recording_page.dart` 改动

- `weather` 消息**不再携带 locationName**，只含 icon/text/temp。
- 新增 `location` 消息处理：`setState` 持有 `String? _currentLocationName`。
- 底部原「行政区 ☁️ 24°」合并文本，拆为位置、天气各自独立显示（分别持有 `_currentLocationName` / `_currentWeather`，谁先到先显示）。
- 详情页 `DetailInfoBar` **无需改**（已是位置/天气分开 chip，`locationName` 内容变精确即可）。
- 日报统计 `daily_summary` **自动受益**（统计「家」出现次数更精准，无需改动）。

## 7. 回填迁移（自动全部旧日记）

仿 `main.dart` 的 `_runTosMigrationIfNeeded`：fire-and-forget、不阻塞 UI、一次性。

- `main()` 新增 `_runLocationResolveMigrationIfNeeded()`。
- 标志位 SharedPreferences `location_resolve_migration_done`，完成后置 true，**只跑一次**。
- 遍历所有「有 lat/lon」的旧日记，在**主 isolate** 调同一个 `LocationResolver.resolve()`，UPDATE `locationName`。
- **串行**调高德（稳，不打爆配额）；单条失败保留原行政区名、不阻塞整体。
- **数据安全**：只 UPDATE `locationName` 一个字段，不动 lat/lon/audio/其他；不删任何数据；符合兼容性基线（v1.0.0 起向后兼容、不丢用户数据）。

## 8. 设置页 UI（`settings_page.dart`）

新增「常用位置」入口 → 管理页：

- 列出已有位置（名称 + 坐标），支持**新增 / 重命名 / 删除**。
- 新增流程（仅当前位置）：点「+」→ `getCurrentLocation()` 取坐标 → 弹框输入名称（家/公司/自定义）→ 保存。提示「请在目标位置静止片刻以获更准坐标」。

## 9. 错误处理与降级

全程遵循项目异常规范：**正常降级用返回值（null），不抛异常**；真正的配置/网络错误静默降级 + 记 `ApiLogService`，绝不崩。录音 isolate 内任何失败都不阻塞录音（延续现有 best-effort）。

| 情况 | 结果 |
|---|---|
| 命中常用位置（≤200m） | 显示「家」等 |
| 高德成功 | 显示最近 POI / 高德地址 |
| 高德失败、和风成功（存库时） | 回退和风行政区 |
| 高德 + 和风都失败 / 短录音竞态 | `locationName` 为 null，不显示位置 chip |

## 10. 环境变量与备份

- 新增 `AMAP_WEB_KEY`（高德 Web 服务 key）→ 同步进 `.env.local` / `.env.local.example` / `scripts/build.sh` 的 `REQUIRED_ENV_VARS`（遵循维护规范）。
- 常用位置（`pref_favorite_locations`）纳入 app-backup 导出/导入，换机不丢。

## 11. 测试策略

- **LocationResolver** 单测：常用位置 200m 命中/越界边界、高德成功（mock）/失败降级、各级兜底返回值。
- **FavoriteLocationStore** 单测：增删改名 + JSON 序列化往返、空列表。
- **AmapService** 单测：mock dio，验证 POI/address 解析与失败返回 null。
- **回填迁移**：幂等性（标志位二次启动不重跑）、单条失败不阻塞、只改 locationName。
- **手动验证**：在家/公司录音显示常用名、陌生地点显示 POI、高德不可用时回退行政区、设置页增删改、旧日记回填效果。

## 12. 不做（YAGNI）

- 不做地址搜索 / 地图选点录入（仅当前位置）。
- 不做每个常用位置可配半径（统一 200m）。
- 不修短录音竞态（接受 best-effort）。
- 不监听录音中常用位置变化。
- 不为位置解析新增异常派生类（全用返回值降级）。
- 不改 `DetailInfoBar` / `daily_summary`（自动受益）。

## 13. 改动文件清单

**新增**：
- `lib/models/favorite_location.dart`
- `lib/services/favorite_location_store.dart`
- `lib/services/amap_service.dart`
- `lib/services/location_resolver.dart`
- `lib/services/location_resolve_migration.dart`
- `lib/pages/favorite_locations_page.dart`（管理页）

**修改**：
- `lib/services/recording_task_handler.dart`（并行解析 + 分别发消息 + 存库兜底）
- `lib/pages/recording_page.dart`（拆分 weather/location 消息与显示）
- `lib/pages/settings_page.dart`（新增入口）
- `lib/main.dart`（注册回填迁移）
- `.env.local` / `.env.local.example` / `scripts/build.sh`（`AMAP_WEB_KEY`）
- app-backup 逻辑（纳入常用位置）

# 位置信息精简（缩短为纯地标名）— 设计

> 日期：2026-06-30
> 状态：设计中
> 承接：`2026-06-28-location-display-design.md`（引入高德位置解析）

## 1. 背景

`location-display-design` 引入了「常用位置 → 高德 POI → 高德地址」的位置解析链路。其中 `AmapService.nearestPoiOrAddress()` 的逻辑是：**优先返回 POI 名（`pois[0].name`），POI 为空才回退到 `formatted_address`（完整地址）**。

问题：`formatted_address` 是「省+市+区+街道+门牌+建筑」的完整串（如「北京市朝阳区建国门外大街1号中国国际贸易中心」），原样塞进详情页 chip / 录音页 pill 过长，影响阅读与布局。POI 命中时 POI 名一般较短，但偶尔也偏长。

## 2. 目标

1. 位置信息精简为**纯地标名**：去掉省市/区等行政前缀，只留最有辨识度的核心名。
2. **生成时精简**（方案 A）：在 `AmapService` 内用高德结构化字段确定性去前缀，存入 SQLite 的 `locationName` 即为短名。
3. **历史数据一并变短**：复用 `LocationResolveMigration`，用新逻辑重新解析全部历史日记。
4. 保持向后兼容（v1.0.0 基线）：不改 schema、不删数据、不丢数据。

## 3. 现状（位置链路）

```
LocationResolver.resolve(lat, lon, favorites)        ← 唯一解析入口
  ① 常用位置最近者 ≤ 200m            → "家"
  ② AmapService.nearestPoiOrAddress  → pois[0].name（POI 名）
                                       或 formatted_address（完整地址）
  ③ 都没有                            → null
```

- 调用点：`RecordingTaskHandler`（录音 FGS isolate，新录音）；`LocationResolveMigration.run()`（历史回填，主 isolate）。
- 存储：`locationName`（text）+ `lat`/`lon` 进 SQLite `diary_entries`；纯快照语义，存库即最终值。
- 显示：详情页 `DetailInfoBar` chip、录音页实时 pill、每日汇总 `daily_summary`——均直接读 `locationName`，UI 不区分长名/短名。
- **关键**：`LocationResolveMigration.run()` 内部调 `resolver.resolve()` → `nearestPoiOrAddress()`。**改了 `nearestPoiOrAddress` 的返回逻辑，重跑迁移即可让历史数据自动用新逻辑重新解析。**

## 4. 核心设计

### 4.1 去前缀纯函数

在 `lib/services/amap_service.dart` 新增顶层纯函数（无副作用、可单测）：

```dart
/// 从高德 formatted_address 头部依次剥离 province/city/district 行政前缀，
/// 返回核心地标部分。剥离后为空则回退 district，仍空则返回原 formatted。
String stripAdminPrefix(
  String formatted, {
  String? province,
  dynamic city, // 高德 city 对直辖市返回 [] 或 ""，普通市返回市名
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

String? _cityString(dynamic city) {
  if (city == null) return null;
  if (city is List) return city.isEmpty ? null : city.first?.toString();
  if (city is String && city.isNotEmpty) return city;
  return null;
}
```

要点：

- **确定性裁剪**，不靠正则猜测；只剥离「字符串确实以该行政名开头」的前缀。
- 处理直辖市 `city` 为空数组/空串（`_cityString` 归一化为 nullable）。
- 兜底：剥离后为空（如 formatted 仅含省市）→ 返回 `district`；`district` 也空 → 返回原 `formatted`（保证非空、可用）。

### 4.2 `nearestPoiOrAddress` 新流程

读 `regeocode.addressComponent`（base 标准返回，含 province/city/district/adcode）：

```dart
final regeocode = resp.data['regeocode'];
final addrComp = regeocode?['addressComponent'];

// ① POI 命中 → POI 名（超长截断）
final pois = regeocode?['pois'] as List?;
if (pois != null && pois.isNotEmpty) {
  final name = (pois[0]['name'] as String?)?.trim() ?? '';
  if (name.isNotEmpty) return _truncatePoiName(name);
}

// ② POI 为空 → formatted_address 去行政前缀
final formatted = (regeocode?['formatted_address'] as String?)?.trim() ?? '';
if (formatted.isEmpty) return null;
return stripAdminPrefix(
  formatted,
  province: addrComp?['province']?.toString(),
  city: addrComp?['city'],
  district: addrComp?['district']?.toString(),
);
```

- 失败 / 未配置 key / status≠1：仍返回 null（不变，符合异常规范）。
- `addressComponent` 字段缺失（base 必有，理论上不缺）：`stripAdminPrefix` 收到 null 前缀 → 不剥离 → 返回原 `formatted`（降级，不抛异常）。

### 4.3 POI 名超长截断

```dart
String _truncatePoiName(String name) {
  const max = 12;
  // 字符串长度（UTF-16 code unit，中文按 1 计）；超 max 则截断
  if (name.length > max) return '${name.substring(0, max - 1)}…';
  return name;
}
```

- 阈值 **12 字符**（如「中国国际贸易中心」9 字保留；超长建筑/店名截断）。
- 截断符用全角「…」（U+2026）。
- 仅 POI 名走截断；去前缀后的地址不再二次截断（去前缀已足够短）。

## 5. 历史数据重新解析（版本化迁移标记）

### 5.1 问题

`LocationResolveMigration` 用 SharedPreferences `location_resolve_migration_done`（bool）只跑一次，已发布的设备不会再跑，历史日记仍是旧长地址。

### 5.2 方案：版本化守卫

`lib/services/location_resolve_migration.dart`：

```dart
static const _versionKey = 'location_resolve_migration_version';
static const int _currentVersion = 2; // 本次精简 = v2

static Future<bool> isDone() async {
  final prefs = await SharedPreferences.getInstance();
  final done = prefs.getInt(_versionKey) ?? 0;
  return done >= _currentVersion;
}
```

`run()` 成功（无失败）后写入版本：

```dart
if (failed == 0) {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_versionKey, _currentVersion);
}
```

> 旧的 `_doneKey`（bool）不再读写；`_versionKey` 默认 0 < 2，所有设备首次启动都会重跑一次。遗留的 bool key 不影响（不读）。

### 5.3 效果与成本

- 效果：重跑 `run()` → 调 `resolve()` → `nearestPoiOrAddress`（新精简逻辑）→ 全部历史条目重新解析为短名。
- **完全复用现有 `run()`**，只改版本守卫与写入字段。
- API 成本：每条历史记录重调一次高德 regeo；串行 + 弱网失败下次启动重试（已有机制，`failed > 0` 不推进版本）；量取决于历史条数，可接受。
- **数据安全**：`run()` 仍只 UPDATE `locationName` 一个字段，不动 lat/lon/audio/其他；不删任何数据。

## 6. 数据兼容性

- **不改 SQLite schema**：`locationName` 仍是 text，只改值 → 无 drift migration、无需 `build_runner`。
- **不丢数据**：旧 `locationName` 正常读取显示；迁移逐步更新为短名。
- **不可逆性**：存即短名（方案 A 已确认可接受）。lat/lon 始终保留，未来如需重新解析仍有完整坐标。
- **无破坏性操作**：不 DROP TABLE、不 DELETE 无 WHERE。
- 兜底齐全（空 POI + 空地址 → null；剥离后空 → district/formatted），不会出现空位置名。

## 7. 涉及文件清单

修改：

- `lib/services/amap_service.dart`：新增 `stripAdminPrefix` 纯函数 + `_cityString` + `_truncatePoiName`；`nearestPoiOrAddress` 改用去前缀 + POI 截断逻辑。
- `lib/services/location_resolve_migration.dart`：`_doneKey`(bool) → `_versionKey`(int) + `_currentVersion=2`；`isDone` 改版本比较；`run` 改写版本。

新增：

- `test/amap_service_test.dart`：覆盖 `stripAdminPrefix`（省市区前缀 / 直辖市 city 空 / 剥离后空兜底）、`_truncatePoiName`（12 字阈值）、`nearestPoiOrAddress`（mock dio：POI 命中 / POI 空→去前缀 / 字段缺失降级 / 失败返回 null）。

更新：

- `test/location_resolve_migration_test.dart`：版本化守卫——无版本 / 版本 < 2 时重跑、写入 2 后不再重跑、单条失败不推进版本。

不改：`location_resolver.dart`（resolve 顺序不变，仅底层 amap 返回变短）、`recording_task_handler.dart`、`main.dart`、所有 UI、`tables.dart` / `app_database.dart`（无 schema 变更）、`fetchWeatherByLocation`（独立 regeo）。

## 8. 测试策略

纯函数 + 迁移守卫优先单测（无网络依赖）：

1. **`stripAdminPrefix`**：
   - 「北京市朝阳区建国门外大街1号中国国际贸易中心」+ province=北京市 → 去掉后留核心。
   - 直辖市 city=`[]` / `""` → 不误剥、不报错。
   - formatted 仅「北京市」→ 剥离后空 → 回退 district。
   - formatted 不以 province 开头（边界）→ 原样返回。
2. **`_truncatePoiName`**：≤12 字原样；13 字 → 前 11 +「…」。
3. **`nearestPoiOrAddress`**（mock dio 响应）：
   - POI 非空 → 返回 POI 名（超长截断）。
   - POI 空、formatted 含省市区 → 返回去前缀核心。
   - `addressComponent` 缺失 → 返回 formatted 原样（降级）。
   - status≠1 / 网络错误 / 未配置 key → 返回 null。
4. **迁移守卫**：构造 SharedPreferences，断言 `_currentVersion` 比较逻辑、`failed > 0` 不写版本。
5. **手动验证**：dev 构建后，陌生地点录音 → 详情页 chip 显示短地标；首次启动重跑迁移 → 历史日记位置变短。

## 9. 验收标准

- `flutter analyze` 无 issue；改动文件 `dart format` 通过。
- 新录音：陌生地点（POI 命中）显示精简 POI 名；POI 为空时显示去前缀核心地标，不再出现完整省市地址。
- 历史日记：首次启动后位置名重新解析变短（迁移版本推进到 2，再次启动不重跑）。
- 不改 SQLite schema、不触发 drift migration；不丢任何用户数据。
- 单测覆盖 `stripAdminPrefix` 各分支与迁移版本守卫。

## 10. 不做（YAGNI）

- 不做「区 + 地标」格式（用户选定纯地标名）。
- 不做读取时 formatter（方案 B，启发式有误判风险，已排除）。
- 不改 schema、不改 UI、不改 `LocationResolver` 解析顺序。
- 不为精简新增异常派生类（全程降级返回值）。
- 不对去前缀后的地址二次截断（去前缀已足够短）。
- 不对非直辖市的 `city` 做进一步剥离（街道/门牌已是核心，够用）。

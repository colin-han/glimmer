import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/weather_condition.dart';

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
}

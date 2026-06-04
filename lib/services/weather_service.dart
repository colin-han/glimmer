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

    final locParam = '${lon.toStringAsFixed(2)},${lat.toStringAsFixed(2)}';

    try {
      // 1. 逆地理编码获取城市名
      debugPrint('[天气] 请求 GeoAPI: host=$host, loc=$locParam');
      final geoResponse = await _dio.get(
        'https://$host/geo/v2/city/lookup',
        queryParameters: {
          'location': locParam,
          'number': 1,
          'lang': 'zh',
          'key': token,
        },
      );

      final geoCode = geoResponse.data['code']?.toString();
      if (geoCode != '200') {
        debugPrint('[天气] GeoAPI 返回 code=$geoCode, body=${geoResponse.data}');
        return null;
      }

      final locations = geoResponse.data['location'] as List;
      if (locations.isEmpty) return null;

      final locationName = locations[0]['name'] as String;

      // 2. 获取天气实况
      final weatherResponse = await _dio.get(
        'https://$host/v7/weather/now',
        queryParameters: {
          'location': locParam,
          'lang': 'zh',
          'key': token,
        },
      );

      final weatherCode = weatherResponse.data['code']?.toString();
      if (weatherCode != '200') {
        debugPrint('[天气] 天气API 返回 code=$weatherCode, body=${weatherResponse.data}');
        return null;
      }

      final now = weatherResponse.data['now'];
      return WeatherLocation(
        icon: now['icon'] as String,
        text: now['text'] as String,
        temp: now['temp'] as String,
        locationName: locationName,
      );
    } on DioException catch (e) {
      debugPrint('[天气] HTTP 错误: status=${e.response?.statusCode}, body=${e.response?.data}');
      return null;
    } catch (e) {
      debugPrint('[天气] 获取失败: $e');
      return null;
    }
  }
}
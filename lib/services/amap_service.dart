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
      debugPrint(
        '[高德] HTTP 错误: status=${e.response?.statusCode}, body=${e.response?.data}',
      );
      return null;
    } catch (e) {
      debugPrint('[高德] 解析失败: $e');
      return null;
    }
  }
}

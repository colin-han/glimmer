import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// 获取当前位置（粗略定位），失败返回 null
  Future<({double lat, double lon})?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[定位] 位置服务未开启');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      debugPrint('[定位] 当前权限: $permission');
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[定位] 权限被永久拒绝');
        return null;
      }
      if (permission == LocationPermission.denied) {
        debugPrint('[定位] 请求定位权限...');
        permission = await Geolocator.requestPermission();
        debugPrint('[定位] 权限结果: $permission');
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }
      }

      // 优先使用缓存位置（瞬间返回），避免室内 GPS 超时
      debugPrint('[定位] 尝试获取缓存位置...');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint('[定位] 缓存命中: ${lastKnown.latitude}, ${lastKnown.longitude}');
        return (lat: lastKnown.latitude, lon: lastKnown.longitude);
      }

      debugPrint('[定位] 无缓存，实时获取位置...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      debugPrint('[定位] 成功: ${position.latitude}, ${position.longitude}');
      return (lat: position.latitude, lon: position.longitude);
    } catch (e) {
      debugPrint('[定位] 异常: $e');
      return null;
    }
  }
}

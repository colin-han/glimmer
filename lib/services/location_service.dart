import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// 请求定位权限（必须在主 isolate / 有 Activity 上下文调用）。
  ///
  /// 后台 isolate（如录音 FGS）无 Activity，调用 [Geolocator.requestPermission]
  /// 会抛 "Activity is missing"。故权限请求须在 UI 触发（录音开始前、新增常用位置时），
  /// 后台的 [getCurrentLocation] 只读取已授予的权限。返回是否已授权。
  Future<bool> ensurePermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[定位] 位置服务未开启');
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[定位] 权限被永久拒绝');
        return false;
      }
      if (permission == LocationPermission.denied) {
        debugPrint('[定位] 请求定位权限...');
        permission = await Geolocator.requestPermission();
        debugPrint('[定位] 权限结果: $permission');
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      debugPrint('[定位] ensurePermission 异常: $e');
      return false;
    }
  }

  /// 获取当前位置（不请求权限，isolate 安全）。
  ///
  /// 调用方需先 [ensurePermission]；权限未授或失败返回 null。
  /// 优先用缓存位置（瞬间返回），避免室内 GPS 超时。
  Future<({double lat, double lon})?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // 不在此请求权限：后台 isolate 无 Activity 会抛异常。调用方应先 ensurePermission。
        debugPrint('[定位] 权限未授，跳过获取位置');
        return null;
      }
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint('[定位] 缓存命中: ${lastKnown.latitude}, ${lastKnown.longitude}');
        return (lat: lastKnown.latitude, lon: lastKnown.longitude);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      debugPrint('[定位] 成功: ${position.latitude}, ${position.longitude}');
      return (lat: position.latitude, lon: position.longitude);
    } catch (e) {
      debugPrint('[定位] getCurrentLocation 异常: $e');
      return null;
    }
  }
}

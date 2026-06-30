import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// 定位获取器：按精度与超时获取当前位置（生产调 Geolocator，测试可注入 mock）。
typedef PositionGetter =
    Future<Position> Function({
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
}

import 'package:geolocator/geolocator.dart';

import '../models/favorite_location.dart';
import 'amap_service.dart';

/// 位置名解析：常用位置(≤200m) → 高德 POI → 高德地址 → null。
///
/// 全程降级用返回值，不抛异常（符合项目异常规范）。
class LocationResolver {
  final AmapService _amap;

  LocationResolver(this._amap);

  static const double _thresholdMeters = 200;

  Future<String?> resolve({
    required double lat,
    required double lon,
    required List<FavoriteLocation> favorites,
  }) async {
    // ① 常用位置匹配（纯本地，按距离取最近）
    FavoriteLocation? nearest;
    double minDist = double.infinity;
    for (final f in favorites) {
      final d = Geolocator.distanceBetween(lat, lon, f.lat, f.lon);
      if (d < minDist) {
        minDist = d;
        nearest = f;
      }
    }
    if (nearest != null && minDist <= _thresholdMeters) {
      return nearest.name;
    }

    // ②/③ 高德（POI → 地址，失败返回 null）
    return _amap.nearestPoiOrAddress(lat, lon);
  }
}

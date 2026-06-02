import 'package:geolocator/geolocator.dart';

class LocationService {
  /// 获取当前位置（粗略定位），失败返回 null
  Future<({double lat, double lon})?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) return null;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return (lat: position.latitude, lon: position.longitude);
    } catch (_) {
      return null;
    }
  }
}
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/services/location_service.dart';

class _MockPosition extends Mock implements Position {}

/// 构造一个 stub 了 latitude/longitude 的 mock Position。
Position _pos(double lat, double lon) {
  final p = _MockPosition();
  when(() => p.latitude).thenReturn(lat);
  when(() => p.longitude).thenReturn(lon);
  return p;
}

void main() {
  group('resolvePositionWithFallback', () {
    test('high 成功 → 返回 high 位置，不调 low', () async {
      var lowCalled = false;
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) return _pos(34.0, 108.0);
        lowCalled = true;
        return _pos(0, 0);
      }

      final result = await resolvePositionWithFallback(getter);

      expect(result, (lat: 34.0, lon: 108.0));
      expect(lowCalled, isFalse);
    });

    test('high 超时/失败 → 降级 low 成功', () async {
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) {
          throw Exception('超时');
        }
        return _pos(34.1, 108.1);
      }

      final result = await resolvePositionWithFallback(getter);

      expect(result, (lat: 34.1, lon: 108.1));
    });

    test('high + low 都失败 → null', () async {
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        throw Exception('失败');
      }

      final result = await resolvePositionWithFallback(getter);

      expect(result, isNull);
    });

    test('high 用 8s timeLimit', () async {
      Duration? highLimit;
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) {
          highLimit = timeLimit;
          return _pos(1, 1);
        }
        return _pos(2, 2);
      }

      await resolvePositionWithFallback(getter);

      expect(highLimit, const Duration(seconds: 8));
    });

    test('high 失败时 low 用 5s timeLimit', () async {
      Duration? lowLimit;
      Future<Position> getter({
        required LocationAccuracy accuracy,
        required Duration timeLimit,
      }) async {
        if (accuracy == LocationAccuracy.high) {
          throw Exception('超时');
        }
        lowLimit = timeLimit;
        return _pos(2, 2);
      }

      await resolvePositionWithFallback(getter);

      expect(lowLimit, const Duration(seconds: 5));
    });
  });
}

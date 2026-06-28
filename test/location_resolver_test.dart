import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_diary/models/favorite_location.dart';
import 'package:voice_diary/services/amap_service.dart';
import 'package:voice_diary/services/location_resolver.dart';

class _MockAmap extends Mock implements AmapService {}

void main() {
  late _MockAmap amap;
  late LocationResolver resolver;

  setUp(() {
    amap = _MockAmap();
    resolver = LocationResolver(amap);
    registerFallbackValue(0.0);
  });

  test('常用位置命中(同点 0m) → 返回常用名，不调高德', () async {
    final fav = FavoriteLocation(
      id: '1',
      name: '家',
      lat: 34.0,
      lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final result = await resolver.resolve(
      lat: 34.0,
      lon: 108.0,
      favorites: [fav],
    );
    expect(result, '家');
    verifyNever(() => amap.nearestPoiOrAddress(any(), any()));
  });

  test('常用位置越界(~920m) → 调高德返回 POI', () async {
    // 经度差 0.01°（约 920m）> 200m 阈值
    final fav = FavoriteLocation(
      id: '1',
      name: '家',
      lat: 34.0,
      lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    when(
      () => amap.nearestPoiOrAddress(any(), any()),
    ).thenAnswer((_) async => '星巴克国贸店');
    final result = await resolver.resolve(
      lat: 34.0,
      lon: 108.01,
      favorites: [fav],
    );
    expect(result, '星巴克国贸店');
  });

  test('无常用位置 + 高德成功 → 返回高德结果', () async {
    when(
      () => amap.nearestPoiOrAddress(any(), any()),
    ).thenAnswer((_) async => '雁塔路');
    final result = await resolver.resolve(
      lat: 34.0,
      lon: 108.0,
      favorites: const [],
    );
    expect(result, '雁塔路');
  });

  test('无常用位置 + 高德失败 → 返回 null', () async {
    when(
      () => amap.nearestPoiOrAddress(any(), any()),
    ).thenAnswer((_) async => null);
    final result = await resolver.resolve(
      lat: 34.0,
      lon: 108.0,
      favorites: const [],
    );
    expect(result, isNull);
  });

  test('多个常用位置取最近且命中', () async {
    final near = FavoriteLocation(
      id: '1',
      name: '公司',
      lat: 34.0,
      lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final far = FavoriteLocation(
      id: '2',
      name: '家',
      lat: 40.0,
      lon: 116.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final result = await resolver.resolve(
      lat: 34.0001,
      lon: 108.0001,
      favorites: [near, far],
    );
    expect(result, '公司');
  });
}

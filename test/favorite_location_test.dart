import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/favorite_location.dart';

void main() {
  test('toJson/fromJson 往返保持一致', () {
    final original = FavoriteLocation(
      id: 'abc',
      name: '家',
      lat: 34.0,
      lon: 108.0,
      createdAt: DateTime(2026, 6, 28, 10, 0),
    );
    final json = original.toJson();
    final restored = FavoriteLocation.fromJson(json);
    expect(restored.id, 'abc');
    expect(restored.name, '家');
    expect(restored.lat, 34.0);
    expect(restored.lon, 108.0);
    expect(restored.createdAt, original.createdAt);
  });

  test('copyWith 仅改 name', () {
    final original = FavoriteLocation(
      id: 'abc',
      name: '家',
      lat: 34.0,
      lon: 108.0,
      createdAt: DateTime(2026, 6, 28),
    );
    final renamed = original.copyWith(name: '家（新）');
    expect(renamed.name, '家（新）');
    expect(renamed.id, 'abc');
    expect(renamed.lat, 34.0);
  });
}

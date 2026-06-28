import 'package:uuid/uuid.dart';

class FavoriteLocation {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final DateTime createdAt;

  const FavoriteLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.createdAt,
  });

  /// 新建：自动生成 id 与时间戳。
  factory FavoriteLocation.create({
    required String name,
    required double lat,
    required double lon,
  }) {
    return FavoriteLocation(
      id: const Uuid().v4(),
      name: name,
      lat: lat,
      lon: lon,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lon': lon,
    'createdAt': createdAt.toIso8601String(),
  };

  factory FavoriteLocation.fromJson(Map<String, dynamic> json) {
    return FavoriteLocation(
      id: json['id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  FavoriteLocation copyWith({String? name}) => FavoriteLocation(
    id: id,
    name: name ?? this.name,
    lat: lat,
    lon: lon,
    createdAt: createdAt,
  );
}

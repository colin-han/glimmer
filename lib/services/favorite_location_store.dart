import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_location.dart';

/// 常用位置存储（SharedPreferences）。isolate 安全：各 isolate 各自
/// `getInstance()` 读同一份偏好数据。
class FavoriteLocationStore {
  static const _key = 'pref_favorite_locations';

  Future<List<FavoriteLocation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => FavoriteLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<FavoriteLocation> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((f) => f.toJson()).toList()),
    );
  }

  Future<List<FavoriteLocation>> add(
    String name,
    double lat,
    double lon,
  ) async {
    final list = await load();
    list.add(FavoriteLocation.create(name: name, lat: lat, lon: lon));
    await _save(list);
    return list;
  }

  Future<List<FavoriteLocation>> rename(String id, String name) async {
    final list = (await load())
        .map((f) => f.id == id ? f.copyWith(name: name) : f)
        .toList();
    await _save(list);
    return list;
  }

  Future<List<FavoriteLocation>> remove(String id) async {
    final list = (await load()).where((f) => f.id != id).toList();
    await _save(list);
    return list;
  }
}

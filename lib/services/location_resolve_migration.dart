import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diary_storage_service.dart';
import 'favorite_location_store.dart';
import 'location_resolver.dart';

/// 历史位置回填：用已有 lat/lon 重新解析 locationName（常用位置 → 高德地标）。
/// 串行调用高德，单条失败不阻塞；只 UPDATE locationName 字段，不动其他数据。
class LocationResolveMigration {
  static const _doneKey = 'location_resolve_migration_done';

  final DiaryStorageService _storage;
  final LocationResolver _resolver;
  final FavoriteLocationStore _favStore;

  LocationResolveMigration(this._storage, this._resolver, this._favStore);

  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_doneKey) ?? false;
  }

  /// 执行回填，返回更新条数。幂等性由调用方用 [isDone] 守卫。
  Future<int> run() async {
    final favorites = await _favStore.load();
    final entries = await _storage.getAllEntries();
    var updated = 0;
    var failed = 0;
    for (final e in entries) {
      if (e.locationLat == null || e.locationLon == null) continue;
      try {
        final name = await _resolver.resolve(
          lat: e.locationLat!,
          lon: e.locationLon!,
          favorites: favorites,
        );
        if (name != null && name.isNotEmpty) {
          await _storage.updateLocationName(e.id, name);
          updated++;
        }
      } catch (err) {
        failed++;
        debugPrint('[位置回填] 跳过 ${e.id}: $err');
      }
    }
    // 仅当无解析失败时标记完成：失败的条目下次启动重试（应对弱网）。
    // resolve 返回 null（高德无地标）不算失败，不重试。
    if (failed == 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_doneKey, true);
    }
    return updated;
  }
}

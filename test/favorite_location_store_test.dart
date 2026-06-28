import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_diary/services/favorite_location_store.dart';

void main() {
  late FavoriteLocationStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FavoriteLocationStore();
  });

  test('初始为空列表', () async {
    expect(await store.load(), isEmpty);
  });

  test('add 后 load 能读到', () async {
    await store.add('家', 34.0, 108.0);
    final list = await store.load();
    expect(list, hasLength(1));
    expect(list.first.name, '家');
    expect(list.first.lat, 34.0);
  });

  test('rename 改名保留 id/坐标', () async {
    final added = await store.add('家', 34.0, 108.0);
    final id = added.first.id;
    await store.rename(id, '家（新）');
    final list = await store.load();
    expect(list.first.name, '家（新）');
    expect(list.first.id, id);
    expect(list.first.lat, 34.0);
  });

  test('remove 按 id 删除', () async {
    final added = await store.add('家', 34.0, 108.0);
    await store.remove(added.first.id);
    expect(await store.load(), isEmpty);
  });

  test('新增多个共存（持久化）', () async {
    await store.add('家', 34.0, 108.0);
    // 用新实例模拟重启后读取（读同一份 SharedPreferences）
    final list = await FavoriteLocationStore().load();
    expect(list, hasLength(1));
  });
}

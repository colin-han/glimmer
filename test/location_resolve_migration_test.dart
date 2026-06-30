import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_diary/models/diary_entry.dart';
import 'package:voice_diary/services/diary_storage_service.dart';
import 'package:voice_diary/services/favorite_location_store.dart';
import 'package:voice_diary/services/location_resolve_migration.dart';
import 'package:voice_diary/services/location_resolver.dart';

class _MockStorage extends Mock implements DiaryStorageService {}

class _MockResolver extends Mock implements LocationResolver {}

class _MockFavStore extends Mock implements FavoriteLocationStore {}

void main() {
  late _MockStorage storage;
  late _MockResolver resolver;
  late _MockFavStore favStore;
  late LocationResolveMigration migration;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = _MockStorage();
    resolver = _MockResolver();
    favStore = _MockFavStore();
    migration = LocationResolveMigration(storage, resolver, favStore);
  });

  test('只回填有 lat/lon 的条目，更新 locationName，并置完成标志', () async {
    final withLoc = DiaryEntry(
      id: 'a',
      title: 't',
      folderPath: '/a',
      durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
      locationLat: 34.0,
      locationLon: 108.0,
      locationName: '雁塔区',
    );
    final noLoc = DiaryEntry(
      id: 'b',
      title: 't',
      folderPath: '/b',
      durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
    );
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(
      () => storage.getAllEntries(),
    ).thenAnswer((_) async => [withLoc, noLoc]);
    when(
      () => resolver.resolve(
        lat: 34.0,
        lon: 108.0,
        favorites: any(named: 'favorites'),
      ),
    ).thenAnswer((_) async => '星巴克');
    when(
      () => storage.updateLocationName(any(), any()),
    ).thenAnswer((_) async {});

    final count = await migration.run();

    expect(count, 1);
    verify(() => storage.updateLocationName('a', '星巴克')).called(1);
    verifyNever(() => storage.updateLocationName('b', any()));
    expect(await LocationResolveMigration.isDone(), isTrue);
  });

  test('resolve 返回 null/空 不更新', () async {
    final withLoc = DiaryEntry(
      id: 'a',
      title: 't',
      folderPath: '/a',
      durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
      locationLat: 34.0,
      locationLon: 108.0,
    );
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => [withLoc]);
    when(
      () => resolver.resolve(
        lat: 34.0,
        lon: 108.0,
        favorites: any(named: 'favorites'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => storage.updateLocationName(any(), any()),
    ).thenAnswer((_) async {});

    expect(await migration.run(), 0);
    verifyNever(() => storage.updateLocationName(any(), any()));
  });

  test('isDone 为 true 时 run 仍可执行（幂等由调用方判断）', () async {
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => const []);
    expect(await migration.run(), 0);
  });

  test('单条 resolve 异常不阻塞后续，且有失败时不标记完成（弱网重试）', () async {
    final a = DiaryEntry(
      id: 'a',
      title: 't',
      folderPath: '/a',
      durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
      locationLat: 34.0,
      locationLon: 108.0,
    );
    final b = DiaryEntry(
      id: 'b',
      title: 't',
      folderPath: '/b',
      durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
      locationLat: 35.0,
      locationLon: 109.0,
    );
    final c = DiaryEntry(
      id: 'c',
      title: 't',
      folderPath: '/c',
      durationSeconds: 1,
      createdAt: DateTime(2026, 6, 28),
      locationLat: 36.0,
      locationLon: 110.0,
    );
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => [a, b, c]);
    when(
      () => resolver.resolve(
        lat: 34.0,
        lon: 108.0,
        favorites: any(named: 'favorites'),
      ),
    ).thenAnswer((_) async => '地标A');
    when(
      () => resolver.resolve(
        lat: 35.0,
        lon: 109.0,
        favorites: any(named: 'favorites'),
      ),
    ).thenThrow(Exception('网络失败'));
    when(
      () => resolver.resolve(
        lat: 36.0,
        lon: 110.0,
        favorites: any(named: 'favorites'),
      ),
    ).thenAnswer((_) async => '地标C');
    when(
      () => storage.updateLocationName(any(), any()),
    ).thenAnswer((_) async {});

    final count = await migration.run();

    expect(count, 2);
    verify(() => storage.updateLocationName('a', '地标A')).called(1);
    verify(() => storage.updateLocationName('c', '地标C')).called(1);
    verifyNever(() => storage.updateLocationName('b', any()));
    expect(await LocationResolveMigration.isDone(), isFalse);
  });

  test('遗留旧 bool 标志位时，版本化守卫仍判定未完成（需重跑）', () async {
    // 模拟已发布设备：v1 迁移跑过，遗留旧的 bool 标志 true
    SharedPreferences.setMockInitialValues({
      'location_resolve_migration_done': true,
    });
    // 新版本化守卫读 _versionKey（不存在→0），0 < 2 → 未完成，需重跑
    expect(await LocationResolveMigration.isDone(), isFalse);
  });

  test('run 成功后写入当前版本，isDone 为 true', () async {
    SharedPreferences.setMockInitialValues({});
    when(() => favStore.load()).thenAnswer((_) async => const []);
    when(() => storage.getAllEntries()).thenAnswer((_) async => const []);

    await migration.run();

    expect(await LocationResolveMigration.isDone(), isTrue);
  });
}

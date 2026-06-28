import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('onUpgrade 9→10：含和风代码的行 weather_condition 被回填', () async {
    // 内存库 onCreate 已建 v10 全表（weather_condition 列存在但为空）
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
      "created_at, weather_icon, status, processing_stage) "
      "VALUES ('a','t','/a',1,0,'104','completed','uploading')",
    );
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
      "created_at, weather_icon, status, processing_stage) "
      "VALUES ('b','t','/b',1,0,'305','completed','uploading')",
    );
    // 无和风代码的行
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
      "created_at, status, processing_stage) "
      "VALUES ('c','t','/c',1,0,'completed','uploading')",
    );

    // 手动触发 onUpgrade（from=9）
    await db.migration.onUpgrade.call(db.createMigrator(), 9, 10);

    final a = await db
        .customSelect(
          "SELECT weather_condition, weather_icon FROM diary_entries WHERE id='a'",
        )
        .getSingle();
    expect(a.read<String>('weather_condition'), 'overcast');
    expect(a.readNullable<String>('weather_icon'), '104'); // 旧列保留

    final b = await db
        .customSelect(
          "SELECT weather_condition FROM diary_entries WHERE id='b'",
        )
        .getSingle();
    expect(b.read<String>('weather_condition'), 'drizzle');

    final c = await db
        .customSelect(
          "SELECT weather_condition FROM diary_entries WHERE id='c'",
        )
        .getSingle();
    expect(c.readNullable<String>('weather_condition'), isNull);
  });

  test('onUpgrade 幂等：重复执行不报错、不重复改写', () async {
    await db.customStatement(
      "INSERT INTO diary_entries (id, title, folder_path, duration_seconds, "
      "created_at, weather_icon, status, processing_stage) "
      "VALUES ('a','t','/a',1,0,'100','completed','uploading')",
    );
    await db.migration.onUpgrade.call(db.createMigrator(), 9, 10);
    await db.migration.onUpgrade.call(db.createMigrator(), 9, 10); // 再跑一次
    final a = await db
        .customSelect(
          "SELECT weather_condition FROM diary_entries WHERE id='a'",
        )
        .getSingle();
    expect(a.read<String>('weather_condition'), 'sunny');
  });
}

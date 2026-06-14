# 自动归类功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为语音日记 App 增加 tag 系统，支持自动归类、手动管理、搜索和分组展示。

**Architecture:** 纯 SQLite（drift）驱动，新增 Tags + DiaryTagRelations 两张表。LLM 负责自动打 tag 和新建 tag 时的推荐/提示词生成。录音流程在 LLM 润色后增加自动归类步骤，采用防御性保存策略。

**Tech Stack:** Flutter + drift + dio（已有），无新增依赖。

---

## Task 1: 数据模型 + 数据库迁移

**Files:**
- Create: `lib/models/tag.dart`
- Modify: `lib/services/database/tables.dart`
- Modify: `lib/services/database/app_database.dart`
- Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 1: 创建 Tag 数据模型**

创建 `lib/models/tag.dart`：

```dart
class Tag {
  final String id;
  final String name;
  final String matchPrompt;
  final String? color;
  final DateTime createdAt;

  const Tag({
    required this.id,
    required this.name,
    required this.matchPrompt,
    this.color,
    required this.createdAt,
  });
}

class DiaryTagRelation {
  final String diaryId;
  final String tagId;
  final String source; // 'auto' | 'manual'
  final DateTime createdAt;

  const DiaryTagRelation({
    required this.diaryId,
    required this.tagId,
    required this.source,
    required this.createdAt,
  });
}
```

- [ ] **Step 2: 在 tables.dart 中新增 Tags 和 DiaryTagRelations 表**

在 `lib/services/database/tables.dart` 末尾追加：

```dart
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get matchPrompt => text().withDefault(const Constant(''))();
  TextColumn get color => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name}
      ];
}

class DiaryTagRelations extends Table {
  TextColumn get diaryId => text().references(DiaryEntries, #id)();
  TextColumn get tagId => text().references(Tags, #id)();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {diaryId, tagId};
}
```

- [ ] **Step 3: 更新 app_database.dart — 注册新表 + schema v2 迁移**

将 `lib/services/database/app_database.dart` 替换为：

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [DiaryEntries, Tags, DiaryTagRelations])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(tags);
            await m.createTable(diaryTagRelations);
          }
        },
      );

  // --- DiaryEntries ---

  Future<List<DiaryEntry>> getAllEntries() {
    return (select(diaryEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<DiaryEntry> getEntryById(String id) {
    return (select(diaryEntries)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> insertEntry(DiaryEntriesCompanion entry) {
    return into(diaryEntries).insert(entry);
  }

  Future<void> deleteEntry(String id) {
    return (delete(diaryEntries)..where((t) => t.id.equals(id))).go();
  }

  // --- Tags ---

  Future<List<Tag>> getAllTags() {
    return (select(tags)..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<Tag> getTagById(String id) {
    return (select(tags)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> insertTag(TagsCompanion tag) {
    return into(tags).insert(tag);
  }

  Future<void> updateTag(TagsCompanion tag) {
    return (update(tags)..where((t) => t.id.equals(tag.id.value)))
        .write(tag);
  }

  Future<void> deleteTag(String id) {
    return (delete(tags)..where((t) => t.id.equals(id))).go();
  }

  // --- DiaryTagRelations ---

  Future<void> insertDiaryTag(DiaryTagRelationsCompanion relation) {
    return into(diaryTagRelations).insert(relation,
        mode: InsertMode.insertOrIgnore);
  }

  Future<void> deleteDiaryTag(String diaryId, String tagId) {
    return (delete(diaryTagRelations)
          ..where((t) => t.diaryId.equals(diaryId) & t.tagId.equals(tagId)))
        .go();
  }

  Future<void> deleteDiaryTagsByTag(String tagId) {
    return (delete(diaryTagRelations)..where((t) => t.tagId.equals(tagId)))
        .go();
  }

  Future<void> deleteDiaryTagsByDiary(String diaryId) {
    return (delete(diaryTagRelations)..where((t) => t.diaryId.equals(diaryId)))
        .go();
  }

  Future<List<DiaryTagRelation>> getTagsForDiary(String diaryId) {
    return (select(diaryTagRelations)
          ..where((t) => t.diaryId.equals(diaryId)))
        .get();
  }

  Future<List<DiaryTagRelation>> getDiariesForTag(String tagId) {
    return (select(diaryTagRelations)
          ..where((t) => t.tagId.equals(tagId)))
        .get();
  }

  Future<int> getDiaryCountForTag(String tagId) {
    return (select(diaryTagRelations)
          ..where((t) => t.tagId.equals(tagId)))
        .get()
        .then((rows) => rows.length);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'voice_diary.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

- [ ] **Step 4: 运行 build_runner 重新生成代码**

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 5: 验证生成成功**

确认 `lib/services/database/app_database.g.dart` 已更新，包含新的表类。

- [ ] **Step 6: Commit**

```bash
git add lib/models/tag.dart lib/services/database/tables.dart lib/services/database/app_database.dart lib/services/database/app_database.g.dart
git commit -m "feat: 新增 Tags 和 DiaryTagRelations 数据表，数据库升级 v2"
```

---

## Task 2: DiaryStorageService — Tag CRUD 方法

**Files:**
- Modify: `lib/services/diary_storage_service.dart`

- [ ] **Step 1: 添加 import 和 Tag CRUD 方法**

在 `diary_storage_service.dart` 文件中：

1. 添加 import：`import '../models/tag.dart';`
2. 在文件末尾（`}` 之前）追加以下方法：

```dart
  // --- Tag CRUD ---

  Future<List<Tag>> getAllTags() async {
    final rows = await _db.getAllTags();
    return rows
        .map((r) => Tag(
              id: r.id,
              name: r.name,
              matchPrompt: r.matchPrompt,
              color: r.color,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ))
        .toList();
  }

  Future<Tag> getTagById(String id) async {
    final r = await _db.getTagById(id);
    return Tag(
      id: r.id,
      name: r.name,
      matchPrompt: r.matchPrompt,
      color: r.color,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    );
  }

  Future<void> createTag(Tag tag) async {
    await _db.insertTag(TagsCompanion.insert(
      id: tag.id,
      name: tag.name,
      matchPrompt: Value(tag.matchPrompt),
      color: Value(tag.color),
      createdAt: tag.createdAt.millisecondsSinceEpoch,
    ));
  }

  Future<void> updateTag(Tag tag) async {
    await _db.updateTag(TagsCompanion(
      id: Value(tag.id),
      name: Value(tag.name),
      matchPrompt: Value(tag.matchPrompt),
      color: Value(tag.color),
      createdAt: Value(tag.createdAt.millisecondsSinceEpoch),
    ));
  }

  Future<void> deleteTag(String tagId) async {
    await _db.deleteDiaryTagsByTag(tagId);
    await _db.deleteTag(tagId);
  }

  // --- DiaryTagRelation ---

  Future<void> addDiaryTag(String diaryId, String tagId, {String source = 'manual'}) async {
    await _db.insertDiaryTag(DiaryTagRelationsCompanion.insert(
      diaryId: diaryId,
      tagId: tagId,
      source: Value(source),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> removeDiaryTag(String diaryId, String tagId) async {
    await _db.deleteDiaryTag(diaryId, tagId);
  }

  Future<List<DiaryTagRelation>> getTagsForDiary(String diaryId) async {
    return await _db.getTagsForDiary(diaryId);
  }

  Future<int> getDiaryCountForTag(String tagId) async {
    return await _db.getDiaryCountForTag(tagId);
  }

  Future<void> autoTagDiary(String diaryId, List<String> tagIds) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final tagId in tagIds) {
      await _db.insertDiaryTag(DiaryTagRelationsCompanion.insert(
        diaryId: diaryId,
        tagId: tagId,
        source: const Value('auto'),
        createdAt: now,
      ));
    }
  }

  /// 获取日记的完整 tag 信息（用于展示）
  Future<List<Tag>> getFullTagsForDiary(String diaryId) async {
    final relations = await getTagsForDiary(diaryId);
    final tags = <Tag>[];
    for (final rel in relations) {
      try {
        tags.add(await getTagById(rel.tagId));
      } catch (_) {}
    }
    return tags;
  }

  /// 搜索日记：标题匹配 + 正文内容匹配
  Future<List<DiaryEntry>> searchEntries(String query) async {
    final allEntries = await getAllEntries();
    final lowerQuery = query.toLowerCase();

    final results = <DiaryEntry>[];
    for (final entry in allEntries) {
      // 标题匹配
      if (entry.title.toLowerCase().contains(lowerQuery)) {
        results.add(entry);
        continue;
      }
      // 正文匹配（读取 llm_result.json 的 content 字段）
      try {
        if (await hasLlmResult(entry.folderPath)) {
          final llmData = await readLlmResult(entry.folderPath);
          if (llmData.content.toLowerCase().contains(lowerQuery)) {
            results.add(entry);
          }
        }
      } catch (_) {}
    }
    return results;
  }
```

注意：文件顶部需要添加 `import 'package:drift/drift.dart' show Value;`（已有 `import 'package:drift/drift.dart' show Value;`，确认即可）。

- [ ] **Step 2: Commit**

```bash
git add lib/services/diary_storage_service.dart
git commit -m "feat: DiaryStorageService 新增 tag 相关 CRUD 和搜索方法"
```

---

## Task 3: LlmService — 自动打 Tag + 新建 Tag 推荐

**Files:**
- Modify: `lib/services/llm_service.dart`

- [ ] **Step 1: 添加自动打 tag 方法**

在 `LlmService` 类的 `_parseResult` 方法之前，添加以下方法：

```dart
  /// 自动打 tag：根据正文和 tag 列表匹配
  Future<List<String>> matchTags(String content, List<TagInfo> tagInfos) async {
    if (tagInfos.isEmpty) return [];

    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final tagsJson = tagInfos
        .map((t) =>
            '{"id": "${t.id}", "name": "${t.name}", "matchPrompt": "${t.matchPrompt}"}')
        .join('\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记分类助手。你会收到一篇日记正文和一组标签（每条包含 id、name、matchPrompt）。\n'
                '请根据每条标签的 matchPrompt 描述，判断该日记是否属于该标签。\n'
                '严格按以下 JSON 格式返回匹配的标签 ID 列表，不要包含任何其他内容：\n'
                '{"matchedTagIds": ["id1", "id2"]}\n'
                '如果没有匹配的标签，返回空列表：{"matchedTagIds": []}',
          },
          {
            'role': 'user',
            'content': '日记正文：\n$content\n\n标签列表：\n$tagsJson',
          },
        ],
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }),
    );

    final respContent =
        response.data['choices'][0]['message']['content'] as String;
    try {
      final cleaned = respContent
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      return (json['matchedTagIds'] as List<dynamic>)
          .map((id) => id as String)
          .toList();
    } catch (_) {
      return [];
    }
  }
```

- [ ] **Step 2: 添加新建 tag 时的推荐日记方法**

继续在 `LlmService` 类中添加：

```dart
  /// 新建 tag 时，LLM 推荐匹配的日记
  Future<List<TagDiaryRecommendation>> recommendDiariesForTag(
      String tagName, List<DiarySummaryInfo> diaries) async {
    if (diaries.isEmpty) return [];

    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final diariesJson = diaries
        .map((d) =>
            '{"id": "${d.id}", "title": "${d.title}", "summary": "${d.summary}"}')
        .join('\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记分类助手。用户正在创建一个名为「$tagName」的标签。\n'
                '请分析以下日记列表，推荐可能属于该标签的日记。\n'
                '严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
                '{"recommendations": [{"diaryId": "id", "reason": "推荐理由"}]}\n'
                '只推荐确实相关的日记，不要强行推荐。',
          },
          {
            'role': 'user',
            'content': '标签名称：$tagName\n\n日记列表：\n$diariesJson',
          },
        ],
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }),
    );

    final respContent =
        response.data['choices'][0]['message']['content'] as String;
    try {
      final cleaned = respContent
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      return (json['recommendations'] as List<dynamic>)
          .map((r) => TagDiaryRecommendation(
                diaryId: r['diaryId'] as String,
                reason: r['reason'] as String,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 基于用户确认的日记，生成 tag 匹配提示词
  Future<String> generateMatchPrompt(
      String tagName, List<DiarySummaryInfo> confirmedDiaries) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final diariesText = confirmedDiaries
        .map((d) => '标题：${d.title}\n摘要：${d.summary}')
        .join('\n\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记分类助手。用户正在创建一个名为「$tagName」的标签。\n'
                '以下是用户确认属于该标签的日记内容。请根据这些日记的共同特征，生成一段简洁的匹配提示词。\n'
                '提示词用于后续自动判断新日记是否属于该标签。\n'
                '只输出提示词纯文本，不要加引号或其他格式，不超过100个字。',
          },
          {
            'role': 'user',
            'content': diariesText,
          },
        ],
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }),
    );

    return response.data['choices'][0]['message']['content'] as String;
  }
```

- [ ] **Step 3: 在 llm_service.dart 文件顶部添加辅助类**

在 `LlmService` 类定义之前添加：

```dart
class TagInfo {
  final String id;
  final String name;
  final String matchPrompt;

  const TagInfo({required this.id, required this.name, required this.matchPrompt});
}

class DiarySummaryInfo {
  final String id;
  final String title;
  final String summary;

  const DiarySummaryInfo({required this.id, required this.title, required this.summary});
}

class TagDiaryRecommendation {
  final String diaryId;
  final String reason;

  const TagDiaryRecommendation({required this.diaryId, required this.reason});
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/services/llm_service.dart
git commit -m "feat: LlmService 新增自动打 tag、推荐日记和生成提示词方法"
```

---

## Task 4: 步骤进度指示器更新

**Files:**
- Modify: `lib/widgets/step_progress_indicator.dart`

- [ ] **Step 1: 更新步骤列表**

将 `_steps` 常量从 4 步更新为 5 步：

```dart
  static const _steps = ['语音识别', '保存原文', 'AI 总结', '自动归类', '完成'];
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/step_progress_indicator.dart
git commit -m "feat: 步骤进度指示器增加「自动归类」步骤"
```

---

## Task 5: 录音页面 — 集成自动打 Tag

**Files:**
- Modify: `lib/pages/recording_page.dart`

- [ ] **Step 1: 添加 import**

在文件顶部 import 区域添加：

```dart
import '../models/tag.dart';
```

（注意：`../models/utterance.dart` 已有 import，`tag.dart` 需要新增。但实际上 tag 模型在 `LlmService` 中以 `TagInfo` 形式使用，录音页不直接用 `Tag` 模型，这里只需确认 import 即可。）

- [ ] **Step 2: 修改 _stopAndProcess 中的步骤编号和保存逻辑**

将 `_stopAndProcess` 方法中的流程改造。核心变更：

1. 步骤 2（LLM）完成后，**立即保存元数据**（原有步骤 3 前移）
2. 新增步骤 3（自动归类）
3. 步骤 4 为完成

将 `_stopAndProcess` 中 `// 步骤 2: LLM 润色` 后面的代码块替换为：

```dart
      // 步骤 2: LLM 润色（保留时间戳）
      setState(() => _processingStep = 2);
      LlmResult? llmResult;
      try {
        llmResult = await _llmService.summarize(asrResult.utterances);
        await _storageService.writeLlmResult(
            _currentFolderPath!,
            LlmResultData(
              version: 1,
              title: llmResult.title,
              content: llmResult.content,
              summary: llmResult.summary,
              outline: llmResult.outline,
              utterances: llmResult.utterances,
            ));
        debugPrint('[流程] LLM summarize 完成: ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[流程] LLM 失败: $e');
        await _saveEntryAndNavigate('未命名日记', duration);
        return;
      }

      // 步骤 3: 保存元数据（防御性保存：LLM 成功后立即入库）
      setState(() => _processingStep = 3);
      final entry = DiaryEntry(
        id: _currentFolderId!,
        title: llmResult.title,
        folderPath: _currentFolderPath!,
        durationSeconds: duration,
        createdAt: DateTime.now(),
      );
      await _storageService.createEntry(entry);
      debugPrint('[流程] 保存元数据完成: ${sw.elapsedMilliseconds}ms');

      // TTS 触发点 2：低沉男声播报总结（失败不阻塞）
      _speakSummary(llmResult.outline);

      // 步骤 4: 自动归类（失败不阻塞）
      setState(() => _processingStep = 4);
      try {
        final allTags = await _storageService.getAllTags();
        final tagsWithPrompt = allTags.where((t) => t.matchPrompt.isNotEmpty).toList();
        if (tagsWithPrompt.isNotEmpty) {
          final tagInfos = tagsWithPrompt
              .map((t) => TagInfo(id: t.id, name: t.name, matchPrompt: t.matchPrompt))
              .toList();
          final matchedTagIds = await _llmService.matchTags(llmResult.content, tagInfos);
          if (matchedTagIds.isNotEmpty) {
            await _storageService.autoTagDiary(_currentFolderId!, matchedTagIds);
          }
          debugPrint('[流程] 自动归类完成: 匹配 ${matchedTagIds.length} 个标签');
        }
      } catch (e) {
        debugPrint('[流程] 自动归类失败（不阻塞）: $e');
      }

      if (mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => DiaryDetailPage(entry: entry),
            ))
            .then((_) {
          setState(() {
            _state = RecordingState.idle;
            _hasError = false;
            _processingStep = 0;
            _recordingSeconds = 0;
            _realtimeText = '';
          });
        });
      }
```

注意：需要添加 import `import '../services/llm_service.dart' show LlmService, LlmResult, TagInfo;`（已有 `import '../services/llm_service.dart';`，但需确认 `TagInfo` 可访问）。

- [ ] **Step 3: Commit**

```bash
git add lib/pages/recording_page.dart
git commit -m "feat: 录音流程集成自动归类，采用防御性保存策略"
```

---

## Task 6: Tag 选择器 BottomSheet 组件

**Files:**
- Create: `lib/widgets/tag_selector_sheet.dart`

- [ ] **Step 1: 创建 Tag 选择器组件**

创建 `lib/widgets/tag_selector_sheet.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/tag.dart';
import '../services/diary_storage_service.dart';

/// Tag 选择/内联创建 BottomSheet
/// 返回用户选中的 tagId 列表
Future<List<String>?> showTagSelectorSheet(
  BuildContext context, {
  required List<String> selectedTagIds,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TagSelectorContent(selectedTagIds: selectedTagIds),
  );
}

class _TagSelectorContent extends StatefulWidget {
  final List<String> selectedTagIds;

  const _TagSelectorContent({required this.selectedTagIds});

  @override
  State<_TagSelectorContent> createState() => _TagSelectorContentState();
}

class _TagSelectorContentState extends State<_TagSelectorContent> {
  final _storageService = DiaryStorageService();
  List<Tag> _tags = [];
  late Set<String> _selectedIds;
  bool _loading = true;
  bool _showCreateField = false;
  final _newTagNameController = TextEditingController();
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedTagIds);
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _storageService.getAllTags();
    if (mounted) {
      setState(() {
        _tags = tags;
        _loading = false;
      });
    }
  }

  Future<void> _createTag(String name) async {
    final tag = Tag(
      id: _uuid.v4(),
      name: name.trim(),
      matchPrompt: '',
      createdAt: DateTime.now(),
    );
    await _storageService.createTag(tag);
    _selectedIds.add(tag.id);
    _newTagNameController.clear();
    _showCreateField = false;
    await _loadTags();
  }

  @override
  void dispose() {
    _newTagNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('选择标签', style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => Navigator.pop(context, _selectedIds.toList()),
                child: const Text('完成'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags.map((tag) {
                final selected = _selectedIds.contains(tag.id);
                return FilterChip(
                  label: Text(tag.name),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedIds.add(tag.id);
                      } else {
                        _selectedIds.remove(tag.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (_showCreateField)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTagNameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '输入新标签名称',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) _createTag(val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      if (_newTagNameController.text.trim().isNotEmpty) {
                        _createTag(_newTagNameController.text);
                      }
                    },
                  ),
                ],
              )
            else
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('新建标签'),
                onPressed: () => setState(() => _showCreateField = true),
              ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/tag_selector_sheet.dart
git commit -m "feat: 新增 Tag 选择器 BottomSheet 组件，支持内联创建"
```

---

## Task 7: Tag 提示词编辑 BottomSheet 组件

**Files:**
- Create: `lib/widgets/tag_editor_sheet.dart`

- [ ] **Step 1: 创建提示词编辑组件**

创建 `lib/widgets/tag_editor_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/diary_storage_service.dart';

/// 匹配提示词编辑 BottomSheet
/// 添加/移除 tag 后弹出，让用户编辑匹配提示词
Future<void> showTagEditorSheet(
  BuildContext context, {
  required Tag tag,
  required bool isRemoval,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TagEditorContent(tag: tag, isRemoval: isRemoval),
  );
}

class _TagEditorContent extends StatefulWidget {
  final Tag tag;
  final bool isRemoval;

  const _TagEditorContent({required this.tag, required this.isRemoval});

  @override
  State<_TagEditorContent> createState() => _TagEditorContentState();
}

class _TagEditorContentState extends State<_TagEditorContent> {
  final _storageService = DiaryStorageService();
  late TextEditingController _promptController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.tag.matchPrompt);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updatedTag = Tag(
      id: widget.tag.id,
      name: widget.tag.name,
      matchPrompt: _promptController.text.trim(),
      color: widget.tag.color,
      createdAt: widget.tag.createdAt,
    );
    await _storageService.updateTag(updatedTag);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isRemoval ? '调整「${widget.tag.name}」匹配规则' : '编辑「${widget.tag.name}」匹配规则',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (widget.isRemoval)
            Text(
              '已移除该标签。你可以调整匹配提示词，避免后续日记被自动打上此标签。',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          else
            Text(
              '你可以编辑匹配提示词，帮助 AI 更准确地自动归类。也可以直接跳过。',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '匹配提示词',
              hintText: '描述什么样的日记内容属于该标签',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('跳过'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/tag_editor_sheet.dart
git commit -m "feat: 新增 Tag 提示词编辑 BottomSheet 组件"
```

---

## Task 8: Tag Chip Bar 组件

**Files:**
- Create: `lib/widgets/tag_chip_bar.dart`

- [ ] **Step 1: 创建 Tag Chip 过滤条组件**

创建 `lib/widgets/tag_chip_bar.dart`：

```dart
import 'package:flutter/material.dart';

import '../models/tag.dart';

enum GroupMode { date, tag }

class TagChipBar extends StatelessWidget {
  final List<Tag> tags;
  final String? selectedTagId;
  final GroupMode groupMode;
  final ValueChanged<String?> onTagSelected;
  final ValueChanged<GroupMode> onGroupModeChanged;

  const TagChipBar({
    super.key,
    required this.tags,
    this.selectedTagId,
    required this.groupMode,
    required this.onTagSelected,
    required this.onGroupModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.start,
            children: [
              _buildChip(
                label: '全部',
                selected: selectedTagId == null,
                onTap: () => onTagSelected(null),
              ),
              ...tags.map((tag) => _buildChip(
                    label: tag.name,
                    selected: selectedTagId == tag.id,
                    onTap: () => onTagSelected(
                        selectedTagId == tag.id ? null : tag.id),
                  )),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildGroupToggle(context),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        label: Text(label, style: TextStyle(fontSize: 12)),
        backgroundColor: selected ? null : Colors.grey[200],
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildGroupToggle(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleBtn(
            icon: Icons.calendar_today,
            selected: groupMode == GroupMode.date,
            onTap: () => onGroupModeChanged(GroupMode.date),
          ),
          _buildToggleBtn(
            icon: Icons.label,
            selected: groupMode == GroupMode.tag,
            onTap: () => onGroupModeChanged(GroupMode.tag),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: selected ? null : Colors.grey),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/tag_chip_bar.dart
git commit -m "feat: 新增 Tag Chip 过滤条组件，支持分组切换"
```

---

## Task 9: 日记详情页 — Tag 展示和管理

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

- [ ] **Step 1: 添加 import 和状态变量**

在文件顶部添加 import：

```dart
import '../models/tag.dart';
import '../widgets/tag_selector_sheet.dart';
import '../widgets/tag_editor_sheet.dart';
```

在 `_DiaryDetailPageState` 中添加状态变量（在 `String _retryError = '';` 之后）：

```dart
  List<Tag> _tags = [];
```

- [ ] **Step 2: 在 _loadContent 中加载 tag 数据**

在 `_loadContent` 方法的 `if (mounted) { setState(() {` 块末尾（`_loading = false` 之后），添加 tag 加载逻辑：

在 `_loadContent` 的两个 `setState` 调用中，在设置 `_loading = false` 之前，添加 tag 加载。

实际上需要在 `_loadContent` 完成后单独加载 tag。在 `_loadContent` 方法末尾（最后一个 `setState` 的 `}` 之后），添加：

```dart
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _storageService.getFullTagsForDiary(widget.entry.id);
    if (mounted) {
      setState(() => _tags = tags);
    }
  }
```

- [ ] **Step 3: 修改 _retry 方法，成功后追加自动打 tag**

在 `_retry` 方法中，在 `// 更新数据库标题` 之后、`// 重新加载页面` 之前，添加自动打 tag：

```dart
      // 自动打 tag
      try {
        final allTags = await _storageService.getAllTags();
        final tagsWithPrompt = allTags.where((t) => t.matchPrompt.isNotEmpty).toList();
        if (tagsWithPrompt.isNotEmpty) {
          final tagInfos = tagsWithPrompt
              .map((t) => TagInfo(id: t.id, name: t.name, matchPrompt: t.matchPrompt))
              .toList();
          final matchedTagIds = await _llmService.matchTags(llmResult.content, tagInfos);
          if (matchedTagIds.isNotEmpty) {
            await _storageService.autoTagDiary(widget.entry.id, matchedTagIds);
          }
        }
      } catch (e) {
        debugPrint('[重试] 自动归类失败（不阻塞）: $e');
      }
```

需要在顶部添加 import：`import '../services/llm_service.dart' show TagInfo;`（注意 `LlmService` 已有 import，需要确保 `TagInfo` 可访问）。

- [ ] **Step 4: 在 build 方法中添加 tag 展示区域**

在 `build` 方法的 `SingleChildScrollView` 的 `Column.children` 中，在日期文本（`'${widget.entry.formattedDate} ...'`）之后、音频播放器之前，插入 tag 展示区域：

```dart
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ..._tags.map((tag) => Chip(
                              label: Text(tag.name, style: const TextStyle(fontSize: 12)),
                              onDeleted: () async {
                                await _storageService.removeDiaryTag(widget.entry.id, tag.id);
                                final updatedTag = await _storageService.getTagById(tag.id);
                                if (mounted) {
                                  await showTagEditorSheet(context, tag: updatedTag, isRemoval: true);
                                  _loadTags();
                                }
                              },
                              deleteIconColor: Colors.grey,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            )),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: const Text('标签', style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            final selectedIds = await showTagSelectorSheet(
                              context,
                              selectedTagIds: _tags.map((t) => t.id).toList(),
                            );
                            if (selectedIds != null && mounted) {
                              final currentIds = _tags.map((t) => t.id).toSet();
                              final newIds = selectedIds.toSet();
                              // 添加新选中的
                              for (final id in newIds.difference(currentIds)) {
                                await _storageService.addDiaryTag(widget.entry.id, id);
                                final tag = await _storageService.getTagById(id);
                                if (mounted) {
                                  await showTagEditorSheet(context, tag: tag, isRemoval: false);
                                }
                              }
                              // 移除取消选中的
                              for (final id in currentIds.difference(newIds)) {
                                await _storageService.removeDiaryTag(widget.entry.id, id);
                                final tag = await _storageService.getTagById(id);
                                if (mounted) {
                                  await showTagEditorSheet(context, tag: tag, isRemoval: true);
                                }
                              }
                              _loadTags();
                            }
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
```

- [ ] **Step 5: Commit**

```bash
git add lib/pages/diary_detail_page.dart
git commit -m "feat: 详情页展示 tag，支持手动添加/删除和提示词编辑"
```

---

## Task 10: Tag 管理页面

**Files:**
- Create: `lib/pages/tag_management_page.dart`

- [ ] **Step 1: 创建 Tag 管理页面**

创建 `lib/pages/tag_management_page.dart`：

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/tag.dart';
import '../models/utterance.dart';
import '../services/diary_storage_service.dart';
import '../services/llm_service.dart';

class TagManagementPage extends StatefulWidget {
  const TagManagementPage({super.key});

  @override
  State<TagManagementPage> createState() => _TagManagementPageState();
}

class _TagManagementPageState extends State<TagManagementPage> {
  final _storageService = DiaryStorageService();
  final _llmService = LlmService();
  final _uuid = const Uuid();
  List<Tag> _tags = [];
  Map<String, int> _diaryCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _storageService.getAllTags();
    final counts = <String, int>{};
    for (final tag in tags) {
      counts[tag.id] = await _storageService.getDiaryCountForTag(tag.id);
    }
    if (mounted) {
      setState(() {
        _tags = tags;
        _diaryCounts = counts;
        _loading = false;
      });
    }
  }

  Future<void> _createTag() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('新建标签'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '标签名称'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('创建')),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    // 第一步：创建 tag
    final tag = Tag(
      id: _uuid.v4(),
      name: name,
      matchPrompt: '',
      createdAt: DateTime.now(),
    );
    await _storageService.createTag(tag);

    // 第二步：LLM 推荐日记
    if (mounted) {
      final confirmedDiaryIds = await _showRecommendations(tag);
      if (confirmedDiaryIds != null && confirmedDiaryIds.isNotEmpty) {
        // 第三步：基于确认的日记生成提示词
        try {
          final entries = await _storageService.getAllEntries();
          final confirmedEntries = entries.where((e) => confirmedDiaryIds.contains(e.id)).toList();
          final diarySummaries = <DiarySummaryInfo>[];
          for (final entry in confirmedEntries) {
            String summary = '';
            try {
              if (await _storageService.hasLlmResult(entry.folderPath)) {
                final llmData = await _storageService.readLlmResult(entry.folderPath);
                summary = llmData.summary.length > 200 ? llmData.summary.substring(0, 200) : llmData.summary;
              }
            } catch (_) {}
            diarySummaries.add(DiarySummaryInfo(id: entry.id, title: entry.title, summary: summary));
          }
          final prompt = await _llmService.generateMatchPrompt(name, diarySummaries);
          // 更新 tag 的 matchPrompt
          final updatedTag = Tag(
            id: tag.id,
            name: tag.name,
            matchPrompt: prompt,
            color: tag.color,
            createdAt: tag.createdAt,
          );
          await _storageService.updateTag(updatedTag);

          // 给确认的日记添加 tag
          for (final diaryId in confirmedDiaryIds) {
            await _storageService.addDiaryTag(diaryId, tag.id, source: 'manual');
          }
        } catch (e) {
          debugPrint('生成提示词失败: $e');
        }
      }
      _loadTags();
    }
  }

  Future<List<String>?> _showRecommendations(Tag tag) async {
    // 获取所有日记摘要
    final entries = await _storageService.getAllEntries();
    final diarySummaries = <DiarySummaryInfo>[];
    for (final entry in entries) {
      String summary = '';
      try {
        if (await _storageService.hasLlmResult(entry.folderPath)) {
          final llmData = await _storageService.readLlmResult(entry.folderPath);
          summary = llmData.summary.length > 200 ? llmData.summary.substring(0, 200) : llmData.summary;
        }
      } catch (_) {}
      diarySummaries.add(DiarySummaryInfo(id: entry.id, title: entry.title, summary: summary));
    }

    // LLM 推荐
    final recommendations = await _llmService.recommendDiariesForTag(tag.name, diarySummaries);
    if (recommendations.isEmpty) return [];

    // 展示推荐列表让用户选择
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final selected = <String>{};
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('「${tag.name}」推荐日记'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: recommendations.length,
                  itemBuilder: (_, index) {
                    final rec = recommendations[index];
                    final entry = entries.firstWhere((e) => e.id == rec.diaryId);
                    return CheckboxListTile(
                      value: selected.contains(rec.diaryId),
                      title: Text(entry.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(rec.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            selected.add(rec.diaryId);
                          } else {
                            selected.remove(rec.diaryId);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, <String>[]),
                    child: const Text('跳过')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, selected.toList()),
                    child: const Text('确认')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editTag(Tag tag) async {
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: tag.matchPrompt);
        return AlertDialog(
          title: Text('编辑「${tag.name}」'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: TextEditingController(text: tag.name),
                decoration: const InputDecoration(labelText: '标签名称'),
                onChanged: (val) => tag = Tag(id: tag.id, name: val, matchPrompt: tag.matchPrompt, color: tag.color, createdAt: tag.createdAt),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '匹配提示词',
                  hintText: '描述什么样的日记内容属于该标签',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('保存')),
          ],
        );
      },
    );

    if (prompt != null) {
      await _storageService.updateTag(Tag(
        id: tag.id,
        name: tag.name,
        matchPrompt: prompt,
        color: tag.color,
        createdAt: tag.createdAt,
      ));
      _loadTags();
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${tag.name}」'),
        content: Text('删除后所有日记的该标签关联也会移除，确定删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.deleteTag(tag.id);
      _loadTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tags.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.label_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('还没有标签', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tags.length,
                  itemBuilder: (context, index) {
                    final tag = _tags[index];
                    final count = _diaryCounts[tag.id] ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: tag.color != null
                              ? _parseColor(tag.color!)
                              : Theme.of(context).colorScheme.primaryContainer,
                          child: Text(tag.name[0], style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(tag.name),
                        subtitle: Text('$count 篇日记${tag.matchPrompt.isNotEmpty ? ' · 已设置匹配规则' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        trailing: PopupMenuButton(
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: Text('编辑')),
                            const PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                          onSelected: (val) {
                            if (val == 'edit') _editTag(tag);
                            if (val == 'delete') _deleteTag(tag);
                          },
                        ),
                        onTap: () => _editTag(tag),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTag,
        child: const Icon(Icons.add),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.blue;
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/pages/tag_management_page.dart
git commit -m "feat: 新增 Tag 管理页面，支持 LLM 推荐和提示词生成"
```

---

## Task 11: 日记列表页改造

**Files:**
- Modify: `lib/pages/diary_list_page.dart`

- [ ] **Step 1: 完整替换 diary_list_page.dart**

将 `lib/pages/diary_list_page.dart` 完整替换为：

```dart
import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../models/tag.dart';
import '../services/diary_storage_service.dart';
import '../widgets/tag_chip_bar.dart';
import 'diary_detail_page.dart';
import 'recording_page.dart';
import 'tag_management_page.dart';

class DiaryListPage extends StatefulWidget {
  const DiaryListPage({super.key});

  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  final _storageService = DiaryStorageService();
  List<DiaryEntry> _entries = [];
  List<Tag> _tags = [];
  Map<String, List<Tag>> _entryTags = {};
  bool _loading = true;

  String? _selectedTagId;
  GroupMode _groupMode = GroupMode.date;
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final entries = await _storageService.getAllEntries();
    final tags = await _storageService.getAllTags();
    final entryTags = <String, List<Tag>>{};
    for (final entry in entries) {
      entryTags[entry.id] = await _storageService.getFullTagsForDiary(entry.id);
    }
    if (mounted) {
      setState(() {
        _entries = entries;
        _tags = tags;
        _entryTags = entryTags;
        _loading = false;
      });
    }
  }

  List<DiaryEntry> get _filteredEntries {
    var result = _entries;

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((e) {
        if (e.title.toLowerCase().contains(q)) return true;
        if ((_entryTags[e.id] ?? []).any((t) => t.name.toLowerCase().contains(q))) return true;
        return false;
      }).toList();
    }

    // Tag 过滤
    if (_selectedTagId != null) {
      result = result.where((e) {
        return (_entryTags[e.id] ?? []).any((t) => t.id == _selectedTagId);
      }).toList();
    }

    return result;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索日记...',
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Text('我的日记'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.label),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TagManagementPage()),
              ).then((_) => _loadData());
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: TagChipBar(
                          tags: _tags,
                          selectedTagId: _selectedTagId,
                          groupMode: _groupMode,
                          onTagSelected: (id) => setState(() => _selectedTagId = id),
                          onGroupModeChanged: (mode) => setState(() => _groupMode = mode),
                        ),
                      ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('没有匹配的日记'))
                          : _groupMode == GroupMode.date
                              ? _buildDateGroups(filtered)
                              : _buildTagGroups(filtered),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RecordingPage()),
          );
        },
        child: const Icon(Icons.mic),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.book_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('还没有日记，点击 + 开始录音',
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildDateGroups(List<DiaryEntry> entries) {
    final groups = <String, List<DiaryEntry>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in entries) {
      final date = DateTime(
        entry.createdAt.year,
        entry.createdAt.month,
        entry.createdAt.day,
      );
      final diff = today.difference(date).inDays;
      final label = _getDateLabel(entry.createdAt, diff);
      groups.putIfAbsent(label, () => []).add(entry);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: groups.entries.expand((group) => [
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              group.key,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600]),
            ),
          ),
          ...group.value.map((entry) => _buildEntryCard(entry)),
        ]).toList(),
      ),
    );
  }

  String _getDateLabel(DateTime date, int daysDiff) {
    final monthDay = '${date.month}月${date.day}日';
    if (daysDiff == 0) return '今天（$monthDay）';
    if (daysDiff == 1) return '昨天（$monthDay）';
    if (daysDiff < 7) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '${weekdays[date.weekday - 1]}（$monthDay）';
    }
    if (daysDiff < 14) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '上周${weekdays[date.weekday - 1]}（$monthDay）';
    }
    return '$monthDay';
  }

  Widget _buildTagGroups(List<DiaryEntry> entries) {
    final tagGroups = <Tag, List<DiaryEntry>>{};
    final taggedIds = <String>{};

    for (final tag in _tags) {
      final tagged = entries.where((e) {
        return (_entryTags[e.id] ?? []).any((t) => t.id == tag.id);
      }).toList();
      if (tagged.isNotEmpty) {
        tagGroups[tag] = tagged;
        taggedIds.addAll(tagged.map((e) => e.id));
      }
    }

    // 未分类
    final untagged = entries.where((e) => !taggedIds.contains(e.id)).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...tagGroups.entries.expand((group) => [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                '${group.key.name}（${group.value.length}）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600]),
              ),
            ),
            ...group.value.map((entry) => _buildEntryCard(entry)),
          ]),
          if (untagged.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                '未分类（${untagged.length}）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600]),
              ),
            ),
            ...untagged.map((entry) => _buildEntryCard(entry)),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryCard(DiaryEntry entry) {
    final tags = _entryTags[entry.id] ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: (tag.color != null ? _parseColor(tag.color!) : Theme.of(context).colorScheme.primary).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tag.name, style: TextStyle(fontSize: 10, color: tag.color != null ? _parseColor(tag.color!) : Theme.of(context).colorScheme.primary)),
                  )).toList(),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${entry.formattedDate}  ${entry.durationDisplay}'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DiaryDetailPage(entry: entry)),
          ).then((_) => _loadData());
        },
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.blue;
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/pages/diary_list_page.dart
git commit -m "feat: 日记列表页支持搜索、tag 过滤、日期/标签分组"
```

---

## Task 12: 编译验证

- [ ] **Step 1: 运行 build_runner 确保生成代码是最新的**

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 2: 运行 flutter analyze**

Run: `flutter analyze`

修复所有报错和警告。

- [ ] **Step 3: 运行 flutter build apk --release 验证完整编译**

Run: `flutter build apk --release`

- [ ] **Step 4: 最终 Commit（如有修复）**

```bash
git add -A
git commit -m "fix: 修复编译问题"
```

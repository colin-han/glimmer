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
  final String source;
  final DateTime createdAt;

  const DiaryTagRelation({
    required this.diaryId,
    required this.tagId,
    required this.source,
    required this.createdAt,
  });
}

// --- 容错解析工具 ---
// 单个字段缺失或类型不符时降级为默认值，避免一条坏数据（旧版本字段缺失、半残 JSON、
// LLM 写入 null 等）导致整篇日记正文/识别结果不可读。
String _asString(dynamic v) =>
    v is String ? v : (v == null ? '' : v.toString());

int _asInt(dynamic v, [int def = 0]) =>
    v is int ? v : (v is num ? v.toInt() : def);

List<Utterance> _asUtteranceList(dynamic v) {
  if (v is! List) return const [];
  final result = <Utterance>[];
  for (final u in v) {
    if (u is Map<String, dynamic>) {
      try {
        result.add(Utterance.fromJson(u));
      } catch (_) {
        // 跳过无法解析的单条 utterance，保证其余仍可用
      }
    }
  }
  return result;
}

class Utterance {
  final String text;
  final int startTime;
  final int endTime;

  const Utterance({
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  factory Utterance.fromJson(Map<String, dynamic> json) {
    return Utterance(
      text: _asString(json['text']),
      startTime: _asInt(json['startTime']),
      endTime: _asInt(json['endTime']),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'startTime': startTime,
        'endTime': endTime,
      };
}

class TranscriptData {
  final int version;
  final List<Utterance> utterances;

  const TranscriptData({required this.version, required this.utterances});

  String get fullText => utterances.map((u) => u.text).join();

  factory TranscriptData.fromJson(Map<String, dynamic> json) {
    return TranscriptData(
      version: _asInt(json['version'], 1),
      utterances: _asUtteranceList(json['utterances']),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'utterances': utterances.map((u) => u.toJson()).toList(),
      };
}

class SummaryUtteranceData {
  final int version;
  final List<Utterance> utterances;

  const SummaryUtteranceData({required this.version, required this.utterances});

  factory SummaryUtteranceData.fromJson(Map<String, dynamic> json) {
    return SummaryUtteranceData(
      version: _asInt(json['version'], 1),
      utterances: _asUtteranceList(json['utterances']),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'utterances': utterances.map((u) => u.toJson()).toList(),
      };
}

class LlmResultData {
  final int version;
  final String title;
  final String summary;
  final String outline;
  final List<Utterance> utterances;

  const LlmResultData({
    required this.version,
    required this.title,
    required this.summary,
    required this.outline,
    required this.utterances,
  });

  factory LlmResultData.fromJson(Map<String, dynamic> json) {
    return LlmResultData(
      version: _asInt(json['version'], 1),
      title: _asString(json['title']),
      summary: _asString(json['summary']),
      outline: _asString(json['outline']),
      utterances: _asUtteranceList(json['utterances']),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'title': title,
        'summary': summary,
        'outline': outline,
        'utterances': utterances.map((u) => u.toJson()).toList(),
      };
}

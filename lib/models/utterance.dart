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
      text: json['text'] as String,
      startTime: json['startTime'] as int,
      endTime: json['endTime'] as int,
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
      version: json['version'] as int,
      utterances: (json['utterances'] as List)
          .map((u) => Utterance.fromJson(u as Map<String, dynamic>))
          .toList(),
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
      version: json['version'] as int,
      utterances: (json['utterances'] as List)
          .map((u) => Utterance.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'utterances': utterances.map((u) => u.toJson()).toList(),
      };
}

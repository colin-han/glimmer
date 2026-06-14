import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/utterance.dart';

class TagInfo {
  final String id;
  final String name;
  final String matchPrompt;

  const TagInfo({
    required this.id,
    required this.name,
    required this.matchPrompt,
  });
}

class DiarySummaryInfo {
  final String id;
  final String title;
  final String summary;

  const DiarySummaryInfo({
    required this.id,
    required this.title,
    required this.summary,
  });
}

class TagDiaryRecommendation {
  final String diaryId;
  final String reason;

  const TagDiaryRecommendation({required this.diaryId, required this.reason});
}

/// LLM API 返回的 token 用量。
class LlmUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int? cachedTokens;
  final int? reasoningTokens;

  const LlmUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    this.cachedTokens,
    this.reasoningTokens,
  });
}

class LlmResult {
  final String title;
  final String summary;
  final String outline;
  final List<Utterance> utterances;
  final LlmUsage? usage;

  LlmResult({
    required this.title,
    required this.summary,
    required this.outline,
    required this.utterances,
    this.usage,
  });
}

class LlmService {
  final Dio _dio = Dio();

  Future<LlmResult> summarize(List<Utterance> utterances) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final utterancesJson = utterances
        .map(
          (u) => jsonEncode({
            'text': u.text,
            'startTime': u.startTime,
            'endTime': u.endTime,
          }),
        )
        .join('\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content':
                '你是一个日记助手。用户会给你一段语音识别的口语文本（带时间戳），请完成以下三项任务：\n'
                '\n'
                '1. **日记体提炼（summary）**：以第一人称「我」的视角，写一篇精炼版日记（Markdown 格式）：\n'
                '   - 保留原文中的情感、感受、思考\n'
                '   - 合并相似内容，省略无关紧要的细节\n'
                '   - 自然流畅，300-500字，不要分条列举\n'
                '\n'
                '2. **口语化播报（outline）**：生成一段完整的口语化播报文本：\n'
                '   - 提炼最重要的前5个主题或事件\n'
                '   - 如果主题超过5个，末尾补充「还有其他几条，就不一一念了」类的收尾\n'
                '   - 口语化、适合 TTS 朗读，不要使用条目列表格式\n'
                '   - 示例：「日记整理完成，今天讨论了很多事情：首先是工作上的项目进展；然后是关于周末旅行的计划；还提到了最近在读的一本书。此外还有一些其他内容，就不一一念了。」\n'
                '\n'
                '3. **标题（title）**：从内容中提炼简短标题，不超过20个字\n'
                '\n'
                '时间戳规则（仅用于 utterances）：\n'
                '- 每个片段在 utterances 中保留 startTime 和 endTime（毫秒）\n'
                '- 合并多个片段时，取第一个的 startTime 和最后一个的 endTime\n'
                '- 不要拆分任何片段的时间戳\n'
                '- summary、outline 中不得出现任何时间戳数字或时间标记（例如 (1070ms - 6030ms)）\n'
                '\n'
                '严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
                '{"title": "标题", "summary": "日记体提炼(Markdown)", '
                '"outline": "口语化播报文本", '
                '"utterances": [{"text": "整理后的片段文本", "startTime": 0, "endTime": 1000}]}',
          },
          {'role': 'user', 'content': utterancesJson},
        ],
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    final content = response.data['choices'][0]['message']['content'] as String;

    // 提取 usage 数据
    final usageJson = response.data['usage'] as Map<String, dynamic>?;
    LlmUsage? usage;
    if (usageJson != null) {
      usage = LlmUsage(
        promptTokens: usageJson['prompt_tokens'] as int? ?? 0,
        completionTokens: usageJson['completion_tokens'] as int? ?? 0,
        totalTokens: usageJson['total_tokens'] as int? ?? 0,
        cachedTokens:
            (usageJson['prompt_tokens_details']
                    as Map<String, dynamic>?)?['cached_tokens']
                as int?,
        reasoningTokens:
            (usageJson['completion_tokens_details']
                    as Map<String, dynamic>?)?['reasoning_tokens']
                as int?,
      );
    }

    final result = _parseResult(content);
    return LlmResult(
      title: result.title,
      summary: result.summary,
      outline: result.outline,
      utterances: result.utterances,
      usage: usage,
    );
  }

  Future<String> generateReply(String realtimeText) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content':
                '你是一个温暖的日记助手。用户刚录完一段语音，'
                '你会根据他说的话，生成一句简短的回应（不超过 20 个字）。'
                '语气亲切温暖，就像朋友在回应。不要加引号或其他格式符号，只输出纯文本。',
          },
          {'role': 'user', 'content': realtimeText},
        ],
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    return response.data['choices'][0]['message']['content'] as String;
  }

  Future<List<String>> matchTags(String content, List<TagInfo> tagInfos) async {
    if (tagInfos.isEmpty) return [];

    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final tagsJson = tagInfos
        .map(
          (t) => jsonEncode({
            'id': t.id,
            'name': t.name,
            'matchPrompt': t.matchPrompt,
          }),
        )
        .join('\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content':
                '你是一个日记分类助手。你会收到一篇日记正文和一组标签（每条包含 id、name、matchPrompt）。\n'
                '请根据每条标签的 matchPrompt 描述，判断该日记是否属于该标签。\n'
                '严格按以下 JSON 格式返回匹配的标签 ID 列表，不要包含任何其他内容：\n'
                '{"matchedTagIds": ["id1", "id2"]}\n'
                '如果没有匹配的标签，返回空列表：{"matchedTagIds": []}',
          },
          {'role': 'user', 'content': '日记正文：\n$content\n\n标签列表：\n$tagsJson'},
        ],
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
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

  Future<List<TagDiaryRecommendation>> recommendDiariesForTag(
    String tagName,
    List<DiarySummaryInfo> diaries,
  ) async {
    if (diaries.isEmpty) return [];

    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final diariesJson = diaries
        .map(
          (d) =>
              jsonEncode({'id': d.id, 'title': d.title, 'summary': d.summary}),
        )
        .join('\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content':
                '你是一个日记分类助手。用户正在创建一个名为「$tagName」的标签。\n'
                '请分析以下日记列表，推荐可能属于该标签的日记。\n'
                '严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
                '{"recommendations": [{"diaryId": "id", "reason": "推荐理由"}]}\n'
                '只推荐确实相关的日记，不要强行推荐。',
          },
          {'role': 'user', 'content': '标签名称：$tagName\n\n日记列表：\n$diariesJson'},
        ],
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
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
          .map(
            (r) => TagDiaryRecommendation(
              diaryId: r['diaryId'] as String,
              reason: r['reason'] as String,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> generateMatchPrompt(
    String tagName,
    List<DiarySummaryInfo> confirmedDiaries,
  ) async {
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
            'content':
                '你是一个日记分类助手。用户正在创建一个名为「$tagName」的标签。\n'
                '以下是用户确认属于该标签的日记内容。请根据这些日记的共同特征，生成一段简洁的匹配提示词。\n'
                '提示词用于后续自动判断新日记是否属于该标签。\n'
                '只输出提示词纯文本，不要加引号或其他格式，不超过100个字。',
          },
          {'role': 'user', 'content': diariesText},
        ],
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    return response.data['choices'][0]['message']['content'] as String;
  }

  LlmResult _parseResult(String content) {
    try {
      final cleaned = content
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      final utterancesList = json['utterances'] as List<dynamic>?;
      final utterances =
          utterancesList
              ?.map((u) => Utterance.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [];

      return LlmResult(
        title: json['title'] as String? ?? '未命名日记',
        summary: json['summary'] as String? ?? '',
        outline: json['outline'] as String? ?? '',
        utterances: utterances,
      );
    } catch (_) {
      return LlmResult(
        title: _extractTitle(content),
        summary: '',
        outline: '',
        utterances: [],
      );
    }
  }

  String _extractTitle(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && trimmed.startsWith('#')) {
        return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      }
    }
    return content.length > 20 ? '${content.substring(0, 20)}...' : content;
  }
}

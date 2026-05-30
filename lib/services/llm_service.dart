import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/utterance.dart';

class LlmResult {
  final String title;
  final String content;
  final String summary;
  final String outline;
  final List<Utterance> utterances;

  LlmResult({
    required this.title,
    required this.content,
    required this.summary,
    required this.outline,
    required this.utterances,
  });
}

class LlmService {
  final Dio _dio = Dio();

  Future<LlmResult> summarize(List<Utterance> utterances) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final utterancesJson = utterances
        .map((u) =>
            '{"text": "${u.text}", "startTime": ${u.startTime}, "endTime": ${u.endTime}}')
        .join('\n');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记助手。用户会给你一段语音识别的口语文本（带时间戳），请完成以下四项任务：\n'
                '\n'
                '1. **润色正文（content）**：按以下规则整理为 Markdown 格式日记正文：\n'
                '   - 最大程度保留原文的句子结构和用词，不添加、不删除实质内容\n'
                '   - 仅删除无意义的口语填充词（嗯、啊、那个、就是说、然后呢等）\n'
                '   - 消除重复、结巴、停顿导致的不通顺\n'
                '   - 按语义自然分段（话题转换、时间线变化处分段）\n'
                '   - 适当将口语化词汇替换为书面表达（如觉得→认为、挺→很），保持自然\n'
                '\n'
                '2. **日记体提炼（summary）**：以第一人称「我」的视角，写一篇精炼版日记（Markdown 格式）：\n'
                '   - 保留原文中的情感、感受、思考\n'
                '   - 合并相似内容，省略无关紧要的细节\n'
                '   - 自然流畅，300-500字，不要分条列举\n'
                '\n'
                '3. **口语化播报（outline）**：生成一段完整的口语化播报文本：\n'
                '   - 提炼最重要的前5个主题或事件\n'
                '   - 如果主题超过5个，末尾补充「还有其他几条，就不一一念了」类的收尾\n'
                '   - 口语化、适合 TTS 朗读，不要使用条目列表格式\n'
                '   - 示例：「日记整理完成，今天讨论了很多事情：首先是工作上的项目进展；然后是关于周末旅行的计划；还提到了最近在读的一本书。此外还有一些其他内容，就不一一念了。」\n'
                '\n'
                '4. **标题（title）**：从内容中提炼简短标题，不超过20个字\n'
                '\n'
                '时间戳规则：\n'
                '- 每个片段都有 startTime 和 endTime（毫秒），润色正文时必须保留\n'
                '- 合并多个片段时，取第一个的 startTime 和最后一个的 endTime\n'
                '- 不要拆分任何片段的时间戳\n'
                '\n'
                '严格按以下 JSON 格式返回，不要包含任何其他内容：\n'
                '{"title": "标题", "content": "润色正文(Markdown)", "summary": "日记体提炼(Markdown)", '
                '"outline": "口语化播报文本", '
                '"utterances": [{"text": "润色后文本", "startTime": 0, "endTime": 1000}]}',
          },
          {
            'role': 'user',
            'content': utterancesJson,
          },
        ],
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      }),
    );

    final content =
        response.data['choices'][0]['message']['content'] as String;
    return _parseResult(content);
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
            'content': '你是一个温暖的日记助手。用户刚录完一段语音，'
                '你会根据他说的话，生成一句简短的回应（不超过 20 个字）。'
                '语气亲切温暖，就像朋友在回应。不要加引号或其他格式符号，只输出纯文本。',
          },
          {
            'role': 'user',
            'content': realtimeText,
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


  LlmResult _parseResult(String content) {
    try {
      final cleaned = content
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();
      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      final utterancesList = json['utterances'] as List<dynamic>?;
      final utterances = utterancesList
              ?.map((u) => Utterance.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [];

      return LlmResult(
        title: json['title'] as String? ?? '未命名日记',
        content: json['content'] as String? ?? content,
        summary: json['summary'] as String? ?? '',
        outline: json['outline'] as String? ?? '',
        utterances: utterances,
      );
    } catch (_) {
      return LlmResult(
        title: _extractTitle(content),
        content: content,
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
    return content.length > 20
        ? '${content.substring(0, 20)}...'
        : content;
  }
}

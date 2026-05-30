import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LlmResult {
  final String title;
  final String content;
  final String oneLineSummary;

  LlmResult({
    required this.title,
    required this.content,
    required this.oneLineSummary,
  });
}

class LlmService {
  final Dio _dio = Dio();

  Future<LlmResult> summarize(String transcript) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记助手。用户会给你一段语音识别的口语文本，'
                '请按以下规则整理为日记正文（Markdown 格式）：\n'
                '1. 最大程度保留原文的句子结构和用词，不添加、不删除实质内容\n'
                '2. 仅删除无意义的口语填充词（嗯、啊、那个、就是说、然后呢等）\n'
                '3. 消除重复、结巴、停顿导致的不通顺\n'
                '4. 按语义自然分段（话题转换、时间线变化处分段）\n'
                '5. 适当将口语化词汇替换为书面表达（如觉得→认为、挺→很），保持自然\n'
                '同时从内容中提炼一个简短标题（不超过 20 个字），'
                '以及一句话总结（不超过 30 个字）。'
                '严格按以下 JSON 格式返回，不要包含任何其他内容：'
                '{"title": "标题", "content": "日记正文", "oneLineSummary": "一句话总结"}',
          },
          {
            'role': 'user',
            'content': transcript,
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

  Future<String> generateSummaryAnnouncement(String oneLineSummary) async {
    final endpointId = dotenv.get('VOLCENGINE_ARK_ENDPOINT_ID');
    final apiKey = dotenv.get('VOLCENGINE_ARK_API_KEY');

    final response = await _dio.post(
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      data: {
        'model': endpointId,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个日记助手。用户今天的日记已经整理完成，'
                '一句话总结是：「$oneLineSummary」\n'
                '请生成一句播报文本（不超过 30 个字），告知用户日记整理完成并包含这个总结。'
                '语气沉稳专业。不要加引号或其他格式符号，只输出纯文本。',
          },
          {
            'role': 'user',
            'content': '请生成播报文本',
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
      return LlmResult(
        title: json['title'] as String? ?? '未命名日记',
        content: json['content'] as String? ?? content,
        oneLineSummary: json['oneLineSummary'] as String? ?? '',
      );
    } catch (_) {
      return LlmResult(
        title: _extractTitle(content),
        content: content,
        oneLineSummary: '',
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

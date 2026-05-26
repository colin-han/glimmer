import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LlmResult {
  final String title;
  final String content;

  LlmResult({required this.title, required this.content});
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
                '请将其整理为通顺的日记正文（使用 Markdown 格式）。'
                '同时生成一个简短的标题（不超过 20 个字）。'
                '请严格按以下 JSON 格式返回，不要包含任何其他内容：'
                '{"title": "标题", "content": "日记正文"}',
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
      );
    } catch (_) {
      return LlmResult(
        title: _extractTitle(content),
        content: content,
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

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AsrService {
  final Dio _dio = Dio();

  Future<String> transcribe(String audioFilePath) async {
    final audioBytes = await File(audioFilePath).readAsBytes();
    final audioBase64 = base64Encode(audioBytes);
    final appid = dotenv.get('VOLCENGINE_ACCESS_KEY');

    final submitResp = await _dio.post(
      'https://openspeech.bytedance.com/api/v1/auc/submit',
      data: {
        'header': {
          'appid': appid,
          'cluster': 'volcengine_streaming_common',
        },
        'setting': {
          'language': 'zh',
          'format': 'm4a',
        },
        'audio': {
          'format': 'm4a',
          'codec': 'raw',
          'data': audioBase64,
        },
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
      }),
    );

    final taskId = submitResp.data['payload']?['task_id'];
    if (taskId == null) {
      throw Exception('ASR 任务提交失败: ${submitResp.data}');
    }

    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 2));

      final queryResp = await _dio.post(
        'https://openspeech.bytedance.com/api/v1/auc/query',
        data: {
          'header': {'appid': appid},
          'payload': {'task_id': taskId},
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
        }),
      );

      final payload = queryResp.data['payload'];
      final status = payload?['status'];

      if (status == 'completed') {
        final results = payload?['result'] as List?;
        if (results != null && results.isNotEmpty) {
          return results.map((r) => r['text'] as String? ?? '').join();
        }
        throw Exception('ASR 结果为空');
      } else if (status == 'failed') {
        throw Exception('ASR 识别失败: ${payload?['message']}');
      }
    }

    throw Exception('ASR 识别超时');
  }
}

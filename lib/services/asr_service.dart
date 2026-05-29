import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

class AsrService {
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  Future<String> transcribe(String audioFilePath) async {
    final appid = dotenv.get('VOLCENGINE_SPEECH_APPID');
    final token = dotenv.get('VOLCENGINE_SPEECH_TOKEN');

    final audioBytes = await File(audioFilePath).readAsBytes();
    final audioBase64 = base64Encode(audioBytes);

    final requestId = _uuid.v4();

    final response = await _dio.post(
      'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash',
      data: {
        'user': {'uid': appid},
        'audio': {
          'data': audioBase64,
          'format': 'wav',
        },
        'request': {
          'model_name': 'bigmodel',
        },
      },
      options: Options(headers: {
        'X-Api-App-Key': appid,
        'X-Api-Access-Key': token,
        'X-Api-Resource-Id': 'volc.bigasr.auc_turbo',
        'X-Api-Request-Id': requestId,
        'X-Api-Sequence': '-1',
      }),
    );

    final statusCode = response.headers.value('X-Api-Status-Code');
    if (statusCode != '20000000') {
      final message = response.headers.value('X-Api-Message') ?? '未知错误';
      throw Exception('ASR 识别失败 ($statusCode): $message');
    }

    final text = response.data['result']?['text'] as String?;
    if (text == null || text.isEmpty) {
      throw Exception('ASR 识别结果为空');
    }
    return text;
  }
}

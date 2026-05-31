import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

import '../models/utterance.dart';

class AsrResult {
  final String text;
  final List<Utterance> utterances;

  const AsrResult({required this.text, required this.utterances});
}

class AsrService {
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  Future<AsrResult> transcribe(String audioFilePath) async {
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
          'show_utterances': true,
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

    final result = response.data['result'] as Map<String, dynamic>?;
    if (result == null) {
      throw Exception('ASR 识别结果为空');
    }

    final text = result['text'] as String? ?? '';
    if (text.isEmpty) {
      throw Exception('ASR 识别结果为空');
    }

    final utterancesList = result['utterances'] as List<dynamic>?;
    if (utterancesList == null || utterancesList.isEmpty) {
      throw Exception('ASR 未返回 utterances 数据，需要切换到录音文件识别 API');
    }

    final utterances = utterancesList
        .map((u) => Utterance(
              text: u['text'] as String,
              startTime: u['start_time'] as int,
              endTime: u['end_time'] as int,
            ))
        .toList();

    return AsrResult(text: text, utterances: utterances);
  }

  /// 通过预签名 URL 识别音频（OGG/Opus 格式）。
  Future<AsrResult> transcribeFromUrl(String audioUrl) async {
    final appid = dotenv.get('VOLCENGINE_SPEECH_APPID');
    final token = dotenv.get('VOLCENGINE_SPEECH_TOKEN');

    final requestId = _uuid.v4();

    final response = await _dio.post(
      'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash',
      data: {
        'user': {'uid': appid},
        'audio': {
          'url': audioUrl,
          'format': 'ogg_opus',
        },
        'request': {
          'model_name': 'bigmodel',
          'show_utterances': true,
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

    final result = response.data['result'] as Map<String, dynamic>?;
    if (result == null) {
      throw Exception('ASR 识别结果为空');
    }

    final text = result['text'] as String? ?? '';
    if (text.isEmpty) {
      throw Exception('ASR 识别结果为空');
    }

    final utterancesList = result['utterances'] as List<dynamic>?;
    if (utterancesList == null || utterancesList.isEmpty) {
      throw Exception('ASR 未返回 utterances 数据');
    }

    final utterances = utterancesList
        .map((u) => Utterance(
              text: u['text'] as String,
              startTime: u['start_time'] as int,
              endTime: u['end_time'] as int,
            ))
        .toList();

    return AsrResult(text: text, utterances: utterances);
  }
}

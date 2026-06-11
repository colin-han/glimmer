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

  /// 提交异步 ASR 识别任务，返回 asrTaskId（即 requestId）
  Future<String> submitAsync(String audioUrl) async {
    final apiKey = dotenv.get('VOLCENGINE_SPEECH_API_KEY');
    final requestId = _uuid.v4();

    await _dio.post(
      'https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit',
      data: {
        'user': {'uid': 'voice_diary'},
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
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'X-Api-Resource-Id': 'volc.seedasr.auc',
        'X-Api-Request-Id': requestId,
        'X-Api-Sequence': '-1',
      }),
    );

    return requestId;
  }

  /// 查询异步 ASR 任务状态。返回 null 表示仍在处理中，返回 AsrResult 表示完成。
  Future<AsrResult?> queryAsync(String requestId) async {
    final apiKey = dotenv.get('VOLCENGINE_SPEECH_API_KEY');

    final response = await _dio.post(
      'https://openspeech.bytedance.com/api/v3/auc/bigmodel/query',
      data: {},
      options: Options(headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'X-Api-Resource-Id': 'volc.seedasr.auc',
        'X-Api-Request-Id': requestId,
      }),
    );

    final statusCode = response.headers.value('X-Api-Status-Code');
    if (statusCode == '20000001' || statusCode == '20000002') {
      // 排队中或处理中
      return null;
    }
    if (statusCode == '20000003') {
      // 静音音频
      throw Exception('ASR 识别结果为空（静音音频）');
    }
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

  /// 轮询异步 ASR 直到完成或超时
  Future<AsrResult> pollAsyncResult(String requestId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = await queryAsync(requestId);
      if (result != null) return result;
      await Future.delayed(interval);
    }
    throw Exception('ASR 识别超时');
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

import '../exceptions.dart';
import '../models/utterance.dart';

class AsrResult {
  final String text;
  final List<Utterance> utterances;

  const AsrResult({required this.text, required this.utterances});
}

/// 空识别结果：ASR 返回无语音内容（静音/过短）时使用，调用方按"未识别到内容"处理。
const emptyAsrResult = AsrResult(text: '', utterances: []);

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

    _ensureSuccess(response);
    final result = response.data['result'] as Map<String, dynamic>?;
    final utterances = _parseUtterances(result);
    if (utterances.isEmpty) {
      debugPrint('[ASR] 识别结果为空');
      return emptyAsrResult;
    }
    final text = result?['text'] as String? ?? '';
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

    _ensureSuccess(response);
    final result = response.data['result'] as Map<String, dynamic>?;
    final utterances = _parseUtterances(result);
    if (utterances.isEmpty) {
      debugPrint('[ASR] 识别结果为空');
      return emptyAsrResult;
    }
    final text = result?['text'] as String? ?? '';
    return AsrResult(text: text, utterances: utterances);
  }

  /// 提交异步 ASR 识别任务，返回 asrTaskId（即 requestId）
  Future<String> submitAsync(String audioUrl) async {
    final apiKey = dotenv.get('VOLCENGINE_SPEECH_API_KEY');
    final requestId = _uuid.v4();

    debugPrint('[ASR] submitAsync: requestId=$requestId, url=${audioUrl.substring(0, audioUrl.indexOf("?"))}...');

    try {
      final response = await _dio.post(
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

      debugPrint('[ASR] submitAsync 成功: statusCode=${response.statusCode}, data=${response.data}');
      return requestId;
    } on DioException catch (e) {
      debugPrint('[ASR] submitAsync 失败: ${e.type}, status=${e.response?.statusCode}');
      debugPrint('[ASR] submitAsync 响应头: ${e.response?.headers.map}');
      debugPrint('[ASR] submitAsync 响应体: ${e.response?.data}');
      rethrow;
    }
  }

  /// 查询异步 ASR 任务状态。
  /// 返回 null 表示仍在处理中；返回 [emptyAsrResult] 表示已完成但无语音内容；
  /// 返回非空 AsrResult 表示识别成功。
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
      // 静音音频：识别无内容
      debugPrint('[ASR] 静音音频，识别结果为空');
      return emptyAsrResult;
    }
    if (statusCode != '20000000') {
      final message = response.headers.value('X-Api-Message') ?? '未知错误';
      throw AsrException(message, statusCode: statusCode);
    }

    final result = response.data['result'] as Map<String, dynamic>?;
    final utterances = _parseUtterances(result);
    if (utterances.isEmpty) {
      debugPrint('[ASR] 识别结果为空');
      return emptyAsrResult;
    }
    final text = result?['text'] as String? ?? '';
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
    throw const AsrTimeoutException();
  }

  /// 校验 ASR 响应状态码，非成功则抛异常。
  void _ensureSuccess(Response response) {
    final statusCode = response.headers.value('X-Api-Status-Code');
    if (statusCode != '20000000') {
      final message = response.headers.value('X-Api-Message') ?? '未知错误';
      throw AsrException(message, statusCode: statusCode);
    }
  }

  /// 从 ASR 响应 result 中解析 utterances 列表。无数据时返回空列表。
  /// 容错解析：跳过结构/类型异常的单条，避免一条坏数据连累整篇。
  List<Utterance> _parseUtterances(Map<String, dynamic>? result) {
    final utterancesList = result?['utterances'] as List<dynamic>?;
    if (utterancesList == null || utterancesList.isEmpty) return [];
    final parsed = <Utterance>[];
    for (final u in utterancesList) {
      if (u is! Map<String, dynamic>) continue;
      final text = u['text'];
      final startTime = u['start_time'];
      final endTime = u['end_time'];
      if (text is! String) continue;
      if (startTime is! num || endTime is! num) continue;
      parsed.add(Utterance(
        text: text,
        startTime: startTime.toInt(),
        endTime: endTime.toInt(),
      ));
    }
    return parsed;
  }
}

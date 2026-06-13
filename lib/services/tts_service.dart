import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../exceptions.dart';

enum VoiceType { femaleSweet, maleDeep }

class TtsService {
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  static const _voiceTypes = {
    VoiceType.femaleSweet: 'zh_female_xiaohe_uranus_bigtts',
    VoiceType.maleDeep: 'zh_male_m191_uranus_bigtts',
  };

  Future<void> speak(String text, VoiceType voiceType) async {
    final sw = Stopwatch()..start();
    debugPrint('[TTS] speak 开始: voice=$voiceType, text="$text"');

    final appid = dotenv.get('VOLCENGINE_SPEECH_APPID');
    final token = dotenv.get('VOLCENGINE_SPEECH_TOKEN');

    final response = await _dio.post(
      'https://openspeech.bytedance.com/api/v1/tts',
      data: {
        'app': {
          'appid': appid,
          'token': token,
          'cluster': 'volcano_tts',
        },
        'user': {'uid': appid},
        'audio': {
          'voice_type': _voiceTypes[voiceType],
          'encoding': 'mp3',
          'speed_ratio': 1.0,
        },
        'request': {
          'reqid': _uuid.v4(),
          'text': text,
          'text_type': 'plain',
          'operation': 'query',
        },
      },
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer;$token',
      }),
    );
    debugPrint('[TTS] HTTP 响应耗时: ${sw.elapsedMilliseconds}ms');

    final code = response.data['code'] as int?;
    if (code != 3000) {
      final message = response.data['message'] ?? 'TTS 合成失败';
      throw TtsException(message, code: code);
    }

    final audioBase64 = response.data['data'] as String;
    final audioBytes = base64Decode(audioBase64);

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/tts_${_uuid.v4()}.mp3');
    await tempFile.writeAsBytes(audioBytes);
    debugPrint('[TTS] 文件写入耗时: ${sw.elapsedMilliseconds}ms, 大小=${audioBytes.length} bytes');

    final player = AudioPlayer();
    try {
      await player.setFilePath(tempFile.path);
      debugPrint('[TTS] setFilePath 完成: ${sw.elapsedMilliseconds}ms');

      await player.play();
      debugPrint('[TTS] 播放开始: ${sw.elapsedMilliseconds}ms');

      await player.processingStateStream.firstWhere(
        (state) => state == ProcessingState.completed,
      );
      debugPrint('[TTS] 播放完成: ${sw.elapsedMilliseconds}ms');
    } finally {
      await player.dispose();
      await tempFile.delete();
    }
  }
}

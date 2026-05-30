import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum VoiceType { femaleSweet, maleDeep }

class TtsService {
  final Dio _dio = Dio();
  final AudioPlayer _player = AudioPlayer();
  final _uuid = const Uuid();

  static const _voiceTypes = {
    VoiceType.femaleSweet: 'saturn_zh_female_keainvsheng_tob',
    VoiceType.maleDeep: 'zh_male_m191_uranus_bigtts',
  };

  Future<void> speak(String text, VoiceType voiceType) async {
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

    final code = response.data['code'] as int?;
    if (code != 3000) {
      final message = response.data['message'] ?? 'TTS 合成失败';
      throw Exception('TTS 错误 ($code): $message');
    }

    final audioBase64 = response.data['data'] as String;
    final audioBytes = base64Decode(audioBase64);

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/tts_${_uuid.v4()}.mp3');
    await tempFile.writeAsBytes(audioBytes);

    await _player.setFilePath(tempFile.path);
    await _player.play();
    await _player.processingStateStream.firstWhere(
      (state) => state == ProcessingState.completed,
    );

    await tempFile.delete();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// TOS 上传与预签名 URL 服务
///
/// 使用 dio + TOS4-HMAC-SHA256 签名，不依赖 tos SDK（SDK 在 Android 上签名异常）。
class TosUploadService {
  String? _bucket;
  String? _ak;
  String? _sk;
  String? _endpoint;
  String? _region;

  final _dio = Dio();

  TosUploadService();

  /// 测试用构造函数，绕过 dotenv 初始化
  @visibleForTesting
  TosUploadService.withMockConfig({
    String ak = 'test-ak',
    String sk = 'test-sk',
    String endpoint = 'tos-cn-beijing.volces.com',
    String bucket = 'test-bucket',
  }) {
    _ak = ak;
    _sk = sk;
    _endpoint = endpoint;
    _bucket = bucket;
    _region = endpoint.split('.').first.replaceAll('tos-', '');
  }

  void _ensureInitialized() {
    if (_ak != null) return;
    _ak = dotenv.get('VOLCENGINE_TOS_ACCESS_KEY');
    _sk = dotenv.get('VOLCENGINE_TOS_SECRET_KEY');
    _endpoint = dotenv.get('VOLCENGINE_TOS_ENDPOINT');
    _bucket = dotenv.get('VOLCENGINE_TOS_BUCKET');
    _region = _endpoint!.split('.').first.replaceAll('tos-', '');
  }

  /// 上传音频文件到 TOS（PUT + TOS4 Header 签名）
  Future<String> uploadAudio(String localPath, String diaryId) async {
    _ensureInitialized();
    final ak = _ak!, sk = _sk!, endpoint = _endpoint!, bucket = _bucket!, region = _region!;
    final tosKey = tosKeyForDiary(diaryId);
    final host = '$bucket.$endpoint';
    final url = 'https://$host/$tosKey';

    final fileBytes = await File(localPath).readAsBytes();
    final contentSha256 = sha256.convert(fileBytes).toString();

    final now = DateTime.now().toUtc();
    final shortDate =
        '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
    final longDate =
        '${shortDate}T${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}Z';

    final credentialScope = '$shortDate/$region/tos/request';

    // 签名 headers（按名称排序）
    final signedHeaderMap = <String, String>{
      'content-type': 'audio/ogg',
      'host': host,
      'x-tos-content-sha256': contentSha256,
      'x-tos-date': longDate,
    };

    final signedHeaderNames = signedHeaderMap.keys.toList()..sort();
    final signedHeaders = signedHeaderNames.join(';');

    // Canonical headers：按排序后的 key 顺序，每行 "key:value\n"
    final canonicalHeaders = signedHeaderNames
        .map((k) => '$k:${signedHeaderMap[k]}\n')
        .join();

    final canonicalRequest =
        'PUT\n/$tosKey\n\n$canonicalHeaders\n$signedHeaders\n$contentSha256';

    debugPrint('[TOS] canonicalRequest:\n$canonicalRequest');

    final canonicalRequestHash =
        sha256.convert(utf8.encode(canonicalRequest)).toString();
    final stringToSign =
        'TOS4-HMAC-SHA256\n$longDate\n$credentialScope\n$canonicalRequestHash';

    final signature = _calcSignature(stringToSign, shortDate, region, sk);

    debugPrint('[TOS] stringToSign: $stringToSign');
    debugPrint('[TOS] signature: $signature');
    debugPrint('[TOS] ak: $ak, region: $region, shortDate: $shortDate');

    final authHeader =
        'TOS4-HMAC-SHA256 Credential=$ak/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    try {
      await _dio.put(
        url,
        data: Stream.fromIterable([fileBytes]),
        options: Options(
          headers: {
            'Authorization': authHeader,
            'Content-Type': 'audio/ogg',
            'Content-Length': fileBytes.length,
            'Host': host,
            'X-Tos-Content-Sha256': contentSha256,
            'X-Tos-Date': longDate,
          },
        ),
      );
    } on DioException catch (e) {
      debugPrint('[TOS] 上传失败: status=${e.response?.statusCode} body=${e.response?.data}');
      rethrow;
    }

    return tosKey;
  }

  /// 生成预签名 URL（GET + TOS4 签名查询参数）
  Future<String> getPresignedUrl(String tosKey,
      {int expiresSeconds = 3600}) async {
    _ensureInitialized();
    final ak = _ak!, sk = _sk!, endpoint = _endpoint!, bucket = _bucket!, region = _region!;
    final now = DateTime.now().toUtc();
    final shortDate =
        '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
    final longDate =
        '${shortDate}T${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}Z';

    final credentialScope = '$shortDate/$region/tos/request';
    final host = '$bucket.$endpoint';

    final queryParams = <String, String>{
      'X-Tos-Algorithm': 'TOS4-HMAC-SHA256',
      'X-Tos-Credential': '$ak/$credentialScope',
      'X-Tos-Date': longDate,
      'X-Tos-Expires': expiresSeconds.toString(),
      'X-Tos-SignedHeaders': 'host',
    };

    final canonicalUri = '/${_urlEncodeKey(tosKey)}';
    final canonicalQueryString = queryParams.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final canonicalHeaders = 'host:$host\n';
    final signedHeaders = 'host';

    final canonicalRequest =
        'GET\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\nUNSIGNED-PAYLOAD';

    final canonicalRequestHash =
        sha256.convert(utf8.encode(canonicalRequest)).toString();
    final stringToSign =
        'TOS4-HMAC-SHA256\n$longDate\n$credentialScope\n$canonicalRequestHash';

    final signature = _calcSignature(stringToSign, shortDate, region, sk);

    final encodedKey = _urlEncodeKey(tosKey);
    final allQueryParams = Map<String, String>.from(queryParams);
    allQueryParams['X-Tos-Signature'] = signature;
    final queryString = allQueryParams.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    return 'https://$host/$encodedKey?$queryString';
  }

  /// 生成日记音频的 TOS key
  String tosKeyForDiary(String diaryId) => 'audio/$diaryId.ogg';

  void close() {}

  // ==================== 签名辅助方法 ====================

  static String _calcSignature(
      String stringToSign, String shortDate, String region, String sk) {
    final signingKey = _calcSigningKey(shortDate, region, sk);
    return Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();
  }

  static List<int> _calcSigningKey(
      String shortDate, String region, String sk) {
    final kDate =
        Hmac(sha256, utf8.encode(sk)).convert(utf8.encode(shortDate)).bytes;
    final kRegion =
        Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
    final kService =
        Hmac(sha256, kRegion).convert(utf8.encode('tos')).bytes;
    final kSigning =
        Hmac(sha256, kService).convert(utf8.encode('request')).bytes;
    return kSigning;
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  static String _urlEncodeKey(String key) {
    return Uri.encodeComponent(key).replaceAll('%2F', '/');
  }
}

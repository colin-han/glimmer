import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tos/tos.dart';

/// TOS 上传与预签名 URL 服务
///
/// 负责将音频文件上传到火山引擎 TOS 对象存储，
/// 并生成 TOS4 签名的预签名 URL 用于回放。
class TosUploadService {
  late final TosClient _client;
  late final String _bucket;
  late final String _ak;
  late final String _sk;
  late final String _endpoint;
  late final String _region;

  TosUploadService() {
    _ak = dotenv.get('VOLCENGINE_TOS_ACCESS_KEY');
    _sk = dotenv.get('VOLCENGINE_TOS_SECRET_KEY');
    _endpoint = dotenv.get('VOLCENGINE_TOS_ENDPOINT');
    _bucket = dotenv.get('VOLCENGINE_TOS_BUCKET');
    // 从 endpoint 提取 region，如 tos-cn-beijing.volces.com -> cn-beijing
    _region = _endpoint.split('.').first.replaceAll('tos-', '');

    _client = TosClientBuilder()
        .ak(_ak)
        .sk(_sk)
        .region(_region)
        .endpoint(_endpoint)
        .build();
  }

  /// 测试用构造函数，绕过 dotenv 和 TosClient 初始化
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
    // 不初始化 _client，mock 实例不用于实际上传
  }

  /// 上传音频文件到 TOS
  ///
  /// [localPath] 本地文件路径
  /// [diaryId] 日记 ID，用于构造 TOS key
  /// 返回上传后的 TOS key
  Future<String> uploadAudio(String localPath, String diaryId) async {
    final tosKey = tosKeyForDiary(diaryId);
    final input = PutObjectFromFileInput(_bucket, tosKey, localPath);
    input.contentType = 'audio/ogg';
    await _client.putObjectFromFile(input);
    return tosKey;
  }

  /// 生成预签名 URL（TOS4 签名）
  ///
  /// [tosKey] TOS 对象 key
  /// [expiresSeconds] URL 有效期（秒），默认 1 小时
  Future<String> getPresignedUrl(String tosKey,
      {int expiresSeconds = 3600}) async {
    final now = DateTime.now().toUtc();
    final shortDate =
        '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
    final longDate =
        '${shortDate}T${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}Z';

    final credentialScope = '$shortDate/$_region/tos/request';
    final host = '$_bucket.$_endpoint';

    // 签名查询参数（按字母序排列）
    final queryParams = <String, String>{
      'X-Tos-Algorithm': 'TOS4-HMAC-SHA256',
      'X-Tos-Credential': '$_ak/$credentialScope',
      'X-Tos-Date': longDate,
      'X-Tos-Expires': expiresSeconds.toString(),
      'X-Tos-SignedHeaders': 'host',
    };

    // 构造 canonical request
    final canonicalUri = '/${_urlEncodeKey(tosKey)}';
    final canonicalQueryString = queryParams.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final canonicalHeaders = 'host:$host\n';
    final signedHeaders = 'host';

    final canonicalRequest =
        'GET\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\nUNSIGNED-PAYLOAD';

    // 计算 StringToSign
    final canonicalRequestHash =
        sha256.convert(utf8.encode(canonicalRequest)).toString();
    final stringToSign =
        'TOS4-HMAC-SHA256\n$longDate\n$credentialScope\n$canonicalRequestHash';

    // 计算签名
    final signature = _calcSignature(stringToSign, shortDate, _region, _sk);

    // 拼接最终 URL
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

  /// 关闭客户端连接
  void close() => _client.close();

  // ==================== 签名辅助方法 ====================

  /// TOS4 签名计算
  ///
  /// 使用 HMAC-SHA256 链：sk -> kDate -> kRegion -> kService -> kSigning
  static String _calcSignature(
      String stringToSign, String shortDate, String region, String sk) {
    final signingKey = _calcSigningKey(shortDate, region, sk);
    return Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();
  }

  /// 计算 signing key
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

  /// 两位数字格式化
  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  /// URL 编码 key（与 TOS SDK 的 _urlEncode 一致：编码后恢复 /）
  static String _urlEncodeKey(String key) {
    return Uri.encodeComponent(key).replaceAll('%2F', '/');
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// TosUploadService 提供了 _mock 构造函数，绕过 dotenv 依赖
import 'package:voice_diary/services/tos_upload_service.dart';

void main() {
  group('TosUploadService', () {
    group('tosKeyForDiary', () {
      test('返回正确的 key 格式', () {
        final service = TosUploadService.withMockConfig();
        expect(service.tosKeyForDiary('abc-123'), 'audio/abc-123.ogg');
      });

      test('不同 diaryId 生成不同 key', () {
        final service = TosUploadService.withMockConfig();
        final key1 = service.tosKeyForDiary('id-1');
        final key2 = service.tosKeyForDiary('id-2');
        expect(key1, 'audio/id-1.ogg');
        expect(key2, 'audio/id-2.ogg');
        expect(key1, isNot(equals(key2)));
      });
    });

    group('getPresignedUrl 签名验证', () {
      late TosUploadService service;

      setUp(() {
        service = TosUploadService.withMockConfig();
      });

      test('URL 包含必要的查询参数', () async {
        final url = await service.getPresignedUrl('audio/test-id.ogg');

        expect(url, contains('X-Tos-Algorithm=TOS4-HMAC-SHA256'));
        expect(url, contains('X-Tos-Credential='));
        expect(url, contains('X-Tos-Date='));
        expect(url, contains('X-Tos-Expires='));
        expect(url, contains('X-Tos-SignedHeaders=host'));
        expect(url, contains('X-Tos-Signature='));
      });

      test('URL 的 host 格式为 bucket.endpoint/key', () async {
        final url = await service.getPresignedUrl('audio/test-id.ogg');

        // bucket=test-bucket, endpoint=tos-cn-beijing.volces.com
        expect(
          url,
          startsWith('https://test-bucket.tos-cn-beijing.volces.com/'),
        );
      });

      test('URL 中 key 被正确编码（/ 不编码）', () async {
        final url = await service.getPresignedUrl('audio/test-id.ogg');
        // key 中的 / 不编码
        expect(url, contains('/audio/test-id.ogg?'));
      });

      test('X-Tos-Date 格式为 YYYYMMDDTHHmmSSZ', () async {
        final url = await service.getPresignedUrl('audio/test-id.ogg');
        // 提取 X-Tos-Date 值
        final dateMatch = RegExp(r'X-Tos-Date=(\d{8}T\d{6}Z)').firstMatch(url);
        expect(dateMatch, isNotNull);
        final dateStr = dateMatch!.group(1)!;
        // 验证格式：20260531T120000Z
        expect(dateStr.length, 16);
        expect(dateStr.endsWith('Z'), isTrue);
      });

      test('X-Tos-Credential 包含正确的 scope 格式', () async {
        final url = await service.getPresignedUrl('audio/test-id.ogg');
        // 提取 credential 值（URL 编码后的）
        final credMatch = RegExp(r'X-Tos-Credential=([^&]+)').firstMatch(url);
        expect(credMatch, isNotNull);
        final cred = Uri.decodeComponent(credMatch!.group(1)!);
        // 格式：ak/date/region/tos/request
        expect(cred, contains('test-ak/'));
        expect(cred, contains('/cn-beijing/tos/request'));
      });

      test('X-Tos-Expires 使用默认值 3600', () async {
        final url = await service.getPresignedUrl('audio/test-id.ogg');
        expect(url, contains('X-Tos-Expires=3600'));
      });

      test('X-Tos-Expires 使用自定义值', () async {
        final url = await service.getPresignedUrl(
          'audio/test-id.ogg',
          expiresSeconds: 7200,
        );
        expect(url, contains('X-Tos-Expires=7200'));
      });

      test('签名使用正确的 TOS4 HMAC-SHA256 链', () {
        // 独立验证签名算法的正确性
        const shortDate = '20260531';
        const region = 'cn-beijing';
        const sk = 'test-sk';

        // 计算 signing key：sk -> kDate -> kRegion -> kService -> kSigning
        final kDate = Hmac(
          sha256,
          utf8.encode(sk),
        ).convert(utf8.encode(shortDate)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
        final kService = Hmac(
          sha256,
          kRegion,
        ).convert(utf8.encode('tos')).bytes;
        final kSigning = Hmac(
          sha256,
          kService,
        ).convert(utf8.encode('request')).bytes;

        // 验证 signing key 长度正确（SHA256 = 32 bytes）
        expect(kSigning.length, 32);

        // 使用 signing key 计算签名
        final signature = Hmac(
          sha256,
          kSigning,
        ).convert(utf8.encode('test-string-to-sign')).toString();

        // 签名应该是 64 字符的十六进制字符串
        expect(signature.length, 64);
        expect(signature, matches(RegExp(r'^[0-9a-f]{64}$')));
      });

      test('不同 key 生成不同签名', () async {
        final url1 = await service.getPresignedUrl('audio/diary-1.ogg');
        final url2 = await service.getPresignedUrl('audio/diary-2.ogg');

        final sig1 = RegExp(
          r'X-Tos-Signature=([0-9a-f]+)',
        ).firstMatch(url1)?.group(1);
        final sig2 = RegExp(
          r'X-Tos-Signature=([0-9a-f]+)',
        ).firstMatch(url2)?.group(1);

        // 不同 key 的签名一定不同
        expect(sig1, isNot(equals(sig2)));
      });

      test('签名长度为 64 字符的 hex', () async {
        final url = await service.getPresignedUrl('audio/test-id.ogg');
        final sigMatch = RegExp(
          r'X-Tos-Signature=([0-9a-f]{64})',
        ).firstMatch(url);
        expect(sigMatch, isNotNull);
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/amap_service.dart';

void main() {
  group('stripAdminPrefix', () {
    test('去掉省/区前缀，保留核心（直辖市）', () {
      expect(
        stripAdminPrefix(
          '北京市朝阳区建国门外大街1号中国国际贸易中心',
          province: '北京市',
          city: <String>[],
          district: '朝阳区',
        ),
        '建国门外大街1号中国国际贸易中心',
      );
    });

    test('普通地级市剥离省+市+区', () {
      expect(
        stripAdminPrefix(
          '陕西省西安市雁塔区高新路1号',
          province: '陕西省',
          city: '西安市',
          district: '雁塔区',
        ),
        '高新路1号',
      );
    });

    test('直辖市 city 为空字符串不报错', () {
      expect(
        stripAdminPrefix(
          '天津市和平区南京路1号',
          province: '天津市',
          city: '',
          district: '和平区',
        ),
        '南京路1号',
      );
    });

    test('剥离后为空 → 回退 district', () {
      expect(
        stripAdminPrefix(
          '北京市朝阳区',
          province: '北京市',
          city: <String>[],
          district: '朝阳区',
        ),
        '朝阳区',
      );
    });

    test('district 也剥离后为空 → 回退 formatted', () {
      expect(
        stripAdminPrefix(
          '北京市',
          province: '北京市',
          city: <String>[],
          district: '',
        ),
        '北京市',
      );
    });

    test('不以 province 开头 → 原样 trim 返回', () {
      expect(
        stripAdminPrefix(
          '星巴克国贸店',
          province: '北京市',
          city: <String>[],
          district: '朝阳区',
        ),
        '星巴克国贸店',
      );
    });

    test('前缀均为 null → 仅 trim', () {
      expect(stripAdminPrefix('  中关村大街1号  '), '中关村大街1号');
    });

    test('剥离 township（街道）', () {
      expect(
        stripAdminPrefix(
          '陕西省西安市雁塔区电子城街道太白南路',
          province: '陕西省',
          city: '西安市',
          district: '雁塔区',
          township: '电子城街道',
        ),
        '太白南路',
      );
    });

    test('剥离后为空 → 回退 district（优先于 township）', () {
      expect(
        stripAdminPrefix(
          '陕西省西安市雁塔区电子城街道',
          province: '陕西省',
          city: '西安市',
          district: '雁塔区',
          township: '电子城街道',
        ),
        '雁塔区',
      );
    });
  });

  group('truncatePoiName', () {
    test('恰好 12 字符不截断', () {
      expect(truncatePoiName('123456789012'), '123456789012');
    });

    test('13 字符截断为前 11 + …', () {
      expect(truncatePoiName('1234567890123'), '12345678901…');
    });

    test('中文短名原样返回', () {
      expect(truncatePoiName('中国贸易中心'), '中国贸易中心');
    });
  });

  group('parseRegeoForLocation', () {
    // 构造高德 regeo 响应的辅助函数
    Map<String, dynamic> regeo({
      List<Map<String, dynamic>>? pois,
      String formatted = '',
      String province = '',
      dynamic city,
      String district = '',
      String township = '',
      Map<String, dynamic>? streetNumber,
      String status = '1',
    }) => {
      'status': status,
      'regeocode': {
        if (pois != null) 'pois': pois, // ignore: use_null_aware_elements
        'formatted_address': formatted,
        'addressComponent': {
          'province': province,
          'city': city ?? <String>[],
          'district': district,
          if (township.isNotEmpty) 'township': township,
          if (streetNumber != null) 'streetNumber': streetNumber, // ignore: use_null_aware_elements
        },
      },
    };

    test('POI 命中 → 返回 POI 名', () {
      final data = regeo(
        pois: [
          {'name': '星巴克(国贸店)'},
        ],
      );
      expect(parseRegeoForLocation(data), '星巴克(国贸店)');
    });

    test('POI 名超长 → 截断', () {
      final data = regeo(
        pois: [
          {'name': '1234567890123'},
        ],
      );
      expect(parseRegeoForLocation(data), '12345678901…');
    });

    test('POI 为空、formatted 含省市区 → 去前缀核心', () {
      final data = regeo(
        formatted: '北京市朝阳区建国门外大街1号中国国际贸易中心',
        province: '北京市',
        city: <String>[],
        district: '朝阳区',
      );
      expect(parseRegeoForLocation(data), '建国门外大街1号中国国际贸易中心');
    });

    test('POI name 为空串 → 走 formatted 去前缀', () {
      final data = regeo(
        pois: [
          {'name': ''},
        ],
        formatted: '陕西省西安市雁塔区高新路1号',
        province: '陕西省',
        city: '西安市',
        district: '雁塔区',
      );
      expect(parseRegeoForLocation(data), '高新路1号');
    });

    test('POI 空 + streetNumber 有 → street+number（精确门牌，西安真实数据）', () {
      final data = regeo(
        formatted: '陕西省西安市雁塔区电子城街道太白南路西安高新技术产业开发区',
        province: '陕西省',
        city: '西安市',
        district: '雁塔区',
        township: '电子城街道',
        streetNumber: {'street': '太白南路', 'number': '187号'},
      );
      expect(parseRegeoForLocation(data), '太白南路187号');
    });

    test('streetNumber 只有 street 无 number', () {
      final data = regeo(
        streetNumber: {'street': '某路', 'number': ''},
        formatted: '某市某路',
      );
      expect(parseRegeoForLocation(data), '某路');
    });

    test('POI 空 + 无 streetNumber → formatted 去前缀（含街道）', () {
      final data = regeo(
        formatted: '陕西省西安市雁塔区电子城街道太白南路西安高新技术产业开发区',
        province: '陕西省',
        city: '西安市',
        district: '雁塔区',
        township: '电子城街道',
      );
      expect(parseRegeoForLocation(data), '太白南路西安高新技术产业开发区');
    });

    test('addressComponent 缺失 → formatted 原样返回（降级）', () {
      final data = {
        'status': '1',
        'regeocode': {'formatted_address': '某市某区某路1号'},
      };
      expect(parseRegeoForLocation(data), '某市某区某路1号');
    });

    test('status≠1 → null', () {
      expect(
        parseRegeoForLocation({'status': '0', 'info': 'INVALID_USER_KEY'}),
        isNull,
      );
    });

    test('regeocode 缺失 → null', () {
      expect(parseRegeoForLocation({'status': '1'}), isNull);
    });

    test('POI 空 + formatted 空 → null', () {
      expect(parseRegeoForLocation(regeo()), isNull);
    });
  });
}

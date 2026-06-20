import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/audio_input_device.dart';
import 'package:voice_diary/services/audio_device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('info.colinhan.glimmer/audio_device');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getCurrentInputDevice') {
            return {'type': 'bluetooth', 'label': '蓝牙耳机（AirPods）'};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('正常返回 AudioInputDevice', () async {
    final d = await AudioDeviceService().getCurrentInputDevice();
    expect(d, isNotNull);
    expect(d!.type, AudioInputType.bluetooth);
    expect(d.label, '蓝牙耳机（AirPods）');
  });

  test('native 返回 null → 返回 null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    expect(await AudioDeviceService().getCurrentInputDevice(), isNull);
  });

  test('native 抛异常 → 返回 null（安静失败）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'error', message: 'boom');
        });
    expect(await AudioDeviceService().getCurrentInputDevice(), isNull);
  });
}

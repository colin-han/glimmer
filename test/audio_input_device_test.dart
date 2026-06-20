import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/models/audio_input_device.dart';

void main() {
  group('AudioInputDevice emoji', () {
    test('builtin → 🎙', () {
      const d = AudioInputDevice(type: AudioInputType.builtin, label: '');
      expect(d.emoji, '🎙');
    });
    test('bluetooth → 🎧', () {
      const d = AudioInputDevice(type: AudioInputType.bluetooth, label: '');
      expect(d.emoji, '🎧');
    });
    test('wired → 🎧', () {
      const d = AudioInputDevice(type: AudioInputType.wired, label: '');
      expect(d.emoji, '🎧');
    });
  });

  group('AudioInputDevice.fromMap', () {
    test('解析 type + 透传 label（含蓝牙设备名）', () {
      final d = AudioInputDevice.fromMap({
        'type': 'bluetooth',
        'label': '蓝牙耳机（AirPods）',
      });
      expect(d.type, AudioInputType.bluetooth);
      expect(d.label, '蓝牙耳机（AirPods）');
    });

    test('wired 类型', () {
      final d = AudioInputDevice.fromMap({'type': 'wired', 'label': '有线耳机'});
      expect(d.type, AudioInputType.wired);
    });

    test('容错：未知 type → builtin', () {
      final d = AudioInputDevice.fromMap({'type': 'unknown', 'label': 'x'});
      expect(d.type, AudioInputType.builtin);
    });

    test('容错：缺字段 → 默认内置麦克风', () {
      final d = AudioInputDevice.fromMap({});
      expect(d.type, AudioInputType.builtin);
      expect(d.label, '内置麦克风');
    });
  });
}

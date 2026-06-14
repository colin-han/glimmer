import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/services/fgs_runtime.dart';

void main() {
  tearDown(FgsRuntime.setNone);

  test('默认 mode 为 none', () {
    FgsRuntime.setNone();
    expect(FgsRuntime.mode, FgsMode.none);
  });

  test('setRecording / setProcessing 切换 mode', () {
    FgsRuntime.setRecording();
    expect(FgsRuntime.mode, FgsMode.recording);
    FgsRuntime.setProcessing();
    expect(FgsRuntime.mode, FgsMode.processing);
  });

  test('setNone 回到 none', () {
    FgsRuntime.setProcessing();
    FgsRuntime.setNone();
    expect(FgsRuntime.mode, FgsMode.none);
  });
}

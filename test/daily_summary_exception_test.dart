import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/exceptions.dart';

void main() {
  test('DailySummaryException 是 AppException 子类，携带 message', () {
    const exc = DailySummaryException('昨天录音尚未处理完成');
    expect(exc, isA<AppException>());
    expect(exc.message, '昨天录音尚未处理完成');
    expect(exc.toString(), '昨天录音尚未处理完成');
  });

  test('可按 DailySummaryException 类型捕获，不被通用 AppException 吞掉', () {
    Object thrown() {
      throw const DailySummaryException('聚合失败');
    }

    expect(() => thrown(), throwsA(isA<DailySummaryException>()));
    expect(() => thrown(), throwsA(isA<AppException>()));
  });
}

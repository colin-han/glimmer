import 'package:flutter_test/flutter_test.dart';

import 'package:voice_diary/main.dart';

void main() {
  testWidgets('应用能正常启动', (WidgetTester tester) async {
    await tester.pumpWidget(const VoiceDiaryApp());

    expect(find.text('语音日记 v1'), findsOneWidget);
  });
}

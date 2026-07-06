import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_diary/widgets/streak_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox.expand(
      child: Stack(children: [Positioned.fill(child: child)]),
    ),
  ),
);

void main() {
  testWidgets('idle(compact=false) 渲染三行 + 两个琥珀数字', (tester) async {
    await tester.pumpWidget(
      _wrap(const StreakBadge(streak: 27, total: 40, compact: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('您已经'), findsOneWidget);
    expect(find.text('录制语音日记'), findsOneWidget);

    // 数字在 Text.rich 的 TextSpan 中，需通过 RichText plainText 验证
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plainTexts = richTexts
        .map((r) => (r.text as TextSpan).toPlainText())
        .toList();
    expect(plainTexts.any((t) => t.contains('27')), isTrue);
    expect(plainTexts.any((t) => t.contains('40')), isTrue);
  });

  testWidgets('total==0 渲染鼓励文案、不渲染数字', (tester) async {
    await tester.pumpWidget(
      _wrap(const StreakBadge(streak: 0, total: 0, compact: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('开始第一篇语音日记吧'), findsOneWidget);
    expect(find.text('您已经'), findsNothing);
  });

  testWidgets('compact=true：前后缀 opacity=0（隐藏），数字仍渲染', (tester) async {
    await tester.pumpWidget(
      _wrap(const StreakBadge(streak: 27, total: 40, compact: true)),
    );
    await tester.pumpAndSettle();

    // 数字仍在树中（Text.rich 内 TextSpan）
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plainTexts = richTexts
        .map((r) => (r.text as TextSpan).toPlainText())
        .toList();
    expect(plainTexts.any((t) => t.contains('27')), isTrue);
    // 前后缀被 AnimatedOpacity 置 0（AnimatedOpacity 不产生 Opacity 节点，
    // 直接通过 FadeTransition 实现淡出，因此需按 AnimatedOpacity 查询）
    final opacities = tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .map((o) => o.opacity)
        .toList();
    expect(opacities, contains(0.0));
  });

  testWidgets('compact=true 且无数据：鼓励文案渲染', (tester) async {
    await tester.pumpWidget(
      _wrap(const StreakBadge(streak: 0, total: 0, compact: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('开始第一篇语音日记吧'), findsOneWidget);
  });
}

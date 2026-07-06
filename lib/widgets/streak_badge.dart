import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 录音累计天数徽章。
///
/// 居中醒目形态（[compact]=false）：三行——「您已经」/ 数字行 / 「录制语音日记」，
/// 前两行左对齐、末行右对齐到数字行右边缘，整体由外层居中。
///
/// 缩略形态（[compact]=true）：整体缩到左上角，前后缀淡出，只剩数字行，
/// 带 chip 背景。
///
/// [total]==0 时（首次使用）改显示鼓励文案「开始第一篇语音日记吧」，
/// 动画行为不变。
class StreakBadge extends StatelessWidget {
  const StreakBadge({
    super.key,
    required this.streak,
    required this.total,
    required this.compact,
  });

  final int streak;
  final int total;
  final bool compact;

  static const _duration = Duration(milliseconds: 600);
  static const _curve = Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    return AnimatedAlign(
      alignment: compact ? Alignment.topLeft : const Alignment(0, -0.5),
      duration: _duration,
      curve: _curve,
      child: Padding(
        padding: compact
            ? const EdgeInsets.only(left: 20, top: 14)
            : EdgeInsets.zero,
        child: AnimatedScale(
          scale: compact ? 0.62 : 1.0,
          duration: _duration,
          curve: _curve,
          child: AnimatedContainer(
            duration: _duration,
            curve: _curve,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 9, vertical: 4)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: compact
                  ? WarmTokens.streakChipBg
                  : const Color(0x00000000),
              borderRadius: compact
                  ? BorderRadius.circular(10)
                  : BorderRadius.zero,
              border: compact
                  ? Border.all(color: WarmTokens.streakChipBorder, width: 0.5)
                  : null,
            ),
            child: total == 0 ? _encourage() : _block(),
          ),
        ),
      ),
    );
  }

  Widget _encourage() {
    return Text(
      '开始第一篇语音日记吧',
      style: TextStyle(
        fontSize: 15,
        color: WarmTokens.streakMidGray,
        letterSpacing: 1,
      ),
    );
  }

  Widget _block() {
    final fadeOpacity = compact ? 0.0 : 1.0;
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedOpacity(
            opacity: fadeOpacity,
            duration: _duration,
            curve: _curve,
            child: Text(
              '您已经',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 12,
                color: WarmTokens.streakLightGray,
                letterSpacing: 2,
                height: 1.15,
              ),
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '连续', style: _midStyle()),
                TextSpan(text: '$streak', style: _numStyle()),
                TextSpan(text: '天', style: _midStyle()),
                TextSpan(text: '，', style: _commaStyle()),
                TextSpan(text: '累计', style: _midStyle()),
                TextSpan(text: '$total', style: _numStyle()),
                TextSpan(text: '天', style: _midStyle()),
              ],
            ),
            style: const TextStyle(height: 1.15),
          ),
          AnimatedOpacity(
            opacity: fadeOpacity,
            duration: _duration,
            curve: _curve,
            child: Text(
              '录制语音日记',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: WarmTokens.streakLightGray,
                letterSpacing: 2,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _numStyle() => const TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: WarmTokens.streakAmber,
  );

  TextStyle _midStyle() =>
      const TextStyle(fontSize: 15, color: WarmTokens.streakMidGray);

  TextStyle _commaStyle() =>
      const TextStyle(fontSize: 15, color: WarmTokens.streakComma);
}

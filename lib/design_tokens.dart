import 'package:flutter/material.dart';

/// 暖色设计令牌（Warm Editorial）
///
/// 全应用共享的颜色常量，所有页面和组件统一引用。
class WarmTokens {
  WarmTokens._();

  /// Material3 种子色（暖棕色）
  static const Color seedColor = Color(0xFF8B7355);

  /// 主文字
  static const Color warmBrown = Color(0xFF5D4E3C);

  /// 强调/高亮
  static const Color warmAmber = Color(0xFFC4956A);

  /// 次要文字
  static const Color warmMuted = Color(0xFF9B8E7E);

  /// 卡片背景
  static const Color warmCardBg = Color(0xFFFAF8F5);

  /// 分隔线
  static const Color warmDivider = Color(0xFFE8E2DA);

  /// 展开区/次级背景
  static const Color warmSurface = Color(0xFFF7F3EE);

  /// 处理中横幅背景
  static const Color warmProcessBg = Color(0xFFF0EBE3);

  /// 失败背景
  static const Color failedBg = Color(0xFFFDF0EE);

  /// 失败强调
  static const Color failedAccent = Color(0xFFC47A6A);

  /// 失败文字
  static const Color failedText = Color(0xFF8B4E3C);
}

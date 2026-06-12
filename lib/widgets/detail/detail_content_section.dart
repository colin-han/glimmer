import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 暖色设计常量
class _DesignTokens {
  static const Color warmBrown = Color(0xFF5D4E3C);
  static const Color warmAmber = Color(0xFFC4956A);
  static const Color warmMuted = Color(0xFF9B8E7E);
}

class DetailContentSection extends StatelessWidget {
  final String content;

  const DetailContentSection({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分隔区域：标题行 + 复制按钮
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: _DesignTokens.warmAmber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '润色正文',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _DesignTokens.warmBrown,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.copy_outlined,
                    size: 16,
                    color: _DesignTokens.warmMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 正文内容：温暖的排版
        MarkdownBody(
          data: content,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              fontSize: 15,
              height: 2.0,
              color: _DesignTokens.warmBrown,
              letterSpacing: 0.3,
            ),
            h2: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _DesignTokens.warmBrown,
              height: 2.0,
            ),
            h3: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _DesignTokens.warmBrown,
              height: 1.8,
            ),
            listBullet: TextStyle(
              fontSize: 15,
              color: _DesignTokens.warmAmber,
            ),
            em: TextStyle(
              fontStyle: FontStyle.italic,
              color: _DesignTokens.warmMuted,
            ),
          ),
        ),
      ],
    );
  }
}

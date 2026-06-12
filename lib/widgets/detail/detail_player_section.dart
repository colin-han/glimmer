import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/utterance.dart';
import '../../services/audio_player_service.dart';
import '../audio_player_bar.dart';

/// 暖色设计常量
class _DesignTokens {
  static const Color warmBrown = Color(0xFF5D4E3C);
  static const Color warmAmber = Color(0xFFC4956A);
  static const Color warmMuted = Color(0xFF9B8E7E);
  static const Color warmCardBg = Color(0xFFF7F3EE);
  static const Color warmDivider = Color(0xFFE8E2DA);
}

class DetailPlayerSection extends StatefulWidget {
  final AudioPlayerService playerService;
  final String audioFilePath;
  final List<Utterance> utterances;
  final bool hasTranscript;

  const DetailPlayerSection({
    super.key,
    required this.playerService,
    required this.audioFilePath,
    required this.utterances,
    required this.hasTranscript,
  });

  @override
  State<DetailPlayerSection> createState() => _DetailPlayerSectionState();
}

class _DetailPlayerSectionState extends State<DetailPlayerSection> {
  Duration _position = Duration.zero;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.playerService.positionStream.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });
  }

  int get _currentIndex {
    if (widget.utterances.isEmpty) return -1;
    final posMs = _position.inMilliseconds;
    for (var i = 0; i < widget.utterances.length; i++) {
      final u = widget.utterances[i];
      if (posMs >= u.startTime && posMs < u.endTime) {
        return i;
      }
    }
    if (posMs >= widget.utterances.last.endTime) {
      return widget.utterances.length - 1;
    }
    return -1;
  }

  String get _currentText {
    final idx = _currentIndex;
    if (idx < 0 || idx >= widget.utterances.length) return '';
    return widget.utterances[idx].text;
  }

  String get _fullText => widget.utterances.map((u) => u.text).join();

  void _copyFullText() {
    Clipboard.setData(ClipboardData(text: _fullText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUtterances = widget.hasTranscript && widget.utterances.isNotEmpty;

    return Column(
      children: [
        // 播放器
        AudioPlayerBar(
          playerService: widget.playerService,
          audioFilePath: widget.audioFilePath,
        ),
        if (hasUtterances) ...[
          const SizedBox(height: 12),
          // 字幕行 —— 签名时刻：平滑过渡 + 暖色高亮
          if (_currentText.isNotEmpty)
            GestureDetector(
              onTap: () {
                final idx = _currentIndex;
                if (idx >= 0) {
                  widget.playerService.seek(
                    Duration(milliseconds: widget.utterances[idx].startTime),
                  );
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Text(
                  _currentText,
                  // 用 index 作 key 触发切换动画
                  key: ValueKey(_currentIndex),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: _DesignTokens.warmAmber,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // 展开/收起按钮
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _expanded
                    ? _DesignTokens.warmCardBg
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _expanded
                      ? _DesignTokens.warmDivider
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? '收起识别文本' : '展开识别文本',
                    style: TextStyle(
                      fontSize: 12,
                      color: _DesignTokens.warmMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _expanded ? -0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 16,
                      color: _DesignTokens.warmMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开区域
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: _DesignTokens.warmCardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(
                        top: 16,
                        bottom: 16,
                        left: 16,
                        right: 40,
                      ),
                      child: _buildExpandedText(),
                    ),
                  ),
                  // 右上角复制按钮
                  Positioned(
                    top: 12,
                    right: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _copyFullText,
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
                  ),
                ],
              ),
            ),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedText() {
    final currentIndex = _currentIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.utterances.length; i++)
          _buildSentence(
            widget.utterances[i],
            i == currentIndex,
            i < currentIndex,
          ),
      ],
    );
  }

  Widget _buildSentence(
    Utterance utterance,
    bool isCurrent,
    bool isPlayed,
  ) {
    final Color textColor;
    final FontWeight fontWeight;
    final double fontSize;

    if (isCurrent) {
      textColor = _DesignTokens.warmAmber;
      fontWeight = FontWeight.w600;
      fontSize = 15;
    } else if (isPlayed) {
      textColor = _DesignTokens.warmMuted.withValues(alpha: 0.45);
      fontWeight = FontWeight.normal;
      fontSize = 14;
    } else {
      textColor = _DesignTokens.warmBrown;
      fontWeight = FontWeight.normal;
      fontSize = 14;
    }

    return GestureDetector(
      onTap: () {
        widget.playerService
            .seek(Duration(milliseconds: utterance.startTime));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: fontSize,
            color: textColor,
            fontWeight: fontWeight,
            height: 1.9,
            letterSpacing: 0.2,
          ),
          child: Text(utterance.text),
        ),
      ),
    );
  }
}

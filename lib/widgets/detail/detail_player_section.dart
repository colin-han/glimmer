import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/utterance.dart';
import '../../services/audio_player_service.dart';
import '../audio_player_bar.dart';

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

  String get _fullText =>
      widget.utterances.map((u) => u.text).join();

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
    final theme = Theme.of(context);
    final hasUtterances = widget.hasTranscript && widget.utterances.isNotEmpty;

    return Column(
      children: [
        // 播放器
        AudioPlayerBar(
          playerService: widget.playerService,
          audioFilePath: widget.audioFilePath,
        ),
        if (hasUtterances) ...[
          const SizedBox(height: 8),
          // 字幕行（可点击跳转，无复制按钮）
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
              child: Text(
                _currentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 4),
          // 展开/收起按钮
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _expanded ? '收起识别文本' : '展开识别文本',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
          // 展开区域
          if (_expanded)
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: 8,
                      right: 32,
                    ),
                    child: _buildExpandedText(theme),
                  ),
                  // 右上角复制按钮
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: '复制',
                      onPressed: _copyFullText,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildExpandedText(ThemeData theme) {
    final currentIndex = _currentIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.utterances.length; i++)
          _buildSentence(
            widget.utterances[i],
            i == currentIndex,
            i < currentIndex,
            theme,
          ),
      ],
    );
  }

  Widget _buildSentence(
    Utterance utterance,
    bool isCurrent,
    bool isPlayed,
    ThemeData theme,
  ) {
    final Color textColor;
    final FontWeight fontWeight;

    if (isCurrent) {
      textColor = theme.colorScheme.primary;
      fontWeight = FontWeight.w600;
    } else if (isPlayed) {
      textColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
      fontWeight = FontWeight.normal;
    } else {
      textColor = theme.colorScheme.onSurface;
      fontWeight = FontWeight.normal;
    }

    return GestureDetector(
      onTap: () {
        widget.playerService
            .seek(Duration(milliseconds: utterance.startTime));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          utterance.text,
          style: TextStyle(
            fontSize: 14,
            color: textColor,
            fontWeight: fontWeight,
            height: 1.8,
          ),
        ),
      ),
    );
  }
}

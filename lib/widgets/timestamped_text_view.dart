import 'package:flutter/material.dart';

import '../models/utterance.dart';
import '../services/audio_player_service.dart';

class TimestampedTextView extends StatefulWidget {
  final List<Utterance> utterances;
  final AudioPlayerService playerService;

  const TimestampedTextView({
    super.key,
    required this.utterances,
    required this.playerService,
  });

  @override
  State<TimestampedTextView> createState() => _TimestampedTextViewState();
}

class _TimestampedTextViewState extends State<TimestampedTextView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<AudioPlayerState>(
      stream: widget.playerService.stateStream,
      initialData: widget.playerService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const AudioPlayerState();
        final currentIndex =
            _findCurrentIndex(widget.utterances, state.position);

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
      },
    );
  }

  /// 根据播放位置计算当前高亮的 utterance 索引。
  static int _findCurrentIndex(
      List<Utterance> utterances, Duration position) {
    if (utterances.isEmpty) return -1;
    final posMs = position.inMilliseconds;
    for (var i = 0; i < utterances.length; i++) {
      final u = utterances[i];
      if (posMs >= u.startTime && posMs < u.endTime) {
        return i;
      }
    }
    if (posMs >= utterances.last.endTime) {
      return utterances.length - 1;
    }
    return -1;
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
            fontSize: 16,
            color: textColor,
            fontWeight: fontWeight,
            height: 1.8,
          ),
        ),
      ),
    );
  }
}

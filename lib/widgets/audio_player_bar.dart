import 'package:audio_video_progress_bar/audio_video_progress_bar.dart'
    show ProgressBar, TimeLabelLocation, TimeLabelType;
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../services/audio_player_service.dart';

class AudioPlayerBar extends StatelessWidget {
  final AudioPlayerService playerService;
  final VoidCallback? onCompleted;

  const AudioPlayerBar({
    super.key,
    required this.playerService,
    this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<AudioPlayerState>(
          stream: playerService.stateStream,
          initialData: playerService.currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? const AudioPlayerState();
            return _buildContent(context, state);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AudioPlayerState state) {
    return Row(
      children: [
        // 播放/暂停按钮
        IconButton(
          icon: Icon(
            state.isCompleted
                ? Icons.replay
                : state.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
          ),
          onPressed: () async {
            if (state.isCompleted) {
              await playerService.seek(Duration.zero);
            }
            await playerService.toggle();
          },
        ),
        // 进度条 + 时间标签
        Expanded(
          child: ProgressBar(
            progress: state.position,
            total: state.duration > Duration.zero
                ? state.duration
                : const Duration(seconds: 1),
            onSeek: (position) async {
              await playerService.seek(position);
            },
            timeLabelLocation: TimeLabelLocation.sides,
            timeLabelType: TimeLabelType.remainingTime,
            progressBarColor: WarmTokens.warmAmber,
            baseBarColor: WarmTokens.warmDivider,
            thumbColor: WarmTokens.warmAmber,
            thumbRadius: 6,
            barHeight: 3,
            timeLabelTextStyle: const TextStyle(
              fontSize: 12,
              color: WarmTokens.warmMuted,
            ),
          ),
        ),
        // 变速按钮
        _SpeedButton(
          currentSpeed: state.speed,
          onSpeedChanged: (speed) async {
            await playerService.setSpeed(speed);
          },
        ),
      ],
    );
  }
}

/// 变速切换按钮（1.0x → 1.5x → 2.0x → 1.0x）
class _SpeedButton extends StatelessWidget {
  final double currentSpeed;
  final ValueChanged<double> onSpeedChanged;

  static const _speeds = [1.0, 1.5, 2.0];

  const _SpeedButton({
    required this.currentSpeed,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        final idx = _speeds.indexOf(currentSpeed);
        final next = _speeds[(idx + 1) % _speeds.length];
        onSpeedChanged(next);
      },
      child: Text('${currentSpeed}x'),
    );
  }
}

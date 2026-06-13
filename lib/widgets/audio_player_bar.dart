import 'package:audio_waveforms/audio_waveforms.dart';
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：播放按钮 + 变速按钮
        Row(
          children: [
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
            const Spacer(),
            _SpeedButton(
              currentSpeed: state.speed,
              onSpeedChanged: (speed) async {
                await playerService.setSpeed(speed);
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 波形展示
        SizedBox(
          height: 70,
          child: AudioFileWaveforms(
            size: Size(
              MediaQuery.of(context).size.width - 56,
              70,
            ),
            playerController: playerService.playerController,
            waveformType: WaveformType.fitWidth,
            enableSeekGesture: true,
            playerWaveStyle: const PlayerWaveStyle(
              fixedWaveColor: WarmTokens.warmDivider,
              liveWaveColor: WarmTokens.warmAmber,
              waveThickness: 2.5,
              spacing: 4.0,
              waveCap: StrokeCap.round,
              showSeekLine: true,
              seekLineColor: WarmTokens.warmAmber,
              seekLineThickness: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 时间标签
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(state.position),
              style: const TextStyle(fontSize: 12, color: WarmTokens.warmMuted),
            ),
            Text(
              state.duration > Duration.zero
                  ? _formatDuration(state.duration)
                  : '--:--',
              style: const TextStyle(fontSize: 12, color: WarmTokens.warmMuted),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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

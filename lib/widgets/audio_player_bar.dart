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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 波形总宽 = spacing × samples。fitWidth 模式不会缩放波形，只从左侧
              // 平铺、超出 size.width 的右侧被裁。若固定 spacing 而忽略外层 padding
              //（如详情页 body 的 horizontal padding），波形会溢出屏幕，导致进度色
              // 提前"填满"可见区、与实际播放时间脱节。因此按真实可用宽度反算 spacing，
              // 让采样数恰好铺满，进度与时间严格成正比。
              const samples = 100; // 需与 AudioPlayerService.load 的 noOfSamples 一致
              final spacing = constraints.maxWidth / samples;
              return AudioFileWaveforms(
                size: Size(constraints.maxWidth, 70),
                playerController: playerService.playerController,
                waveformType: WaveformType.fitWidth,
                enableSeekGesture: true,
                playerWaveStyle: PlayerWaveStyle(
                  fixedWaveColor: WarmTokens.warmDivider,
                  liveWaveColor: WarmTokens.warmAmber,
                  waveThickness: 2.5,
                  spacing: spacing,
                  waveCap: StrokeCap.round,
                  showSeekLine: true,
                  seekLineColor: WarmTokens.warmAmber,
                  seekLineThickness: 1.5,
                ),
              );
            },
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

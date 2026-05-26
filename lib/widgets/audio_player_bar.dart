import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';

class AudioPlayerBar extends StatefulWidget {
  final AudioPlayerService playerService;
  final String audioFilePath;

  const AudioPlayerBar({
    super.key,
    required this.playerService,
    required this.audioFilePath,
  });

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _speed = 1.0;
  static const _speeds = [1.0, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    widget.playerService.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    widget.playerService.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    widget.playerService.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () async {
                if (_isPlaying) {
                  await widget.playerService.pause();
                } else {
                  await widget.playerService.play(widget.audioFilePath);
                }
              },
            ),
            Expanded(
              child: Column(
                children: [
                  Slider(
                    value: _duration != null &&
                            _position.inMilliseconds <= _duration!.inMilliseconds
                        ? _position.inMilliseconds.toDouble()
                        : 0,
                    min: 0,
                    max: _duration?.inMilliseconds.toDouble() ?? 1,
                    onChanged: (val) async {
                      await widget.playerService.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_position), style: const TextStyle(fontSize: 12)),
                      Text(
                        _duration != null ? _formatDuration(_duration!) : '--:--',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                final idx = _speeds.indexOf(_speed);
                final next = _speeds[(idx + 1) % _speeds.length];
                setState(() => _speed = next);
                await widget.playerService.setSpeed(next);
              },
              child: Text('${_speed}x'),
            ),
          ],
        ),
      ),
    );
  }
}

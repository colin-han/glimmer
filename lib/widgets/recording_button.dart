import 'package:flutter/material.dart';

enum RecordingState {
  idle,
  recording,
  processing,
}

class RecordingButton extends StatelessWidget {
  final RecordingState state;
  final VoidCallback onTap;
  final int recordingSeconds;

  const RecordingButton({
    super.key,
    required this.state,
    required this.onTap,
    this.recordingSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: state == RecordingState.processing ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCircle(context),
          const SizedBox(height: 16),
          _buildLabel(context),
        ],
      ),
    );
  }

  Widget _buildCircle(BuildContext context) {
    final color = switch (state) {
      RecordingState.idle => Theme.of(context).colorScheme.primary,
      RecordingState.recording => Colors.red,
      RecordingState.processing => Colors.grey,
    };

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color, width: 3),
      ),
      child: Center(
        child: switch (state) {
          RecordingState.idle => Icon(Icons.mic, size: 48, color: color),
          RecordingState.recording => _buildRecordingContent(color),
          RecordingState.processing => const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
        },
      ),
    );
  }

  Widget _buildRecordingContent(Color color) {
    final minutes = recordingSeconds ~/ 60;
    final seconds = recordingSeconds % 60;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.stop, size: 36, color: color),
        const SizedBox(height: 4),
        Text(
          '$minutes:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildLabel(BuildContext context) {
    return Text(
      switch (state) {
        RecordingState.idle => '点击开始录音',
        RecordingState.recording => '点击停止录音',
        RecordingState.processing => '处理中...',
      },
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

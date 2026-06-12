import 'package:flutter/material.dart';

import '../design_tokens.dart';

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
          const SizedBox(height: 20),
          _buildLabel(),
        ],
      ),
    );
  }

  Widget _buildCircle(BuildContext context) {
    final color = switch (state) {
      RecordingState.idle => WarmTokens.warmAmber,
      RecordingState.recording => Colors.red,
      RecordingState.processing => WarmTokens.warmMuted,
    };

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.08),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: switch (state) {
          RecordingState.idle => _buildIdleContent(color),
          RecordingState.recording => _buildRecordingContent(color),
          RecordingState.processing => SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: WarmTokens.warmMuted,
              ),
            ),
        },
      ),
    );
  }

  Widget _buildIdleContent(Color color) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
      ),
      child: Icon(Icons.mic_rounded, size: 36, color: color),
    );
  }

  Widget _buildRecordingContent(Color color) {
    final minutes = recordingSeconds ~/ 60;
    final seconds = recordingSeconds % 60;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.stop_rounded, size: 32, color: color),
        const SizedBox(height: 4),
        Text(
          '$minutes:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel() {
    return Text(
      switch (state) {
        RecordingState.idle => '轻触开始录音',
        RecordingState.recording => '轻触停止录音',
        RecordingState.processing => '正在处理...',
      },
      style: TextStyle(
        fontSize: 14,
        color: WarmTokens.warmMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

class AudioWaveform extends StatefulWidget {
  final Stream<Amplitude>? amplitudeStream;
  final Color color;

  const AudioWaveform({
    super.key,
    this.amplitudeStream,
    this.color = Colors.red,
  });

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform> {
  static const _barCount = 50;
  static const _minDb = -60.0;
  static const _maxDb = 0.0;

  final List<double> _amplitudes = List.generate(_barCount, (_) => 0.0);
  StreamSubscription<Amplitude>? _subscription;

  @override
  void didUpdateWidget(AudioWaveform old) {
    super.didUpdateWidget(old);
    if (widget.amplitudeStream != old.amplitudeStream) {
      _subscription?.cancel();
      _subscription = null;
      if (widget.amplitudeStream != null) {
        _subscription = widget.amplitudeStream!.listen((amp) {
          setState(() {
            _amplitudes.removeAt(0);
            _amplitudes.add(_dbToNormalized(amp.current));
          });
        });
      } else {
        setState(() {
          for (int i = 0; i < _barCount; i++) {
            _amplitudes[i] = 0.0;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  double _dbToNormalized(double db) {
    if (db <= _minDb) return 0.0;
    if (db >= _maxDb) return 1.0;
    return (db - _minDb) / (_maxDb - _minDb);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      width: double.infinity,
      child: CustomPaint(painter: _WaveformPainter(_amplitudes, widget.color)),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;

  _WaveformPainter(this.amplitudes, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / amplitudes.length * 0.6;
    final gap = size.width / amplitudes.length * 0.4;
    final step = barWidth + gap;
    final minHeight = 3.0;
    final radius = Radius.circular(barWidth / 2);

    for (int i = 0; i < amplitudes.length; i++) {
      final normalized = amplitudes[i];
      final barHeight = (normalized * (size.height - minHeight)).clamp(
        minHeight,
        size.height,
      );
      final x = i * step + gap / 2;
      final y = (size.height - barHeight) / 2;

      final paint = Paint()
        ..color = color.withValues(alpha: 0.3 + normalized * 0.7)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true;
}

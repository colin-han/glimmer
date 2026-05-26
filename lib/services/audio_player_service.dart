import 'package:just_audio/just_audio.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  double _speed = 1.0;

  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  double get speed => _speed;

  Future<void> play(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.setSpeed(_speed);
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setSpeed(double rate) async {
    _speed = rate;
    await _player.setSpeed(rate);
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

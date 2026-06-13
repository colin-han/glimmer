import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

/// 播放器统一状态快照。UI 层永远通过此类获取一致的播放状态。
class AudioPlayerState {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final double speed;
  final bool isCompleted;

  const AudioPlayerState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.speed = 1.0,
    this.isCompleted = false,
  });

  AudioPlayerState copyWith({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    double? speed,
    bool? isCompleted,
  }) {
    return AudioPlayerState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final BehaviorSubject<AudioPlayerState> _stateSubject =
      BehaviorSubject<AudioPlayerState>.seeded(
    const AudioPlayerState(),
  );

  String? _loadedFilePath;
  double _speed = 1.0;
  Duration _duration = Duration.zero;

  late final List<StreamSubscription<dynamic>> _subscriptions;

  /// 统一状态流，UI 层通过此 stream 获取一致的播放状态。
  Stream<AudioPlayerState> get stateStream => _stateSubject.stream;

  /// 当前状态快照。
  AudioPlayerState get currentState => _stateSubject.value;

  AudioPlayerService() {
    _subscriptions = [
      _player.positionStream.listen(_onPosition),
      _player.durationStream.listen(_onDuration),
      _player.playingStream.listen(_onPlaying),
      _player.processingStateStream.listen(_onProcessingState),
    ];
  }

  // --------------------------------------------------
  // 公开 API
  // --------------------------------------------------

  /// 加载音频文件（不播放）。
  Future<void> load(String filePath) async {
    if (_loadedFilePath == filePath) return;
    _loadedFilePath = filePath;
    _duration = Duration.zero;
    _emit(const AudioPlayerState());
    await _player.setFilePath(filePath);
  }

  /// 播放。如果已加载同一文件则 resume；否则需先调用 load()。
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.setSpeed(_speed);
    await _player.play();
  }

  /// 暂停。
  Future<void> pause() async {
    await _player.pause();
  }

  /// 播放/暂停切换。
  Future<void> toggle() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  /// 跳转到指定位置，自动 clamp 到 [0, duration]。
  Future<void> seek(Duration position) async {
    final clamped = Duration(
      milliseconds: position.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    await _player.seek(clamped);
  }

  /// 设置播放速度。
  Future<void> setSpeed(double rate) async {
    _speed = rate;
    await _player.setSpeed(rate);
    _emit(_stateSubject.value.copyWith(speed: rate));
  }

  /// 释放资源。
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _player.dispose();
    await _stateSubject.close();
  }

  // --------------------------------------------------
  // 内部：stream 监听
  // --------------------------------------------------

  void _onPosition(Duration position) {
    final clamped = Duration(
      milliseconds: position.inMilliseconds.clamp(
        0,
        _duration.inMilliseconds,
      ),
    );
    _emit(_stateSubject.value.copyWith(
      position: clamped,
      isCompleted: false,
    ));
  }

  void _onDuration(Duration? duration) {
    if (duration != null) {
      _duration = duration;
      _emit(_stateSubject.value.copyWith(duration: duration));
    }
  }

  void _onPlaying(bool isPlaying) {
    _emit(_stateSubject.value.copyWith(isPlaying: isPlaying));
  }

  void _onProcessingState(ProcessingState state) {
    if (state == ProcessingState.completed) {
      _emit(_stateSubject.value.copyWith(
        position: _duration,
        isPlaying: false,
        isCompleted: true,
      ));
    }
  }

  void _emit(AudioPlayerState state) {
    if (!_stateSubject.isClosed) {
      _stateSubject.add(state);
    }
  }
}

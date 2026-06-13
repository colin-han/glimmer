import 'dart:async';

import 'package:audio_waveforms/audio_waveforms.dart';
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
  final PlayerController _controller = PlayerController();
  final BehaviorSubject<AudioPlayerState> _stateSubject =
      BehaviorSubject<AudioPlayerState>.seeded(const AudioPlayerState());

  String? _loadedFilePath;
  double _speed = 1.0;
  int _maxDurationMs = 0;
  int _currentMs = 0;
  StreamSubscription<int>? _durationSubscription;

  /// 统一状态流，UI 层通过此 stream 获取一致的播放状态。
  Stream<AudioPlayerState> get stateStream => _stateSubject.stream;

  /// 当前状态快照。
  AudioPlayerState get currentState => _stateSubject.value;

  /// 暴露 PlayerController 给 AudioFileWaveforms widget 使用。
  PlayerController get playerController => _controller;

  AudioPlayerService() {
    _controller.addListener(_onStateChanged);
    _durationSubscription = _controller.onCurrentDurationChanged.listen(
      _onCurrentDuration,
    );
  }

  // --------------------------------------------------
  // 公开 API
  // --------------------------------------------------

  /// 加载音频文件（不播放）。内部调用 preparePlayer 并提取波形数据。
  Future<void> load(String filePath) async {
    if (_loadedFilePath == filePath) return;
    _loadedFilePath = filePath;
    _maxDurationMs = 0;
    _currentMs = 0;
    _emit(const AudioPlayerState());

    await _controller.preparePlayer(
      path: filePath,
      shouldExtractWaveform: true,
      noOfSamples: 100,
    );
    await _controller.setFinishMode(finishMode: FinishMode.pause);

    final maxMs = await _controller.getDuration(DurationType.max);
    if (maxMs > 0) {
      _maxDurationMs = maxMs;
      _emit(_stateSubject.value.copyWith(
        duration: Duration(milliseconds: maxMs),
      ));
    }
  }

  /// 播放。如果播放完成则先 seek 到开头。
  Future<void> play() async {
    final state = _stateSubject.value;
    if (state.isCompleted) {
      await _controller.seekTo(0);
    }
    await _controller.setRate(_speed);
    await _controller.startPlayer();
  }

  /// 暂停。
  Future<void> pause() async {
    await _controller.pausePlayer();
  }

  /// 播放/暂停切换。
  Future<void> toggle() async {
    if (_controller.playerState == PlayerState.playing) {
      await pause();
    } else {
      await play();
    }
  }

  /// 跳转到指定位置，自动 clamp 到 [0, maxDuration]。
  Future<void> seek(Duration position) async {
    final ms = position.inMilliseconds.clamp(0, _maxDurationMs);
    await _controller.seekTo(ms);
  }

  /// 设置播放速度。
  Future<void> setSpeed(double rate) async {
    _speed = rate;
    await _controller.setRate(rate);
    _emit(_stateSubject.value.copyWith(speed: rate));
  }

  /// 释放资源。
  Future<void> dispose() async {
    await _durationSubscription?.cancel();
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    await _stateSubject.close();
  }

  // --------------------------------------------------
  // 内部：位置流监听
  // --------------------------------------------------

  void _onCurrentDuration(int durationMs) {
    _currentMs = durationMs;

    final position = Duration(
      milliseconds: durationMs.clamp(0, _maxDurationMs),
    );

    final playerState = _controller.playerState;
    final isPlaying = playerState == PlayerState.playing;

    // 检测播放完成：PlayerState 变为 paused（FinishMode.pause）且位置接近末尾
    final isCompleted = (playerState == PlayerState.paused ||
            playerState == PlayerState.stopped) &&
        _maxDurationMs > 0 &&
        durationMs >= _maxDurationMs - 100;

    _emit(_stateSubject.value.copyWith(
      position: position,
      isPlaying: isPlaying,
      isCompleted: isCompleted ? true : null,
    ));
  }

  // --------------------------------------------------
  // 内部：ChangeNotifier 监听（playerState 变化）
  // --------------------------------------------------

  void _onStateChanged() {
    final playerState = _controller.playerState;
    final isPlaying = playerState == PlayerState.playing;

    // 检测播放完成
    final isCompleted = (playerState == PlayerState.paused ||
            playerState == PlayerState.stopped) &&
        _maxDurationMs > 0 &&
        _currentMs >= _maxDurationMs - 100;

    _emit(_stateSubject.value.copyWith(
      isPlaying: isPlaying,
      isCompleted: isCompleted ? true : null,
    ));
  }

  void _emit(AudioPlayerState state) {
    if (!_stateSubject.isClosed) {
      _stateSubject.add(state);
    }
  }
}

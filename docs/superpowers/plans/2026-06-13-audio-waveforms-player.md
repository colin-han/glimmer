# audio_waveforms 播放器实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 audio_waveforms 替换方案 A 的 just_audio + audio_video_progress_bar 实现，提供波形可视化播放器。

**Architecture:** AudioPlayerService 内部从 just_audio 切换为 audio_waveforms 的 PlayerController（ChangeNotifier），通过 BehaviorSubject 保持统一状态流。AudioPlayerBar 用 AudioFileWaveforms 替代 ProgressBar。

**Tech Stack:** Flutter, audio_waveforms (PlayerController + AudioFileWaveforms), rxdart (BehaviorSubject)

**Design spec:** `docs/superpowers/specs/2026-06-13-audio-player-waveforms-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|---|---|---|
| `pubspec.yaml` | 修改 | 新增 audio_waveforms 依赖 |
| `lib/services/audio_player_service.dart` | 重写 | PlayerController 替代 just_audio，保持统一状态流 |
| `lib/widgets/audio_player_bar.dart` | 重写 | AudioFileWaveforms 替代 ProgressBar |

**不涉及的文件：**
- `lib/widgets/detail/detail_player_section.dart` — 订阅 stateStream，接口不变
- `lib/widgets/timestamped_text_view.dart` — 订阅 stateStream，接口不变
- `lib/pages/diary_detail_page.dart` — 参数传递不变
- `lib/services/tts_service.dart` — 直接使用 just_audio，不经过 AudioPlayerService

---

## Task 1: 新增 audio_waveforms 依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 在 pubspec.yaml 的 dependencies 中添加 audio_waveforms**

在 `pubspec.yaml` 的 `dependencies:` 部分，在 `rxdart: ^0.28.0` 下方添加一行：

当前 pubspec.yaml 第 36-45 行为：
```yaml
  cupertino_icons: ^1.0.8
  record: ^7.0.0
  just_audio: ^0.10.5
  audio_video_progress_bar: ^2.0.3
  rxdart: ^0.28.0
  dio: ^5.7.0
```

改为：
```yaml
  cupertino_icons: ^1.0.8
  record: ^7.0.0
  just_audio: ^0.10.5
  audio_video_progress_bar: ^2.0.3
  rxdart: ^0.28.0
  audio_waveforms: ^2.0.2
  dio: ^5.7.0
```

注意：`just_audio` 必须保留，因为 `TtsService` 直接使用它。`audio_video_progress_bar` 保留不影响（后续可清理）。

- [ ] **Step 2: 运行 flutter pub get 安装依赖**

Run: `flutter pub get`
Expected: 成功解析所有依赖，无冲突错误。

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml
git commit -m "chore: 新增 audio_waveforms 依赖"
```

---

## Task 2: 重写 AudioPlayerService（PlayerController 版）

**Files:**
- Rewrite: `lib/services/audio_player_service.dart`

完全替换文件。关键变化：
- 内部从 `just_audio` 的 `AudioPlayer` 切换为 `audio_waveforms` 的 `PlayerController`
- 从 stream 监听改为 `ChangeNotifier` 的 `addListener` 模式
- 保持 `AudioPlayerState`、`stateStream`、`currentState` 接口不变
- 新增 `playerController` getter 供 `AudioFileWaveforms` widget 绑定

- [ ] **Step 1: 替换 AudioPlayerService**

将 `lib/services/audio_player_service.dart` 完整替换为：

```dart
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
      BehaviorSubject<AudioPlayerState>.seeded(
    const AudioPlayerState(),
  );

  String? _loadedFilePath;
  double _speed = 1.0;
  int _maxDurationMs = 0;

  /// 统一状态流，UI 层通过此 stream 获取一致的播放状态。
  Stream<AudioPlayerState> get stateStream => _stateSubject.stream;

  /// 当前状态快照。
  AudioPlayerState get currentState => _stateSubject.value;

  /// 暴露 PlayerController 给 AudioFileWaveforms widget 使用。
  PlayerController get playerController => _controller;

  AudioPlayerService() {
    _controller.addListener(_onChanged);
  }

  // --------------------------------------------------
  // 公开 API
  // --------------------------------------------------

  /// 加载音频文件（不播放）。内部调用 preparePlayer 并提取波形数据。
  Future<void> load(String filePath) async {
    if (_loadedFilePath == filePath) return;
    _loadedFilePath = filePath;
    _maxDurationMs = 0;
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
    _controller.removeListener(_onChanged);
    _controller.dispose();
    await _stateSubject.close();
  }

  // --------------------------------------------------
  // 内部：ChangeNotifier 监听
  // --------------------------------------------------

  void _onChanged() {
    final currentMs = _controller.currentDuration;
    final playerState = _controller.playerState;
    final isPlaying = playerState == PlayerState.playing;

    // 检测播放完成：PlayerState 变为 paused（FinishMode.pause）且位置接近末尾
    final isCompleted = (playerState == PlayerState.paused ||
            playerState == PlayerState.stopped) &&
        _maxDurationMs > 0 &&
        currentMs >= _maxDurationMs - 100;

    final position = Duration(
      milliseconds: currentMs.clamp(0, _maxDurationMs),
    );

    _emit(_stateSubject.value.copyWith(
      position: position,
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
```

- [ ] **Step 2: 验证编译通过**

Run: `flutter analyze lib/services/audio_player_service.dart`
Expected: 无错误，无警告。

- [ ] **Step 3: 提交**

```bash
git add lib/services/audio_player_service.dart
git commit -m "feat: AudioPlayerService 改用 PlayerController 替代 just_audio"
```

---

## Task 3: 重写 AudioPlayerBar（波形版）

**Files:**
- Rewrite: `lib/widgets/audio_player_bar.dart`

完全替换文件。关键变化：
- 用 `AudioFileWaveforms` 替代 `audio_video_progress_bar` 的 `ProgressBar`
- 布局从横排（播放 | 进度条 | 变速）改为纵排（播放/变速 → 波形 → 时间）
- 波形自带 seek 手势，不需要额外的 Slider
- 时间标签从 ProgressBar 自带改为手动 Text 组件

- [ ] **Step 1: 替换 AudioPlayerBar**

将 `lib/widgets/audio_player_bar.dart` 完整替换为：

```dart
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
```

- [ ] **Step 2: 验证编译通过**

Run: `flutter analyze lib/widgets/audio_player_bar.dart`
Expected: 无错误，无警告。

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/audio_player_bar.dart
git commit -m "feat: AudioPlayerBar 改用 AudioFileWaveforms 波形展示"
```

---

## Task 4: 全局编译验证

**Files:**
- 无新文件

- [ ] **Step 1: 运行 flutter analyze 全量检查**

Run: `flutter analyze`
Expected: 无 error 或 warning（info 级别的预先存在的 lint 可忽略）。

- [ ] **Step 2: 运行 flutter build apk --release 确认构建通过**

Run: `flutter build apk --release`
Expected: 构建成功，无编译错误。

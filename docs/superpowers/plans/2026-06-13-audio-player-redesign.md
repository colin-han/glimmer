# 音频播放器重写实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重写音频播放器，解决进度/时间不同步、总时间显示错误、播放完成进度波动三个核心问题。

**Architecture:** 用 rxdart BehaviorSubject 将 just_audio 的多个 stream 合并为统一的 `AudioPlayerState` 流，UI 层通过 StreamBuilder 订阅单一状态源。进度条 UI 使用 `audio_video_progress_bar` 包替换手动 Slider。

**Tech Stack:** Flutter, just_audio, rxdart (BehaviorSubject), audio_video_progress_bar

**Design spec:** `docs/superpowers/specs/2026-06-13-audio-player-redesign-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|---|---|---|
| `lib/services/audio_player_service.dart` | 重写 | 统一状态管理（BehaviorSubject） |
| `lib/widgets/audio_player_bar.dart` | 重写 | 进度条 UI（audio_video_progress_bar） |
| `lib/widgets/detail/detail_player_section.dart` | 修改 | 订阅 stateStream + 自动滚动 |
| `lib/widgets/timestamped_text_view.dart` | 修改 | 订阅 stateStream |
| `lib/pages/diary_detail_page.dart` | 修改 | 适配 load()+play() 分离 |
| `pubspec.yaml` | 修改 | 新增依赖 |

**不涉及的文件：**
- `lib/services/tts_service.dart` — 直接使用 just_audio 的 AudioPlayer，不经过 AudioPlayerService，无需改动。

---

## Task 1: 新增依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 在 pubspec.yaml 的 dependencies 中添加 audio_video_progress_bar 和 rxdart**

在 `pubspec.yaml` 的 `dependencies:` 部分，在 `just_audio: ^0.10.5` 下方添加两行：

```yaml
  just_audio: ^0.10.5
  audio_video_progress_bar: ^2.0.3
  rxdart: ^0.28.0
```

- [ ] **Step 2: 运行 flutter pub get 安装依赖**

Run: `flutter pub get`
Expected: 成功解析所有依赖，无冲突错误。

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: 新增 audio_video_progress_bar 和 rxdart 依赖"
```

---

## Task 2: 重写 AudioPlayerService

**Files:**
- Rewrite: `lib/services/audio_player_service.dart`

完全替换文件内容为以下代码：

- [ ] **Step 1: 写入新的 AudioPlayerService**

将 `lib/services/audio_player_service.dart` 完整替换为：

```dart
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
```

- [ ] **Step 2: 验证编译通过**

Run: `flutter analyze lib/services/audio_player_service.dart`
Expected: 无错误，无警告。

- [ ] **Step 3: 提交**

```bash
git add lib/services/audio_player_service.dart
git commit -m "feat: 重写 AudioPlayerService，BehaviorSubject 统一状态管理"
```

---

## Task 3: 重写 AudioPlayerBar

**Files:**
- Rewrite: `lib/widgets/audio_player_bar.dart`

完全替换文件内容。关键变化：
- 不再接收 `audioFilePath` 参数，文件路径由 Service 内部管理
- 用 `StreamBuilder<AudioPlayerState>` 替代手动 `setState`
- 用 `audio_video_progress_bar` 的 `ProgressBar` 替代手动 `Slider`

- [ ] **Step 1: 写入新的 AudioPlayerBar**

将 `lib/widgets/audio_player_bar.dart` 完整替换为：

```dart
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart'
    show ProgressBar, TimeLabelLocation, TimeLabelType;
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
    return Row(
      children: [
        // 播放/暂停按钮
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
        // 进度条 + 时间标签
        Expanded(
          child: ProgressBar(
            progress: state.position,
            total: state.duration > Duration.zero
                ? state.duration
                : const Duration(seconds: 1),
            onSeek: (position) async {
              await playerService.seek(position);
            },
            timeLabelLocation: TimeLabelLocation.sides,
            timeLabelType: TimeLabelType.remainingTime,
            progressBarColor: WarmTokens.warmAmber,
            baseBarColor: WarmTokens.warmDivider,
            thumbColor: WarmTokens.warmAmber,
            thumbRadius: 6,
            barHeight: 3,
            timeLabelTextStyle: const TextStyle(
              fontSize: 12,
              color: WarmTokens.warmMuted,
            ),
          ),
        ),
        // 变速按钮
        _SpeedButton(
          currentSpeed: state.speed,
          onSpeedChanged: (speed) async {
            await playerService.setSpeed(speed);
          },
        ),
      ],
    );
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
git commit -m "feat: 重写 AudioPlayerBar，使用 ProgressBar + StreamBuilder"
```

---

## Task 4: 修改 DetailPlayerSection

**Files:**
- Modify: `lib/widgets/detail/detail_player_section.dart`

关键变化：
- 去掉 `audioFilePath` 参数，改为在内部通过 Service 的 `load()` 加载
- 改为订阅 `stateStream` 替代单独订阅 `positionStream`
- 添加自动滚动到当前句子功能

- [ ] **Step 1: 写入修改后的 DetailPlayerSection**

将 `lib/widgets/detail/detail_player_section.dart` 完整替换为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_tokens.dart';
import '../../models/utterance.dart';
import '../../services/audio_player_service.dart';
import '../audio_player_bar.dart';

class DetailPlayerSection extends StatefulWidget {
  final AudioPlayerService playerService;
  final String audioFilePath;
  final List<Utterance> utterances;
  final bool hasTranscript;

  const DetailPlayerSection({
    super.key,
    required this.playerService,
    required this.audioFilePath,
    required this.utterances,
    required this.hasTranscript,
  });

  @override
  State<DetailPlayerSection> createState() => _DetailPlayerSectionState();
}

class _DetailPlayerSectionState extends State<DetailPlayerSection> {
  bool _expanded = false;
  bool _loaded = false;
  int _previousIndex = -1;

  // 展开文本区域的滚动控制器
  final ScrollController _scrollController = ScrollController();

  // 每个 utterance 对应的 GlobalKey，用于自动滚动定位
  final Map<int, GlobalKey> _utteranceKeys = {};

  @override
  void initState() {
    super.initState();
    _loadAudio();
    // 为每个 utterance 创建 GlobalKey
    for (var i = 0; i < widget.utterances.length; i++) {
      _utteranceKeys[i] = GlobalKey();
    }
  }

  Future<void> _loadAudio() async {
    try {
      await widget.playerService.load(widget.audioFilePath);
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      debugPrint('[播放器] 加载音频失败: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 根据播放位置计算当前高亮的 utterance 索引。
  static int findCurrentIndex(List<Utterance> utterances, Duration position) {
    if (utterances.isEmpty) return -1;
    final posMs = position.inMilliseconds;
    for (var i = 0; i < utterances.length; i++) {
      final u = utterances[i];
      if (posMs >= u.startTime && posMs < u.endTime) {
        return i;
      }
    }
    if (posMs >= utterances.last.endTime) {
      return utterances.length - 1;
    }
    return -1;
  }

  /// 自动滚动到当前播放的句子。
  void _scrollToIndex(int index) {
    if (index < 0 || !_expanded) return;
    final key = _utteranceKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUtterances =
        widget.hasTranscript && widget.utterances.isNotEmpty;

    return Column(
      children: [
        // 播放器
        AudioPlayerBar(
          playerService: widget.playerService,
        ),
        if (hasUtterances && _loaded) ...[
          const SizedBox(height: 12),
          // 字幕行 + 展开区域
          StreamBuilder<AudioPlayerState>(
            stream: widget.playerService.stateStream,
            initialData: widget.playerService.currentState,
            builder: (context, snapshot) {
              final state = snapshot.data ?? const AudioPlayerState();
              final currentIndex =
                  findCurrentIndex(widget.utterances, state.position);

              // 当前句子变化时触发自动滚动
              if (currentIndex != _previousIndex && currentIndex >= 0) {
                _previousIndex = currentIndex;
                // 用 addPostFrameCallback 避免 build 过程中触发滚动
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToIndex(currentIndex);
                });
              }

              final currentText = currentIndex >= 0 &&
                      currentIndex < widget.utterances.length
                  ? widget.utterances[currentIndex].text
                  : '';

              return Column(
                children: [
                  // 字幕行
                  if (currentText.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        if (currentIndex >= 0) {
                          widget.playerService.seek(Duration(
                              milliseconds:
                                  widget.utterances[currentIndex].startTime));
                        }
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: Text(
                          currentText,
                          key: ValueKey(currentIndex),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: WarmTokens.warmAmber,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  // 展开/收起按钮
                  _buildExpandToggle(),
                  // 展开区域
                  _buildExpandedSection(currentIndex),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildExpandToggle() {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              _expanded ? WarmTokens.warmSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _expanded
                ? WarmTokens.warmDivider
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _expanded ? '收起识别文本' : '展开识别文本',
              style: TextStyle(
                fontSize: 12,
                color: WarmTokens.warmMuted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _expanded ? -0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                size: 16,
                color: WarmTokens.warmMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedSection(int currentIndex) {
    return AnimatedCrossFade(
      firstChild: const SizedBox.shrink(),
      secondChild: SizedBox(
        height: 220,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: WarmTokens.warmSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.only(
                  top: 16,
                  bottom: 16,
                  left: 16,
                  right: 40,
                ),
                child: _buildExpandedText(currentIndex),
              ),
            ),
            // 右上角复制按钮
            Positioned(
              top: 12,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _copyFullText,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.copy_outlined,
                      size: 16,
                      color: WarmTokens.warmMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      crossFadeState:
          _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 250),
      sizeCurve: Curves.easeOutCubic,
    );
  }

  Widget _buildExpandedText(int currentIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.utterances.length; i++)
          _buildSentence(
            widget.utterances[i],
            i == currentIndex,
            i < currentIndex,
            i,
          ),
      ],
    );
  }

  Widget _buildSentence(
    Utterance utterance,
    bool isCurrent,
    bool isPlayed,
    int index,
  ) {
    final Color textColor;
    final FontWeight fontWeight;
    final double fontSize;

    if (isCurrent) {
      textColor = WarmTokens.warmAmber;
      fontWeight = FontWeight.w600;
      fontSize = 15;
    } else if (isPlayed) {
      textColor = WarmTokens.warmMuted.withValues(alpha: 0.45);
      fontWeight = FontWeight.normal;
      fontSize = 14;
    } else {
      textColor = WarmTokens.warmBrown;
      fontWeight = FontWeight.normal;
      fontSize = 14;
    }

    return GestureDetector(
      onTap: () {
        widget.playerService
            .seek(Duration(milliseconds: utterance.startTime));
      },
      child: Padding(
        key: _utteranceKeys[index],
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: fontSize,
            color: textColor,
            fontWeight: fontWeight,
            height: 1.9,
            letterSpacing: 0.2,
          ),
          child: Text(utterance.text),
        ),
      ),
    );
  }

  String get _fullText => widget.utterances.map((u) => u.text).join();

  void _copyFullText() {
    Clipboard.setData(ClipboardData(text: _fullText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证编译通过**

Run: `flutter analyze lib/widgets/detail/detail_player_section.dart`
Expected: 无错误，无警告。

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/detail/detail_player_section.dart
git commit -m "feat: DetailPlayerSection 改用 stateStream + 自动滚动"
```

---

## Task 5: 修改 TimestampedTextView

**Files:**
- Modify: `lib/widgets/timestamped_text_view.dart`

关键变化：
- 改为订阅 `stateStream` 替代单独订阅 `positionStream`
- 使用共享的 `findCurrentIndex` 静态方法（从 DetailPlayerSection 提取）

注意：`findCurrentIndex` 的逻辑目前重复在两个文件中。这里先在 `TimestampedTextView` 内也保留一份相同的静态方法。如果后续要提取共享工具方法，可以在单独的重构任务中完成，避免改动面过大。

- [ ] **Step 1: 写入修改后的 TimestampedTextView**

将 `lib/widgets/timestamped_text_view.dart` 完整替换为：

```dart
import 'package:flutter/material.dart';

import '../models/utterance.dart';
import '../services/audio_player_service.dart';

class TimestampedTextView extends StatefulWidget {
  final List<Utterance> utterances;
  final AudioPlayerService playerService;

  const TimestampedTextView({
    super.key,
    required this.utterances,
    required this.playerService,
  });

  @override
  State<TimestampedTextView> createState() => _TimestampedTextViewState();
}

class _TimestampedTextViewState extends State<TimestampedTextView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<AudioPlayerState>(
      stream: widget.playerService.stateStream,
      initialData: widget.playerService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const AudioPlayerState();
        final currentIndex =
            _findCurrentIndex(widget.utterances, state.position);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.utterances.length; i++)
              _buildSentence(
                widget.utterances[i],
                i == currentIndex,
                i < currentIndex,
                theme,
              ),
          ],
        );
      },
    );
  }

  /// 根据播放位置计算当前高亮的 utterance 索引。
  static int _findCurrentIndex(
      List<Utterance> utterances, Duration position) {
    if (utterances.isEmpty) return -1;
    final posMs = position.inMilliseconds;
    for (var i = 0; i < utterances.length; i++) {
      final u = utterances[i];
      if (posMs >= u.startTime && posMs < u.endTime) {
        return i;
      }
    }
    if (posMs >= utterances.last.endTime) {
      return utterances.length - 1;
    }
    return -1;
  }

  Widget _buildSentence(
    Utterance utterance,
    bool isCurrent,
    bool isPlayed,
    ThemeData theme,
  ) {
    final Color textColor;
    final FontWeight fontWeight;

    if (isCurrent) {
      textColor = theme.colorScheme.primary;
      fontWeight = FontWeight.w600;
    } else if (isPlayed) {
      textColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
      fontWeight = FontWeight.normal;
    } else {
      textColor = theme.colorScheme.onSurface;
      fontWeight = FontWeight.normal;
    }

    return GestureDetector(
      onTap: () {
        widget.playerService
            .seek(Duration(milliseconds: utterance.startTime));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          utterance.text,
          style: TextStyle(
            fontSize: 16,
            color: textColor,
            fontWeight: fontWeight,
            height: 1.8,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证编译通过**

Run: `flutter analyze lib/widgets/timestamped_text_view.dart`
Expected: 无错误，无警告。

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/timestamped_text_view.dart
git commit -m "feat: TimestampedTextView 改用 stateStream"
```

---

## Task 6: 适配 DiaryDetailPage

**Files:**
- Modify: `lib/pages/diary_detail_page.dart`

当前代码中 `DetailPlayerSection` 接收 `playerService` 和 `audioFilePath`。由于 `DetailPlayerSection` 内部已改为通过 `playerService.load()` 加载音频（Task 4），`DiaryDetailPage` 本身不需要调用 `play()`，所以只需确保参数传递正确即可。

查看当前代码（`diary_detail_page.dart:471-477`）：

```dart
DetailPlayerSection(
  playerService: _playerService,
  audioFilePath: audioPath,
  utterances: _activeUtterances,
  hasTranscript: _hasTranscript,
),
```

这段代码的调用方式与修改后的 `DetailPlayerSection` 的接口完全一致（`playerService`、`audioFilePath`、`utterances`、`hasTranscript` 四个参数均保留），所以 **`diary_detail_page.dart` 不需要任何改动**。

- [ ] **Step 1: 确认 DiaryDetailPage 无需修改**

检查 `diary_detail_page.dart` 中所有使用 `AudioPlayerService` 和 `AudioPlayerBar` 的地方：
- 第 39 行：`final _playerService = AudioPlayerService();` — 不变
- 第 63 行：`_playerService.dispose();` — 不变
- 第 472-477 行：`DetailPlayerSection(...)` — 参数完全匹配，不变

确认无需修改，跳过此任务。

---

## Task 7: 全局编译验证

**Files:**
- 无新文件

- [ ] **Step 1: 运行 flutter analyze 全量检查**

Run: `flutter analyze`
Expected: 无错误，无警告。

- [ ] **Step 2: 运行 flutter build apk --release 确认构建通过**

Run: `flutter build apk --release`
Expected: 构建成功，无编译错误。

- [ ] **Step 3: 提交（如有自动生成的变更）**

```bash
git status
# 如果只有之前已提交的变更，则无需额外提交
```

# 音频播放器重写设计 — audio_waveforms 方案

## 背景

作为方案 A（just_audio + audio_video_progress_bar）的替代方案，使用 `audio_waveforms` 包提供波形可视化播放器。在当前分支上直接替换方案 A 的实现。

## 方案：audio_waveforms 波形播放器

- 用 `audio_waveforms` 的 `PlayerController` 完全替代 `just_audio` 的 `AudioPlayer`
- 用 `AudioFileWaveforms` widget 替代 `audio_video_progress_bar` 的 `ProgressBar`
- 保持 `AudioPlayerState` + `BehaviorSubject` 统一状态管理模式不变
- 字幕同步部分（DetailPlayerSection / TimestampedTextView）不需要改动

## 架构设计

### AudioPlayerService（改用 PlayerController）

```
AudioPlayerService
├── 内部状态
│   ├── PlayerController _controller（audio_waveforms，替代 just_audio）
│   ├── BehaviorSubject<AudioPlayerState> _stateSubject（保持不变）
│   ├── String? _loadedFilePath
│   ├── double _speed
│   └── int _maxDuration（毫秒，从 PlayerController.getDuration 获取）
│
├── 新增公开属性
│   ├── PlayerController get playerController — 供 AudioFileWaveforms 绑定
│
├── 公开 API（接口不变）
│   ├── Stream<AudioPlayerState> get stateStream
│   ├── AudioPlayerState get currentState
│   ├── Future<void> load(String filePath) → _controller.preparePlayer()
│   ├── Future<void> play() → _controller.startPlayer()
│   ├── Future<void> pause() → _controller.pausePlayer()
│   ├── Future<void> toggle()
│   ├── Future<void> seek(Duration) → _controller.seekTo(ms)
│   ├── Future<void> setSpeed(double) → _controller.setRate()
│   └── Future<void> dispose()
│
├── ChangeNotifier 监听
│   ├── _controller.addListener(_onChanged)
│   ├── _onChanged 读取 _controller.currentDuration 和 _controller.playerState
│   ├── 播放完成：检测 playerState 变为 stopped/paused 且 currentDuration >= maxDuration - 100
│   └── 所有状态变更写入 _stateSubject
│
└── 关键行为
    ├── load() 调用 preparePlayer(shouldExtractWaveform: true, noOfSamples: 100)
    ├── load() 调用 setFinishMode(finishMode: FinishMode.pause) 便于重播
    ├── seek 时 clamp position 到 [0, maxDuration]
    └── play() 检测完成状态时先 seekTo(0) 再 startPlayer
```

### AudioPlayerBar（波形版）

```
AudioPlayerBar
├── 输入
│   └── AudioPlayerService playerService
│
├── UI 结构
│   └── StreamBuilder<AudioPlayerState>
│       ├── Row [播放/暂停按钮 | 变速按钮]
│       ├── SizedBox(height: 8)
│       ├── AudioFileWaveforms（波形展示 + seek 手势）
│       │   ├── playerController: playerService.playerController
│       │   ├── waveformType: WaveformType.fitWidth
│       │   ├── enableSeekGesture: true
│       │   ├── playerWaveStyle: PlayerWaveStyle(
│       │   │     fixedWaveColor: WarmTokens.warmDivider,
│       │   │     liveWaveColor: WarmTokens.warmAmber,
│       │   │     waveThickness: 2.5,
│       │   │     spacing: 4.0,
│       │   │     waveCap: StrokeCap.round,
│       │   │     showSeekLine: true,
│       │   │     seekLineColor: WarmTokens.warmAmber,
│       │   │   )
│       │   └── size: (screenWidth - 56, 70)
│       │
│       ├── SizedBox(height: 4)
│       └── Row [当前时间 ............... 总时间]
│
└── 布局
    Card + Padding + Column [
      Row [播放按钮 | 变速按钮],
      波形,
      时间标签行,
    ]
```

### 不需要改动的文件

- `lib/widgets/detail/detail_player_section.dart` — 订阅 stateStream 不变
- `lib/widgets/timestamped_text_view.dart` — 订阅 stateStream 不变
- `lib/pages/diary_detail_page.dart` — 参数传递不变

## 依赖变更

### 新增
- `audio_waveforms: ^2.0.2` — 波形播放器

### 可移除
- `audio_video_progress_bar: ^2.0.3` — 不再需要（但保留也不影响）
- `just_audio: ^0.10.5` — 不再使用（但 TtsService 仍直接依赖 just_audio，必须保留）

### 保持不变
- `rxdart: ^0.28.0` — BehaviorSubject

## 注意事项

1. **波形提取延迟**：`preparePlayer` 会提取波形数据，对于长录音可能需要数秒。load() 期间 UI 应显示 loading 状态。
2. **just_audio 共存**：`TtsService` 直接使用 just_audio 的 AudioPlayer，不受本次改动影响。
3. **音频焦点**：PlayerController 和 just_audio 使用不同的原生播放器实例，不会冲突（TTS 播放时主播放器不会同时播放）。
4. **PlayerController.currentDuration 更新频率**：默认 UpdateFrequency.low（200ms），可通过 `updateFrequency` 属性调整为 high（50ms）以获得更平滑的进度更新。

## 数据兼容性

- 不涉及数据格式变更
- 播放器为纯 UI 层改动，不影响已保存的日记数据

## 测试策略

- 手动测试为主
- 测试场景：
  1. 播放/暂停/恢复，验证波形颜色变化和进度同步
  2. 拖动波形 seek，验证位置和时间准确
  3. 变速播放，验证波形跟踪正常
  4. 播放到结尾，验证完成状态
  5. 字幕高亮与播放音频同步
  6. 长录音（>5分钟）的波形提取速度和展示效果

## 文件变更清单

| 文件 | 操作 | 说明 |
|---|---|---|
| `lib/services/audio_player_service.dart` | 重写 | PlayerController 替代 just_audio |
| `lib/widgets/audio_player_bar.dart` | 重写 | AudioFileWaveforms 替代 ProgressBar |
| `pubspec.yaml` | 修改 | 新增 audio_waveforms 依赖 |

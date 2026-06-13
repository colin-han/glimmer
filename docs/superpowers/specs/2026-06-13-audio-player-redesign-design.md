# 音频播放器重写设计

## 背景

当前音频播放器存在三个核心问题：
1. **进度条与时间不同步** — 多个 Widget 独立订阅 just_audio 的 positionStream/durationStream，导致 UI 状态不一致
2. **总时间显示错误** — durationStream 初始为 null，后续更新可能遗漏
3. **播放完成时进度波动** — 播放结束前 position 值可能超过 duration，且缺少完成状态处理

根本原因：AudioPlayerService 直接暴露 just_audio 的原始 stream，缺少统一的状态管理和边界保护。

## 方案选择

### 主方案：just_audio + audio_video_progress_bar

- 保留 just_audio 播放引擎
- 引入 `audio_video_progress_bar` 作为进度条 UI 组件
- 用 rxdart BehaviorSubject 合并 position/duration/playing 为统一状态流
- 改动最小、风险最低、与现有代码完美兼容

### 备选方案：audio_waveforms 波形播放器（稍后另开 worktree 试验）

- 替换播放引擎为 `audio_waveforms` 的 PlayerController
- 展示音频波形可视化，播放时颜色动态变化
- 视觉效果最佳，但需要替换播放引擎，改动面较大
- 活跃维护（5 个月前更新），质量满分

## 架构设计

### AudioPlayerState（值对象）

```dart
class AudioPlayerState {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final double speed;
  final bool isCompleted;
}
```

所有播放状态打包在一个不可变对象中，UI 层永远看到一致的快照。

### AudioPlayerService（重构版）

```
AudioPlayerService
├── 内部状态
│   ├── AudioPlayer _player (just_audio)
│   ├── BehaviorSubject<AudioPlayerState> _stateSubject
│   ├── String? _loadedFilePath — 记录已加载的文件路径
│   └── double _speed — 当前播放速度
│
├── 公开 API
│   ├── Stream<AudioPlayerState> get stateStream — 统一状态流
│   ├── AudioPlayerState get currentState — 当前状态快照
│   ├── Future<void> load(String filePath) — 加载音频（不播放）
│   ├── Future<void> play() — 播放（如已加载则 resume，否则需先 load）
│   ├── Future<void> pause() — 暂停
│   ├── Future<void> toggle() — 播放/暂停切换
│   ├── Future<void> seek(Duration position) — 跳转
│   ├── Future<void> setSpeed(double rate) — 变速
│   └── Future<void> dispose() — 释放资源
│
├── 内部监听
│   ├── _player.positionStream → 更新 state.position（clamp 到 [0, duration]）
│   ├── _player.durationStream → 更新 state.duration
│   ├── _player.playingStream → 更新 state.isPlaying
│   ├── _player.playerStateStream → 检测播放完成（processingState == completed）
│   └── 所有监听统一写入 _stateSubject，UI 只订阅一个 stream
│
└── 关键行为
    ├── play() 不再每次 setFilePath，改为判断 _loadedFilePath
    ├── seek 时 clamp position 到 [0, duration]
    ├── 播放完成时设置 isCompleted=true, position=duration
    └── load() 新文件时重置所有状态
```

### AudioPlayerBar（重构版）

```
AudioPlayerBar
├── 输入
│   └── AudioPlayerService playerService
│
├── UI 结构
│   └── StreamBuilder<AudioPlayerState>
│       ├── ProgressBar（audio_video_progress_bar）
│       │   ├── progress: state.position
│       │   ├── total: state.duration
│       │   ├── onSeek: (d) => playerService.seek(d)
│       │   ├── timeLabelLocation: TimeLabelLocation.sides
│       │   ├── progressBarColor: WarmTokens.warmAmber
│       │   ├── baseBarColor: WarmTokens.warmDivider
│       │   ├── thumbColor: WarmTokens.warmAmber
│       │   └── thumbRadius / barHeight 可配置
│       │
│       ├── IconButton（播放/暂停）
│       │   ├── icon: state.isPlaying ? Icons.pause : Icons.play_arrow
│       │   └── onPressed: playerService.toggle()
│       │
│       └── TextButton（变速切换）
│           ├── 显示: '${state.speed}x'
│           ├── speeds: [1.0, 1.5, 2.0]
│           └── onPressed: playerService.setSpeed(next)
│
└── 布局
    └── Card + Padding + Row [播放按钮 | ProgressBar | 变速按钮]
```

### 字幕同步修复

**DetailPlayerSection 和 TimestampedTextView**：

- 改为订阅 `playerService.stateStream`，不再单独订阅 positionStream
- `_currentIndex` 计算逻辑不变，但数据源从 `_position` 改为 `state.position`
- 添加自动滚动功能：展开文本区域时，当前句子变化触发 `Scrollable.ensureVisible()`
- 提取共享逻辑：
  - 当前索引计算 → 提取为工具方法 `findCurrentUtteranceIndex(List<Utterance>, Duration)`
  - 消除 DetailPlayerSection 和 TimestampedTextView 之间的代码重复

### DiaryDetailPage 适配

- `play()` 调用改为 `load()` + `play()` 分离
- 删除手动传递 `audioFilePath` 给 `AudioPlayerBar` 的逻辑
- 保持 DetailPlayerSection 和 TimestampedTextView 的现有布局不变

## 依赖变更

### 新增
- `audio_video_progress_bar: ^2.0.3` — 进度条 UI 组件
- `rxdart: ^0.28.0` — BehaviorSubject（just_audio 已间接依赖 rxdart）

### 保持不变
- `just_audio: ^0.10.5` — 播放引擎

### 不再需要
- 无（不删除任何依赖）

## 数据兼容性

- 不涉及数据格式变更
- 不涉及 SQLite schema 变更
- 播放器为纯 UI 层改动，不影响已保存的日记数据

## 测试策略

- 手动测试为主（播放器行为难以自动化测试）
- 测试场景：
  1. 播放/暂停/恢复，验证进度和时间同步
  2. 拖拽进度条 seek，验证位置和时间准确
  3. 变速播放，验证进度同步正常
  4. 播放到结尾，验证完成状态和进度不波动
  5. 字幕高亮与播放音频同步
  6. 点击字幕跳转，验证 seek 位置正确
  7. 展开/收起文本，验证自动滚动到当前句子

## 文件变更清单

| 文件 | 操作 | 说明 |
|---|---|---|
| `lib/services/audio_player_service.dart` | 重写 | BehaviorSubject 统一状态管理 |
| `lib/widgets/audio_player_bar.dart` | 重写 | 使用 ProgressBar + StreamBuilder |
| `lib/widgets/detail/detail_player_section.dart` | 修改 | 改为订阅 stateStream + 自动滚动 |
| `lib/widgets/timestamped_text_view.dart` | 修改 | 改为订阅 stateStream + 提取共享逻辑 |
| `lib/pages/diary_detail_page.dart` | 修改 | 适配新的 Service API |
| `pubspec.yaml` | 修改 | 新增 audio_video_progress_bar 依赖 |

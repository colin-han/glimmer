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
    final hasUtterances = widget.hasTranscript && widget.utterances.isNotEmpty;

    return Column(
      children: [
        // 播放器
        AudioPlayerBar(playerService: widget.playerService),
        if (hasUtterances && _loaded) ...[
          const SizedBox(height: 12),
          // 字幕行 + 展开区域
          StreamBuilder<AudioPlayerState>(
            stream: widget.playerService.stateStream,
            initialData: widget.playerService.currentState,
            builder: (context, snapshot) {
              final state = snapshot.data ?? const AudioPlayerState();
              final currentIndex = findCurrentIndex(
                widget.utterances,
                state.position,
              );

              // 当前句子变化时触发自动滚动
              if (currentIndex != _previousIndex && currentIndex >= 0) {
                _previousIndex = currentIndex;
                // 用 addPostFrameCallback 避免 build 过程中触发滚动
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToIndex(currentIndex);
                });
              }

              final currentText =
                  currentIndex >= 0 && currentIndex < widget.utterances.length
                  ? widget.utterances[currentIndex].text
                  : '';

              return Column(
                children: [
                  // 字幕行
                  if (currentText.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        if (currentIndex >= 0) {
                          widget.playerService.seek(
                            Duration(
                              milliseconds:
                                  widget.utterances[currentIndex].startTime,
                            ),
                          );
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
          color: _expanded ? WarmTokens.warmSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _expanded ? WarmTokens.warmDivider : Colors.transparent,
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
      crossFadeState: _expanded
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
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
        widget.playerService.seek(Duration(milliseconds: utterance.startTime));
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
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }
}

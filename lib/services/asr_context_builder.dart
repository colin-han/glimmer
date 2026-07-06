import 'dart:convert';

/// 构建 ASR `request.corpus.context` 的 JSON 字符串。
///
/// [hotwords] 为逗号分隔的专名（人名/产品/项目）；[prompt] 为个性化上下文一句话
/// （口音/常驻地/语言/话题）。两者皆无有效内容时返回 `null`，调用方据此不注入 `corpus`。
///
/// 红线：热词来源必须为用户提供的金标准。**严禁**从 ASR 输出自动抽取热词回填，
/// 否则会把识别错误固化为权威词（反馈污染）。自动抽取需配合用户在环确认，属后续议题。
String? buildAsrCorpusContext({String? hotwords, String? prompt}) {
  final words = (hotwords ?? '')
      .split(',')
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();
  final promptText = prompt?.trim();
  final hasPrompt = promptText != null && promptText.isNotEmpty;

  if (words.isEmpty && !hasPrompt) return null;

  final map = <String, dynamic>{};
  if (words.isNotEmpty) {
    map['hotwords'] = words.map((w) => {'word': w}).toList();
  }
  if (hasPrompt) {
    map['context_type'] = 'dialog_ctx';
    map['context_data'] = [
      {'text': promptText},
    ];
  }
  return jsonEncode(map);
}

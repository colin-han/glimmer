/// API 费用估算常量。
///
/// 单价来源：火山引擎控制台。实际价格以控制台为准，此处为估算值。
class ApiPricing {
  ApiPricing._();

  // LLM (Doubao) — 输入/输出价格不同（¥/百万 tokens）
  static const double llmInputPricePerMillion = 0.8;
  static const double llmOutputPricePerMillion = 2.0;

  // ASR — 按小时（¥/小时）
  static const double asrPricePerHour = 1.5;

  // TTS — 按万字符（¥/万字符）
  static const double ttsPricePerTenThousandChars = 1.5;

  /// 估算 LLM 费用（元）
  static double estimateLlmCost({
    required int promptTokens,
    required int completionTokens,
  }) {
    return (promptTokens * llmInputPricePerMillion / 1000000) +
        (completionTokens * llmOutputPricePerMillion / 1000000);
  }

  /// 估算 ASR 费用（元）
  static double estimateAsrCost(int durationSeconds) {
    return durationSeconds * asrPricePerHour / 3600;
  }

  /// 估算 TTS 费用（元）
  static double estimateTtsCost(int characterCount) {
    return characterCount * ttsPricePerTenThousandChars / 10000;
  }
}
